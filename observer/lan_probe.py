# SPDX-License-Identifier: Apache-2.0
"""Root-approved IPv4 LAN probes. Fixed target IDs, no shell or user authentication."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import ssl
import sys
import time
import uuid
from .transport import ObserverError, bounded, decode_json, identifier, read_private_json


def _ipv4(value):
    try:
        address = ipaddress.ip_address(value)
    except (ValueError, TypeError):
        raise ObserverError('IPV4_REQUIRED') from None
    if address.version != 4 or str(address) != value or address.is_multicast or address.is_unspecified:
        raise ObserverError('IPV4_REQUIRED')
    return value


def validate_config(c):
    fields = {'schema_version', 'enabled', 'probe_id', 'source', 'interface', 'gateway', 'baseline_revision', 'targets'}
    if type(c) is not dict or set(c) != fields or type(c['schema_version']) is not int or c['schema_version'] != 1:
        raise ObserverError('PROBE_CONFIG_INVALID')
    identifier(c['probe_id'])
    if (type(c['enabled']) is not bool or type(c['baseline_revision']) is not int or c['baseline_revision'] < 1
            or not isinstance(c['interface'], str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}', c['interface'])
            or c['interface'] == 'lo' or c['interface'].startswith(('wt', 'tun', 'wg'))):
        raise ObserverError('PROBE_CONFIG_INVALID')
    _ipv4(c['source']); _ipv4(c['gateway'])
    if type(c['targets']) is not dict or not 1 <= len(c['targets']) <= 32:
        raise ObserverError('PROBE_CONFIG_INVALID')
    for target_id, target in c['targets'].items():
        identifier(target_id)
        if type(target) is not dict or set(target) != {'address', 'port', 'protocol', 'timeout_ms'}:
            raise ObserverError('TARGET_INVALID')
        _ipv4(target['address'])
        if (type(target['port']) is not int or not 1 <= target['port'] <= 65535
                or not isinstance(target['protocol'], str) or target['protocol'] not in {'tcp', 'rdp', 'http', 'https'}
                or type(target['timeout_ms']) is not int or not 100 <= target['timeout_ms'] <= 5000):
            raise ObserverError('TARGET_INVALID')
    return c


def route_matches(route, config):
    return (type(route) is dict and route.get('dev') == config['interface']
            and route.get('gateway') == config['gateway']
            and route.get('from', route.get('prefsrc', route.get('src'))) == config['source'])


def attestation_valid(receipt, binding, now):
    return (type(receipt) is dict and all(type(receipt.get(k)) is type(v) and receipt[k] == v for k, v in binding.items())
            and type(receipt.get('verified_at')) is int and type(receipt.get('expires_at')) is int
            and receipt['verified_at'] <= now <= receipt['expires_at'] <= receipt['verified_at'] + 30 * 86400
            and isinstance(receipt.get('evidence_sha256'), str)
            and re.fullmatch(r'[a-f0-9]{64}', receipt['evidence_sha256']) is not None)


def validate_result(result, expected, *, now, max_age, previous=None):
    source = previous.get('last_source') if type(previous) is dict else None
    unknown = dict(status='UNKNOWN', fresh=False, reason='PROBE_RESULT_INVALID', last_source=source)
    if (type(result) is not dict or type(result.get('schema_version')) is not int or result['schema_version'] != 1
            or not all(type(result.get(k)) is type(v) and result[k] == v for k, v in expected.items())
            or not all(isinstance(result.get(k), str) and 0 < len(result[k]) <= 128 for k in ('boot_id', 'run_id'))
            or type(result.get('sampled_at')) is not int or not 0 <= now - result['sampled_at'] <= max_age
            or not isinstance(result.get('status'), str) or result['status'] not in {'PASS', 'FAIL', 'UNKNOWN'}):
        return unknown
    if source and ((source['run_id'] == result['run_id'] and
            (source['boot_id'] != result['boot_id'] or source['sampled_at'] != result['sampled_at'])) or
            source['boot_id'] == result['boot_id'] and result['sampled_at'] < source['sampled_at']):
        return dict(unknown, reason='PROBE_REPLAY')
    if result['status'] == 'UNKNOWN':
        public_causes = {'PROBE_DISABLED', 'CAPABILITY_MISSING', 'PATH_NOT_ATTESTED', 'LAN_ROUTE_MISMATCH',
                         'PROBE_UNAVAILABLE', 'COMMAND_TIMEOUT', 'COMMAND_UNAVAILABLE', 'OUTPUT_LIMIT',
                         'PROCESS_DRAIN_FAILED'}
        reason = result.get('reason')
        return dict(unknown, reason=reason if isinstance(reason, str) and reason in public_causes else 'PROBE_UNVERIFIED')
    if result.get('path_verified') is not True or not route_matches(result.get('route'), expected):
        return unknown
    # Export approved fields only; remote payload cannot inject arbitrary event details.
    return dict(status=result['status'], fresh=True,
                last_source={k: result[k] for k in ('boot_id', 'run_id', 'sampled_at')}, reason=result.get('reason') if
                isinstance(result.get('reason'), str) and re.fullmatch(r'[A-Z_]{1,64}', result['reason']) else None,
                **{k: result[k] for k in ('probe_id', 'target_id', 'source', 'interface', 'gateway', 'address',
                                         'port', 'protocol', 'timeout_ms', 'baseline_revision', 'boot_id', 'run_id', 'sampled_at')},
                **_diagnostics(result))


def _diagnostics(result):
    # Optional, additive and bounded; absent or malformed values are dropped, never trusted.
    out = {}
    elapsed = result.get('elapsed_ms')
    if type(elapsed) is int and 0 <= elapsed <= 600000:
        out['elapsed_ms'] = elapsed
    failure = result.get('failure')
    if result.get('status') == 'FAIL' and isinstance(failure, str) and _FAILURE_DETAIL.fullmatch(failure):
        out['failure'] = failure
    return out


def _remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise TimeoutError()
    return seconds


def rdp_confirm(data):
    return (len(data) == 19 and data[:5] == b'\x03\x00\x00\x13\x0e' and data[5] == 0xd0
            and data[10] == 0 and data[11] == 2 and data[13:15] == b'\x08\x00'
            and int.from_bytes(data[15:19], 'little') in (1, 2))


def _exchange(c, target, deadline):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as raw:
        raw.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, c['interface'].encode() + b'\0')
        raw.bind((c['source'], 0))
        raw.settimeout(_remaining(deadline))
        raw.connect((target['address'], target['port']))
        if target['protocol'] == 'tcp':
            return
        stream = raw
        if target['protocol'] == 'https':
            raw.settimeout(_remaining(deadline))
            stream = ssl.create_default_context().wrap_socket(raw, server_hostname=target['address'])
        try:
            stream.settimeout(_remaining(deadline))
            if target['protocol'] in {'http', 'https'}:
                stream.sendall(('HEAD / HTTP/1.1\r\nHost: ' + target['address'] + '\r\nConnection: close\r\n\r\n').encode())
                data = bytearray()
                while b'\r\n' not in data and len(data) <= 8192:
                    stream.settimeout(_remaining(deadline))
                    block = stream.recv(min(1024, 8193 - len(data)))
                    if not block:
                        break
                    data.extend(block)
                line = bytes(data).split(b'\r\n', 1)[0]
                if (b'\r\n' not in data or len(line) > 8192
                        or not re.fullmatch(rb'HTTP/1\.[01] 2[0-9][0-9](?: [\x20-\x7e]*)?', line)):
                    raise ObserverError('HTTP_STATUS_FAILED')
            else:
                # X.224 connection request + TLS negotiation only. No RDP login/password.
                stream.sendall(bytes.fromhex('030000130ee000000000000100080003000000'))
                data = bytearray()
                while len(data) < 19:
                    stream.settimeout(_remaining(deadline))
                    block = stream.recv(19 - len(data))
                    if not block:
                        break
                    data.extend(block)
                if not rdp_confirm(data):
                    raise ObserverError('RDP_NEGOTIATION_FAILED')
        finally:
            if stream is not raw:
                stream.close()


_FAILURE_DETAIL = re.compile(r'(?:E[A-Z0-9]{1,30}|TIMEOUT|TLS|HTTP_STATUS|RDP_NEGOTIATION)')


def _failure_detail(error):
    # Bounded diagnostic only: an errno name, never a message or remote payload.
    import errno
    if isinstance(error, ssl.SSLError):
        return 'TLS'
    if isinstance(error, ObserverError):
        return {'HTTP_STATUS_FAILED': 'HTTP_STATUS', 'RDP_NEGOTIATION_FAILED': 'RDP_NEGOTIATION'}.get(error.code)
    if isinstance(error, OSError) and error.errno in errno.errorcode:
        return errno.errorcode[error.errno]
    if isinstance(error, TimeoutError):
        return 'TIMEOUT'
    return None


def probe(c, target_id, attestations):
    validate_config(c); identifier(target_id)
    if target_id not in c['targets']:
        raise ObserverError('TARGET_NOT_APPROVED')
    target = c['targets'][target_id]
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    binding = dict(probe_id=c['probe_id'], boot_id=boot, target_id=target_id, source=c['source'],
                   interface=c['interface'], gateway=c['gateway'], baseline_revision=c['baseline_revision'], **target)
    result = dict(schema_version=1, **binding, run_id=str(uuid.uuid4()), sampled_at=int(time.time()),
                  status='UNKNOWN', reason='PROBE_DISABLED', path_verified=False, route=None)
    if not c['enabled']:
        return result
    if os.geteuid() != 0 or not hasattr(socket, 'SO_BINDTODEVICE'):
        result['reason'] = 'CAPABILITY_MISSING'; return result
    receipt = attestations.get(target_id) if type(attestations) is dict else None
    if not attestation_valid(receipt, binding, result['sampled_at']):
        result['reason'] = 'PATH_NOT_ATTESTED'; return result
    started = time.monotonic()
    deadline = started + target['timeout_ms'] / 1000
    try:
        route = bounded(['/usr/sbin/ip', '-j', '-4', 'route', 'get', target['address'], 'from', c['source']],
                        min(.5, _remaining(deadline)), 8192)
        routes = decode_json(route['stdout']) if route['exit'] == 0 else None
        if type(routes) is not list or len(routes) != 1 or not route_matches(routes[0], c):
            result['reason'] = 'LAN_ROUTE_MISMATCH'; return result
        result['route'] = {k: routes[0][k] for k in ('dev', 'gateway', 'from', 'prefsrc', 'src') if k in routes[0]}
        result['path_verified'] = True
        try:
            _exchange(c, target, deadline)
        finally:
            result['elapsed_ms'] = max(0, round((time.monotonic() - started) * 1000))
        result.update(status='PASS', reason=None)
    except ssl.SSLError as error:
        result.update(status='FAIL', reason='TLS_FAILED', failure=_failure_detail(error))
    except (TimeoutError, ConnectionError) as error:
        result.update(status='FAIL', reason='CONNECT_FAILED', failure=_failure_detail(error))
    except ObserverError as error:
        result.update(status='FAIL' if error.code in {'HTTP_STATUS_FAILED', 'RDP_NEGOTIATION_FAILED'} else 'UNKNOWN', reason=error.code,
                      failure=_failure_detail(error))
    except OSError as error:
        result['failure'] = _failure_detail(error)
        # A local privilege/configuration failure is not proof of a broken business path.
        import errno
        result.update(status='FAIL' if error.errno in {errno.ECONNREFUSED, errno.ETIMEDOUT, errno.EHOSTUNREACH, errno.ENETUNREACH}
                      else 'UNKNOWN', reason='CONNECT_FAILED' if error.errno in
                      {errno.ECONNREFUSED, errno.ETIMEDOUT, errno.EHOSTUNREACH, errno.ENETUNREACH} else 'PROBE_UNAVAILABLE')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--attestations', required=True)
    parser.add_argument('target_id', nargs='?')
    args = parser.parse_args()
    try:
        if sys.platform != 'linux':
            raise ObserverError('CAPABILITY_MISSING')
        forced = os.environ.get('SSH_ORIGINAL_COMMAND')
        if forced is not None:
            match = re.fullmatch(r'netbird-health probe-v1 ([A-Za-z0-9][A-Za-z0-9_.:-]{0,95})', forced)
            if not match or args.target_id is not None:
                raise ObserverError('COMMAND_DENIED')
            target_id = match[1]
        elif args.target_id is not None and os.geteuid() == 0:
            target_id = args.target_id
        else:
            raise ObserverError('COMMAND_DENIED')
        print(json.dumps(probe(read_private_json(args.config), target_id, read_private_json(args.attestations)), allow_nan=False))
        return 0
    except (ObserverError, OSError, ValueError) as error:
        print(json.dumps(dict(schema_version=1, ok=False, reason=error.code if isinstance(error, ObserverError) else 'PROBE_UNAVAILABLE')))
        return 2


if __name__ == '__main__':
    sys.exit(main())

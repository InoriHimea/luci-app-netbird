# SPDX-License-Identifier: Apache-2.0
import copy
import unittest
import os
import socket
import sys
import threading
import time
from observer.lan_probe import validate_config, validate_result, route_matches, attestation_valid
from observer.transport import ObserverError


def config():
    return dict(schema_version=1, enabled=True, probe_id='lan-west', source='192.0.2.2',
                interface='lan0', gateway='192.0.2.1', baseline_revision=3,
                targets={'rdp-a': dict(address='198.51.100.2', port=3389, protocol='rdp', timeout_ms=1000)})


def binding():
    c = config()
    return dict(probe_id=c['probe_id'], boot_id='boot1', target_id='rdp-a', source=c['source'],
                interface=c['interface'], gateway=c['gateway'], baseline_revision=3,
                **c['targets']['rdp-a'])


class LanBoundaryTests(unittest.TestCase):
    def test_rejects_shell_protocol_ipv6_and_unapproved_metadata(self):
        for mutate in [lambda c: c['targets']['rdp-a'].update(protocol='shell'),
                       lambda c: c.update(source='::1'),
                       lambda c: c['targets']['rdp-a'].update(address='example.org'),
                       lambda c: c['targets']['rdp-a'].update(command='reboot'),
                       lambda c: c.update(interface='lan0; reboot'),
                       lambda c: c['targets']['rdp-a'].update(timeout_ms=True)]:
            c = config(); mutate(c)
            with self.assertRaises(ObserverError):
                validate_config(c)

    def test_natural_route_must_match_all_three_constraints(self):
        route = dict(dev='lan0', gateway='192.0.2.1', **{'from': '192.0.2.2'})
        self.assertTrue(route_matches(route, config()))
        for field, value in [('dev', 'wt0'), ('gateway', '192.0.2.9'), ('from', '192.0.2.9')]:
            wrong = dict(route); wrong[field] = value
            self.assertFalse(route_matches(wrong, config()))
        self.assertFalse(route_matches({'dev': 'lan0'}, config()))

    def test_path_receipt_bound_to_boot_target_and_revision(self):
        b = binding(); receipt = dict(b, verified_at=90, expires_at=110, evidence_sha256='a'*64)
        self.assertTrue(attestation_valid(receipt, b, 100))
        for field, value in [('boot_id', 'boot2'), ('target_id', 'rdp-b'), ('baseline_revision', 4),
                             ('gateway', '192.0.2.3'), ('expires_at', 99), ('verified_at', 101),
                             ('evidence_sha256', 'not-a-digest')]:
            wrong = dict(receipt); wrong[field] = value
            self.assertFalse(attestation_valid(wrong, b, 100))

    def test_pass_requires_fresh_independent_identity_and_path_binding(self):
        b = binding()
        result = dict(schema_version=1, **b, run_id='r1', sampled_at=100, status='PASS', reason=None,
                      path_verified=True, route=dict(dev='lan0', gateway='192.0.2.1', **{'from': '192.0.2.2'}))
        expected = dict(b); expected.pop('boot_id')
        self.assertEqual(validate_result(result, expected, now=101, max_age=30)['status'], 'PASS')
        for field, value in [('probe_id', 'router'), ('source', '100.64.0.1'), ('sampled_at', 0),
                             ('sampled_at', 200), ('path_verified', False), ('baseline_revision', 2),
                             ('status', ['PASS'])]:
            wrong = copy.deepcopy(result); wrong[field] = value
            self.assertEqual(validate_result(wrong, expected, now=101, max_age=30)['status'], 'UNKNOWN')

    def test_rdp_refusal_and_plain_confirmation_are_not_pass(self):
        from observer.lan_probe import rdp_confirm
        good = bytes.fromhex('030000130ed000000000000200080001000000')
        self.assertTrue(rdp_confirm(good))
        self.assertFalse(rdp_confirm(bytes.fromhex('030000130ed000000000000300080005000000')))
        self.assertFalse(rdp_confirm(bytes.fromhex('0300000b06d00000000000')))
        self.assertFalse(rdp_confirm(good[:-1]))
        self.assertFalse(rdp_confirm(good + b'junk'))

    def test_lan_run_relabel_and_boot_reuse_are_unknown_even_after_failed_poll(self):
        b = binding(); expected = dict(b); expected.pop('boot_id')
        first = dict(schema_version=1, **b, run_id='r1', sampled_at=100, status='PASS', reason=None,
                     path_verified=True, route=dict(dev='lan0', gateway='192.0.2.1', **{'from': '192.0.2.2'}))
        previous = validate_result(first, expected, now=100, max_age=30)
        failed = validate_result(None, expected, now=101, max_age=30, previous=previous)
        for changes in [dict(sampled_at=102), dict(boot_id='boot2'), dict(run_id='r2', sampled_at=99)]:
            replay = dict(first, **changes)
            self.assertEqual(validate_result(replay, expected, now=102, max_age=30, previous=failed)['status'], 'UNKNOWN')
        fresh = dict(first, run_id='r2', sampled_at=102)
        self.assertEqual(validate_result(fresh, expected, now=102, max_age=30, previous=failed)['status'], 'PASS')

    def test_unknown_reasons_are_preserved_from_a_fixed_public_vocabulary(self):
        b = binding(); expected = dict(b); expected.pop('boot_id')
        result = dict(schema_version=1, **b, run_id='r1', sampled_at=100, status='UNKNOWN',
                      reason='PATH_NOT_ATTESTED', path_verified=False, route=None)
        validated = validate_result(result, expected, now=101, max_age=30)
        self.assertEqual(validated['reason'], 'PATH_NOT_ATTESTED')
        self.assertEqual(validated['status'], 'UNKNOWN')
        result['reason'] = 'PRIVATE_PAYLOAD'
        self.assertEqual(validate_result(result, expected, now=101, max_age=30)['reason'], 'PROBE_UNVERIFIED')


@unittest.skipUnless(sys.platform == 'linux' and os.geteuid() == 0, 'Linux root LAN socket contract')
class HttpResponseBoundaryTests(unittest.TestCase):
    def test_unterminated_status_line_at_eof_or_limit_cannot_pass(self):
        from observer.lan_probe import _exchange
        with socket.socket() as capability:
            try:
                capability.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'lo\0')
            except PermissionError:
                self.skipTest('SO_BINDTODEVICE unavailable')
        for response in (b'HTTP/1.1 200', b'HTTP/1.1 200 ' + b' '*8192):
            with self.subTest(response_bytes=len(response)), socket.socket() as listener:
                listener.bind(('127.0.0.1', 0)); listener.listen(1); listener.settimeout(2)
                def serve():
                    connection, _ = listener.accept()
                    with connection:
                        connection.settimeout(2); connection.recv(4096); connection.sendall(response)
                thread = threading.Thread(target=serve, daemon=True); thread.start()
                try:
                    with self.assertRaisesRegex(ObserverError, 'HTTP_STATUS_FAILED'):
                        _exchange(dict(interface='lo', source='127.0.0.1'),
                                  dict(address='127.0.0.1', port=listener.getsockname()[1], protocol='http'),
                                  time.monotonic()+1)
                finally:
                    thread.join(timeout=2)


class DiagnosticsTests(unittest.TestCase):
    def result(self, **extra):
        b = binding()
        r = dict(schema_version=1, **b, run_id='r1', sampled_at=100, status='FAIL', reason='CONNECT_FAILED',
                 path_verified=True, route=dict(dev='lan0', gateway='192.0.2.1', **{'from': '192.0.2.2'}))
        r.update(extra)
        expected = dict(b); expected.pop('boot_id')
        return validate_result(r, expected, now=101, max_age=30)

    def test_failure_errno_and_elapsed_are_exported_when_bounded(self):
        v = self.result(failure='ECONNREFUSED', elapsed_ms=3)
        self.assertEqual((v['status'], v['failure'], v['elapsed_ms']), ('FAIL', 'ECONNREFUSED', 3))

    def test_malformed_or_injected_diagnostics_are_dropped(self):
        for extra in [dict(failure='connection refused by host'), dict(failure='E' * 40), dict(failure=['ETIMEDOUT']),
                      dict(elapsed_ms=-1), dict(elapsed_ms=10**9), dict(elapsed_ms=1.5), dict(elapsed_ms=True)]:
            v = self.result(**extra)
            self.assertEqual(v['status'], 'FAIL')
            self.assertNotIn('failure', v); self.assertNotIn('elapsed_ms', v)

    def test_pass_never_carries_failure_detail(self):
        v = self.result(status='PASS', reason=None, failure='ETIMEDOUT', elapsed_ms=40)
        self.assertEqual(v['status'], 'PASS'); self.assertNotIn('failure', v); self.assertEqual(v['elapsed_ms'], 40)

    def test_legacy_result_without_diagnostics_still_validates(self):
        v = self.result()
        self.assertEqual(v['status'], 'FAIL'); self.assertNotIn('failure', v)

    def test_failure_detail_names_errno_not_message(self):
        import errno, ssl
        from observer.lan_probe import _failure_detail
        # Linux names; on Windows the same numbers map to WSAE* names via errno.errorcode.
        self.assertEqual(_failure_detail(ConnectionRefusedError(errno.ECONNREFUSED, 'secret text')), errno.errorcode[errno.ECONNREFUSED])
        self.assertEqual(_failure_detail(OSError(errno.EHOSTUNREACH, 'x')), errno.errorcode[errno.EHOSTUNREACH])
        self.assertEqual(_failure_detail(socket.timeout('timed out')), 'TIMEOUT')
        self.assertEqual(_failure_detail(ssl.SSLError(1, 'bad')), 'TLS')
        self.assertEqual(_failure_detail(ObserverError('RDP_NEGOTIATION_FAILED')), 'RDP_NEGOTIATION')


if __name__ == '__main__':
    unittest.main()

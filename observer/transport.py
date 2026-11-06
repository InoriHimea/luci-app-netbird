# SPDX-License-Identifier: Apache-2.0
"""Linux-only bounded transport; no shell, password fallback or host-key bypass."""
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import tempfile
import time

LIMIT = 1048576
ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}\Z')


class ObserverError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def identifier(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ObserverError('ID_INVALID')
    return value


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ObserverError('JSON_DUPLICATE_KEY')
        result[key] = value
    return result


def _finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise ObserverError('JSON_INVALID')
    return value


def decode_json(data):
    if len(data) > LIMIT:
        raise ObserverError('OUTPUT_LIMIT')
    try:
        return json.loads(data, object_pairs_hook=_object, parse_float=_finite_float,
                          parse_constant=lambda _: (_ for _ in ()).throw(ObserverError('JSON_INVALID')))
    except (ValueError, UnicodeError, RecursionError):
        raise ObserverError('JSON_INVALID') from None


def private_directory(path, create=False):
    path = Path(path)
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise ObserverError('PRIVATE_DIRECTORY_REQUIRED')
    return path


def read_private_json(path):
    path = Path(path)
    private_directory(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077 or info.st_size > LIMIT:
            raise ObserverError('PRIVATE_FILE_REQUIRED')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            return decode_json(stream.read(LIMIT + 1))
    finally:
        os.close(fd)


def atomic_json(path, value):
    path = Path(path)
    directory = private_directory(path.parent, create=True)
    if path.is_symlink():
        raise ObserverError('PRIVATE_FILE_REQUIRED')
    if path.exists():
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
            raise ObserverError('PRIVATE_FILE_REQUIRED')
    data = (json.dumps(value, separators=(',', ':'), allow_nan=False) + '\n').encode()
    if len(data) > LIMIT:
        raise ObserverError('STATE_LIMIT')
    fd, name = tempfile.mkstemp(prefix='.observer-', dir=directory)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def bounded(argv, timeout, limit=262144):
    if os.name != 'posix' or timeout <= 0:
        raise ObserverError('CAPABILITY_MISSING' if os.name != 'posix' else 'COMMAND_TIMEOUT')
    try:
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True, close_fds=True,
                                 env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C', 'LC_ALL': 'C'})
    except OSError:
        raise ObserverError('COMMAND_UNAVAILABLE') from None
    streams = {'stdout': bytearray(), 'stderr': bytearray()}
    selector = selectors.DefaultSelector()
    deadline = time.monotonic() + timeout
    try:
        for name, stream in (('stdout', child.stdout), ('stderr', child.stderr)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ObserverError('COMMAND_TIMEOUT')
            for key, _ in selector.select(remaining):
                data = os.read(key.fd, min(16384, limit + 1))
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                streams[key.data].extend(data)
                if sum(map(len, streams.values())) > limit:
                    raise ObserverError('OUTPUT_LIMIT')
        # WNOWAIT keeps the leader PID reserved until its entire group is drained.
        while True:
            status = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if status is not None:
                code = status.si_status if status.si_code == os.CLD_EXITED else -status.si_status
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ObserverError('COMMAND_TIMEOUT')
            time.sleep(min(remaining, 0.01))
        return dict(exit=code, stdout=bytes(streams['stdout']), stderr=bytes(streams['stderr']))
    finally:
        # Also drain any descendants after a leader that closed its pipes/exited.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            raise ObserverError('PROCESS_DRAIN_FAILED') from None
        finally:
            selector.close()
            child.stdout.close()
            child.stderr.close()


def validate_ssh(spec):
    fields = {'host', 'port', 'user', 'identity_file', 'known_hosts_file'}
    if type(spec) is not dict or set(spec) != fields:
        raise ObserverError('SSH_CONFIG_INVALID')
    host = spec['host']
    if not isinstance(host, str) or len(host) > 253:
        raise ObserverError('SSH_CONFIG_INVALID')
    try:
        ipaddress.ip_address(host)
    except ValueError:
        if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', host):
            raise ObserverError('SSH_CONFIG_INVALID') from None
    if (type(spec['port']) is not int or not 1 <= spec['port'] <= 65535 or
            not isinstance(spec['user'], str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]{0,31}', spec['user'])):
        raise ObserverError('SSH_CONFIG_INVALID')
    for key in ('identity_file', 'known_hosts_file'):
        value = spec[key]
        if not isinstance(value, str) or not value.startswith('/') or len(value) > 1024 or any(ord(c) < 32 for c in value):
            raise ObserverError('SSH_CONFIG_INVALID')
    return spec


def ssh_json(spec, timeout, target_id=None):
    validate_ssh(spec)
    command = 'netbird-health snapshot-v1' if target_id is None else 'netbird-health probe-v1 ' + identifier(target_id)
    argv = ['/usr/bin/ssh', '-F', '/dev/null', '-oBatchMode=yes', '-oStrictHostKeyChecking=yes',
            '-oConnectTimeout=2', '-oConnectionAttempts=1', '-oClearAllForwardings=yes',
            '-oLogLevel=ERROR', '-oIdentitiesOnly=yes', '-oPasswordAuthentication=no',
            '-oKbdInteractiveAuthentication=no', '-oUserKnownHostsFile=' + spec['known_hosts_file'],
            '-oGlobalKnownHostsFile=/dev/null', '-oUpdateHostKeys=no',
            '-p', str(spec['port']), '-l', spec['user'], '-i', spec['identity_file'], spec['host'], command]
    result = bounded(argv, timeout)
    if result['exit'] != 0:
        # Authentication/host-key failure is not evidence that a node powered off.
        network = any(text in result['stderr'] for text in
                      (b'Connection refused', b'Connection timed out', b'No route to host', b'Network is unreachable'))
        raise ObserverError('NODE_UNREACHABLE' if network else 'COLLECTION_FAILED')
    return decode_json(result['stdout'])

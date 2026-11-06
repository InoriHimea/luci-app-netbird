// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, open, unlink, rmdir, access } from 'fs';

const LIMIT = 65536;
// Constant shell program; command arguments are positional, never interpolated.
// setsid makes the recorded PID the process-group leader. Always drain the
// group, including after a successful command that left descendants behind.
const LAUNCH = 'umask 077; echo $$ > "$1/pid"; ulimit -f 128 || exit 125; d="$1"; shift; exec "$@" > "$d/out" 2> "$d/err"';
// Only trusted system tools are allowed: no daemonization/setsid descendants.
const DRAIN = 'kill -0 "-$1" 2>/dev/null || exit 0; kill -9 "-$1" 2>/dev/null';
function monotonic_ms() {
    let t = clock(true);
    return t[0] * 1000 + int(t[1] / 1000000);
}
function bounded_read(path, size) {
    let f = open(path, 'r');
    if (!f) return '';
    let s = f.read(size) || '';
    f.close();
    return s;
}
// Internal primitive only: callers must select fixed read-only tool argv.
// No command/path from RPC or UCI may be passed through to this function.
function run_command(argv, timeout_ms) {
    let start = monotonic_ms();
    let result = { ok: false, reason: 'RUNNER_ERROR', exit_code: null,
        stdout: '', output_bytes: 0, json_unsupported: false, duration_ms: 0 };
    if (type(timeout_ms) != 'int' || timeout_ms <= 0 || timeout_ms > 20000)
        return result;
    if (type(argv) != 'array' || !length(argv) || type(argv[0]) != 'string')
        return result;
    for (let arg in argv)
        if (type(arg) != 'string' || index(arg, '\x00') >= 0) return result;
    if (!access(argv[0], 'x')) {
        result.reason = 'TOOL_MISSING';
        return result;
    }
    let dir = mkdtemp('/tmp/netbird-health-cmd.XXXXXX');
    if (!dir) return result;
    let rc = null, pid = '', drained = false;
    try {
        let cmd = ['/bin/busybox', 'setsid', '/bin/sh', '-c', LAUNCH, 'health-command', dir];
        for (let arg in argv) push(cmd, arg);
        // Reserve bounded cleanup time within the requested execution budget.
        rc = system(cmd, max(1, timeout_ms - min(100, int(timeout_ms / 4))));
        result.stdout = bounded_read(dir + '/out', LIMIT);
        let stderr = bounded_read(dir + '/err', LIMIT);
        result.output_bytes = length(result.stdout) + length(stderr);
        result.json_unsupported =
            (rc == 255 && trim(stderr) == 'Option "-j" is unknown, try "ip -help".') ||
            (rc == 1 && index(stderr, "ip: invalid option -- 'j'\nBusyBox ") == 0);
        result.exit_code = rc >= 0 ? rc : null;
        if (length(result.stdout) >= LIMIT || length(stderr) >= LIMIT)
            result.reason = 'OUTPUT_LIMIT';
        else if (rc == -9)
            result.reason = 'TIMEOUT';
        else if (rc != 0)
            result.reason = 'COMMAND_FAILED';
        else {
            result.ok = true;
            result.reason = null;
        }
    }
    catch (e) {
        // Do not expose raw command output or exception text to RPC/logs.
        result.reason = 'RUNNER_ERROR';
    }
    // Cleanup also runs after decoding/read errors. The PID is published
    // before exec; absence cannot be treated as a successful invocation.
    try {
        pid = bounded_read(dir + '/pid', 32);
        if (match(pid, /^[0-9]+\n$/) && int(pid) > 1)
            drained = system(['/bin/sh', '-c', DRAIN, 'health-cleanup', '' + int(pid)], 100) == 0;
    }
    catch (e) { drained = false; }
    if (!drained) {
        result.ok = false;
        if (result.reason != 'TIMEOUT') result.reason = 'CLEANUP_UNCONFIRMED';
    }
    for (let name in ['pid', 'out', 'err']) unlink(dir + '/' + name);
    rmdir(dir);
    result.duration_ms = monotonic_ms() - start;
    if (result.duration_ms > timeout_ms) {
        result.ok = false;
        result.reason = 'TIMEOUT';
    }
    return result;
}
export { run_command, monotonic_ms };

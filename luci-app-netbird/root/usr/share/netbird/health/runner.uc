// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, open, unlink, rmdir, access, glob, lstat } from 'fs';
import { private_dir } from './storage.uc';

const LIMIT = 65536;
// Constant shell program; command arguments are positional, never interpolated.
// setsid makes the recorded PID the process-group leader. Always drain the
// group, including after a successful command that left descendants behind.
// Arm before exec: killing the collecting worker must not strand a command.
// ucode sleep supports milliseconds on builds whose BusyBox sleep does not.
const GUARD = 'import {open,unlink} from "fs"; '
    + 'let d=ARGV[2], lease=open("/tmp/netbird-health/commands.lock","a",0600); '
    + 'let f=lease && lease.lock("s") ? open(d+"/armed","wx",0600) : null; '
    + 'if(f){f.close();let t=clock(true);sleep(max(0,int(ARGV[0])-t[0]*1000-int(t[1]/1000000)));} '
    + 'for(let n in ["out","err","armed"])unlink(d+"/"+n); '
    + 'system(["/bin/busybox","kill","-9","-"+ARGV[1]],100);';
const LAUNCH = 'umask 077; echo $$ > "$1/pid"; ulimit -f 128 || exit 125; d="$1"; '
    + '/usr/bin/ucode -e "$2" "$3" "$$" "$d" </dev/null >/dev/null 2>&1 & g=$!; '
    + 'while [ ! -f "$d/armed" ]; do kill -0 "$g" 2>/dev/null || exit 125; done; '
    + 'export NB_HEALTH_DEADLINE_MS="$3"; shift 3; exec "$@" > "$d/out" 2> "$d/err"';
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
// Internal primitive: fixed system tools and caller-validated operands only.
// Collection callers are read-only; the notification worker owns the explicit
// approved POST. Never pass arbitrary RPC commands, paths or targets here.
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
    let inherited = getenv('NB_HEALTH_DEADLINE_MS');
    if (inherited != null) {
        if (!match(inherited, /^[0-9]+$/)) return result;
        timeout_ms = min(timeout_ms, int(inherited) - start);
        if (timeout_ms <= 0) { result.reason = 'TIMEOUT'; return result; }
    }
    if (!private_dir('/tmp/netbird-health')) return result;
    let lease = open('/tmp/netbird-health/commands.lock', 'a', 0600);
    if (!lease || !lease.lock('s')) { lease?.close(); return result; }
    if (!access(argv[0], 'x')) {
        result.reason = 'TOOL_MISSING';
        lease.close();
        return result;
    }
    let dir = mkdtemp('/tmp/netbird-health-cmd.XXXXXX');
    if (!dir) { lease.close(); return result; }
    let rc = null, pid = '', drained = false;
    try {
        let budget = max(1, timeout_ms - min(100, int(timeout_ms / 4)));
        let cmd = ['/bin/busybox', 'setsid', '/bin/sh', '-c', LAUNCH, 'health-command', dir, GUARD, '' + (start + budget)];
        for (let arg in argv) push(cmd, arg);
        // Reserve bounded cleanup time within the requested execution budget.
        rc = system(cmd, budget);
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
    for (let name in ['pid', 'out', 'err', 'armed']) unlink(dir + '/' + name);
    rmdir(dir);
    lease.close();
    result.duration_ms = monotonic_ms() - start;
    if (result.duration_ms > timeout_ms) {
        result.ok = false;
        result.reason = 'TIMEOUT';
    }
    return result;
}

// Exclusive lease proves no live owner or independently armed guard can still
// use these files. Also reclaims pre-arm and post-drain owner-crash windows.
function cleanup_commands() {
    if (!private_dir('/tmp/netbird-health')) return false;
    let lease = open('/tmp/netbird-health/commands.lock', 'a', 0600);
    if (!lease || !lease.lock('xn')) { lease?.close(); return false; }
    for (let dir in glob('/tmp/netbird-health-cmd.*')) {
        let st = lstat(dir);
        if (st?.type != 'directory' || st.uid != 0 || (st.mode & 0777) != 0700) continue;
        let safe = true, files = glob(dir + '/*');
        for (let path in files) {
            let f = lstat(path), name = substr(path, length(dir) + 1);
            if (index(['pid', 'out', 'err', 'armed'], name) < 0 || f?.type != 'file' ||
                f.uid != 0 || (f.mode & 0777) != 0600) safe = false;
        }
        if (!safe) continue;
        for (let path in files) unlink(path);
        rmdir(dir);
    }
    lease.close();
    return true;
}
export { run_command, monotonic_ms, cleanup_commands };

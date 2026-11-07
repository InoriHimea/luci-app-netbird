// SPDX-License-Identifier: Apache-2.0
import { lstat, readfile } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { run_command } from './runner.uc';
const DIR = '/tmp/netbird-actions', NAME = 'watchdog.json';
const PROGRAM = '/usr/share/netbird/netbird-autoreconnect.sh';
function process_stamp(pid) {
    if (type(pid) != 'int' || pid <= 1) return null;
    function start() {
        let m = match(readfile('/proc/' + pid + '/stat') || '', /^([0-9]+) \(.*\) (.+)$/s);
        let fields = m ? split(trim(m[2]), ' ') : [];
        return length(fields) >= 20 && fields[0] != 'Z' && match(fields[19], /^[0-9]+$/) ? fields[19] : null;
    }
    let before = start(), argv = split(readfile('/proc/' + pid + '/cmdline') || '', '\x00');
    if (before == null || index(argv, PROGRAM) < 0 || index(argv, '--action-lease-v1') < 0 || start() != before)
        return null;
    let boot = trim(readfile('/proc/sys/kernel/random/boot_id') || '');
    if (!match(boot, /^[0-9a-f-]{36}$/)) return null;
    return { pid, started: before, boot_id: boot };
}
function instance_stamp(instance) {
    if (instance?.running !== true || type(instance.command) != 'array' ||
        length(instance.command) != 2 || instance.command[0] != PROGRAM || instance.command[1] != '--action-lease-v1')
        return null;
    return process_stamp(instance.pid);
}
function watchdog_coordinated(instance) {
    let current = instance_stamp(instance), st = lstat(DIR + '/' + NAME);
    if (!current || st?.type != 'file' || st.uid != 0 || st.mode != 0600 || st.size > 1024) return false;
    let receipt = read_json(DIR + '/' + NAME, 1024);
    return receipt?.schema_version == 1 && receipt.pid == current.pid &&
        receipt.started == current.started && receipt.boot_id == current.boot_id;
}
// Only the root-only watchdog RPC calls this, after acquiring the shared owner.
// An argv flag alone cannot attest that a partially upgraded script uses leases.
function register_watchdog(pid) {
    if (type(pid) != 'int' || pid <= 1) return false;
    let result = run_command(['/bin/ubus', '-t', '1', 'call', 'service', 'list',
        '{"name":"luci-netbird-watchdog"}'], 1500), services;
    try { services = result.ok ? json(result.stdout) : null; } catch (e) {}
    let instances = services?.['luci-netbird-watchdog']?.instances;
    if (type(instances) != 'object') return false;
    for (let key in keys(instances)) {
        let instance = instances[key];
        if (instance.pid != pid) continue;
        let stamp = instance_stamp(instance);
        if (!stamp || !private_dir(DIR)) return false;
        return atomic_json(DIR, NAME, { schema_version: 1, pid: stamp.pid,
            started: stamp.started, boot_id: stamp.boot_id }, 1024);
    }
    return false;
}
export { register_watchdog, watchdog_coordinated };

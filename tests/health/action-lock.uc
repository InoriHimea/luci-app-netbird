// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, mkdir, readfile, writefile, unlink } from 'fs';
import { atomic_json } from '../../luci-app-netbird/root/usr/share/netbird/health/storage.uc';
const factory = loadfile('./luci-app-netbird/root/usr/share/rpcd/ucode/lib/action_lock.uc')();
let count = 0;
function check(value, message) { if (!value) die(message); count++; }
let root = mkdtemp('/tmp/nbh-action-lock.XXXXXX');
for (let name in ['/tmp', '/proc', '/proc/self', '/proc/sys', '/proc/sys/kernel', '/proc/sys/kernel/random'])
    check(mkdir(root + name, 0700), 'create isolated process view');
let process = readfile('/proc/self/stat'), pid = match(process, /^([0-9]+)/)[1];
check(mkdir(root + '/proc/' + pid, 0700), 'create current owner view');
writefile(root + '/proc/self/stat', process);
writefile(root + '/proc/' + pid + '/stat', process);
let boot = trim(readfile('/proc/sys/kernel/random/boot_id'));
writefile(root + '/proc/sys/kernel/random/boot_id', boot);
let now = 10000, first = factory.create(root, () => now), second = factory.create(root, () => now);
check(first.acquire('manual-recovery').ok, 'one action owns exclusion');
check(second.acquire('watchdog').reason == 'ACTION_BUSY', 'simultaneous watchdog action rejected');
check(first.release(), 'owner releases exact marker');
check(second.acquire('settings').ok && second.release(), 'settings can proceed after completed action');
function orphan(owner, started, saved_boot) {
    let dir = root + '/tmp/nb-binop.lock';
    check(mkdir(dir, 0700), 'create interrupted owner marker');
    writefile(dir + '/owner', owner + '\n');
    check(atomic_json(dir, 'identity.json', { schema_version: 1, id: '0123456789abcdef0123456789abcdef',
        owner: 'manual-recovery', pid: owner, started, boot_id: saved_boot }, 2048), 'publish interrupted owner identity');
}
orphan('999999', '1', boot);
check(second.acquire('watchdog').reason == 'ACTION_DRAIN_PENDING', 'dead parent does not imply stopped children');
let fence_started = now;
now += 599999;
check(second.acquire('watchdog').reason == 'ACTION_DRAIN_PENDING', 'orphan drain fence remains until its full deadline');
now = fence_started - 1;
check(second.acquire('watchdog').reason == 'ACTION_DRAIN_PENDING', 'clock reversal cannot bypass orphan drain');
now = fence_started + 600000;
check(second.acquire('watchdog').ok && second.release(), 'expired bounded orphan fence cannot deadlock later actions');
orphan(pid, '0', boot);
check(!second.available(), 'reused live PID does not impersonate original owner');
now += 600000;
check(second.acquire('manual-recovery').ok && second.release(), 'PID reuse is reclaimable after drain fence');
orphan(pid, '0', '00000000-0000-0000-0000-000000000000');
check(second.acquire('settings').ok && second.release(), 'previous boot marker cannot fence the new boot');
let marker = root + '/tmp/nb-binop.lock';
mkdir(marker, 0755); writefile(marker + '/owner', '999999\n');
check(second.acquire('watchdog').reason == 'ACTION_DRAIN_PENDING', 'legacy 0755 owner marker enters bounded quarantine');
now += 600000;
check(second.acquire('watchdog').ok && second.release(), 'legacy orphan cannot remain permanently locked by private storage validation');
mkdir(marker, 0755); writefile(marker + '/owner', '999999\n');
writefile(marker + '/user-data', 'preserve');
check(second.acquire('manual-recovery').reason == 'ACTION_OWNER_CONFLICT', 'unrecognized external marker data blocks adoption');
check(readfile(marker + '/user-data') == 'preserve', 'external marker contents preserved');
unlink(marker + '/user-data'); unlink(marker + '/owner');
// Recognized stale legacy content can now drain and retire normally.
writefile(marker + '/owner', '999999\n');
check(!second.available(), 'maintenance probe initializes orphan retirement without admitting an action');
now += 600000;
check(second.acquire('settings').ok && second.release(), 'maintenance-probed orphan eventually retires');
mkdir(marker, 0700); writefile(marker + '/owner', 'not-a-pid\n');
check(second.acquire('manual-recovery').reason == 'ACTION_OWNER_UNKNOWN', 'unknown external ownership fails closed');
check(readfile(marker + '/owner') == 'not-a-pid\n', 'unknown ownership is not silently rewritten');
unlink(marker + '/owner');
print(sprintf('action-lock: %d assertions PASS\n', count));

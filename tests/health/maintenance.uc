// SPDX-License-Identifier: Apache-2.0
import { maintenance_state, maintenance_identity } from '../../luci-app-netbird/root/usr/share/netbird/health/maintenance.uc';
import { mkdtemp, mkdir, open, unlink, rmdir } from 'fs';
let n = 0;
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
let root = mkdtemp('/tmp/nbh-maintenance.XXXXXX');
for (let suffix in ['/etc', '/etc/netbird-update', '/tmp']) mkdir(root + suffix, 0700);
function put(path, text) { let f = open(root + path, 'w', 0600); f.write(text); f.close(); }
let r = maintenance_state(root);
check(r.state == 'idle' && r.watchdog.state == 'unknown', 'absence of maintenance markers never proves watchdog inactivity');
put('/etc/netbird-update/transaction.json', '{"phase":"activating"}');
r = maintenance_state(root);
check(r.state == 'active' && r.transaction_phase == 'activating', 'in-flight upgrade observed without invoking recovery');
put('/etc/netbird-update/transaction.json', '{"phase":"committed"}');
check(maintenance_state(root).state == 'idle', 'completed transaction is not an active maintenance lock');
put('/etc/netbird-update/settings.pending', 'pending');
check(maintenance_state(root).state == 'active', 'pending settings remain visible after committed upgrade');
unlink(root + '/etc/netbird-update/settings.pending');
put('/etc/netbird-update/transaction.json', '{');
check(maintenance_state(root).state == 'unknown', 'damaged journal cannot claim maintenance idle');
mkdir(root + '/tmp/nb-binop.lock', 0700);
check(maintenance_state(root).state == 'active', 'binary lock remains active even with unreadable journal');
check(maintenance_identity(maintenance_state(root)).state == 'unknown', 'damaged journal stays unknown in generation identity');
unlink(root + '/etc/netbird-update/transaction.json');
let idle = maintenance_identity(maintenance_state(root));
check(maintenance_state(root).state == 'active' && idle.state == 'idle',
    'transient binary-operation lease keeps maintenance flag but is not generation identity');
rmdir(root + '/tmp/nb-binop.lock');
check(sprintf('%J', maintenance_identity(maintenance_state(root))) == sprintf('%J', idle), 'lease appearing/disappearing leaves identity unchanged');
put('/etc/netbird-settings.pending', 'pending');
check(maintenance_identity(maintenance_state(root)).state == 'active', 'pending settings change generation identity');
unlink(root + '/etc/netbird-settings.pending');
put('/etc/netbird-update/transaction.json', '{"phase":"activating"}');
check(maintenance_identity(maintenance_state(root)).state == 'active', 'in-flight transaction changes generation identity');
unlink(root + '/etc/netbird-update/transaction.json');
for (let suffix in ['/etc/netbird-update', '/etc', '/tmp', '']) rmdir(root + suffix);
printf('PASS: %d maintenance assertions\n', n);

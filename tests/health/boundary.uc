// SPDX-License-Identifier: Apache-2.0
import { difference, freshness } from '../../luci-app-netbird/root/usr/share/netbird/health/boundary.uc';
let count = 0;
function check(ok, label) { if (!ok) die(label + '\n'); count++; }
let previous = { sampled_at: 100, snapshot: { boot_id: 'boot-a', boundaries: { after: {
    processes: [{ pid: 4, start_ticks: '12' }], rules: { ok: true, records: [{ priority: 105 }] },
    routes: { ok: true, records: [] }, links: { ok: true, records: [{ ifindex: 3 }] } } } } };
let current = json(sprintf('%J', previous));
current.snapshot.boundaries.before = current.snapshot.boundaries.after;
current.sampled_at = 101;
current.snapshot.boundaries.before.rules.records = [{ priority: 110 }];
let d = difference(previous, current);
check(d.changes[0].state == 'UNCHANGED' && d.changes[1].state == 'CHANGED', 'same PID does not hide rules reconstruction');
check(d.engine == 'UNKNOWN' && d.attribution == 'cause_undetermined', 'rules changes do not invent engine identity or actor');
current.snapshot.boot_id = 'boot-b';
check(difference(previous, current).boot_changed === true, 'boot boundary explicit');
current.sampled_at = 99;
check(difference(previous, current).wall_clock_reversed, 'wall clock reversal');
function maint(lock, settings) { return { state: lock || settings ? 'active' : 'idle', durable_active: settings, journal_unreadable: false,
    transaction_phase: null, markers: { binary_operation: lock, update_settings: false, settings } }; }
let mp = json(sprintf('%J', previous)), mc = json(sprintf('%J', previous));
mc.snapshot.boundaries.before = json(sprintf('%J', mc.snapshot.boundaries.after));
mp.snapshot.boundaries.after.maintenance = maint(true, false);
mc.snapshot.boundaries.before.maintenance = maint(false, false);
check(difference(mp, mc).changes[5].field == 'maintenance' && difference(mp, mc).changes[5].state == 'UNCHANGED',
    'transient binary-operation lease is not a cross-run maintenance change');
mc.snapshot.boundaries.before.maintenance = maint(false, true);
check(difference(mp, mc).changes[5].state == 'CHANGED', 'pending settings remain a cross-run maintenance change');
let legacy = maint(true, true); delete legacy.durable_active; delete legacy.journal_unreadable;
mp.snapshot.boundaries.after.maintenance = legacy;
check(difference(mp, mc).changes[5].state == 'UNCHANGED', 'snapshot cached before durable fields compares by markers');
check(!freshness(previous, 'boot-b', 101, 60).fresh, 'prior boot not fresh');
check(!freshness(previous, 'boot-a', 99, 60).fresh, 'future sample not fresh');
check(!freshness(previous, 'boot-a', 161, 60).fresh, 'age expires');
check(freshness(previous, 'boot-a', 160, 60).fresh, 'age boundary included');
print('boundary: ', count, ' assertions passed\n');

// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, mkdir, lsdir, unlink, rmdir, lstat } from 'fs';
import { create_alerts } from '../../luci-app-netbird/root/usr/share/netbird/health/alert-runtime.uc';
import { read_json, atomic_json } from '../../luci-app-netbird/root/usr/share/netbird/health/storage.uc';
let n = 0, now = 1000, serial = 0, sends = 0, outcome = { state: 'failed', delivery_state: 'not_submitted', error: 'CONNECT_FAILED' };
function check(ok, label) { if (!ok) die(label + '\n'); n++; }
let root = mkdtemp('/tmp/nbh-alerts.XXXXXX'), persistent = root + '/durable'; mkdir(persistent, 0700);
let config = { revision: 1, node: { stable_node_id: 'fixture', expected_connection_intent: 'connected' },
    monitor: { enabled: true, interval: 30, cycle_timeout: 2 },
    notification: { owner: 'local', sink_ref: 'fixture', failure_threshold: 3, recovery_threshold: 2, reminder: false } };
let maintenance = 'idle';
let alerts = create_alerts(root, persistent, () => config, () => now, event => { sends++; return outcome; }, () => ({ state: maintenance }));
function sample(status, complete) {
    now += 1000; serial++;
    return alerts.record({ snapshot: { complete, reason: complete ? null : 'COMMAND_TIMEOUT' }, run: {
        run_id: 'boot:' + serial, boot_id: 'boot', overall: status == 'FAIL' ? 'unhealthy' : 'healthy', flags: {}, finished_at: 1000 + serial,
        node_id: config.node.stable_node_id, config_revision: config.revision,
        checks: [{ id: 'port', category: 'endpoint', code: 'PORT_CLOSED', status, severity: 'critical', fresh: true, executed: true }] } });
}
check(sample('FAIL', true).ok && sends == 0, 'sampling never submits network requests'); sample('FAIL', true); sample('FAIL', true);
let result = alerts.run_pending();
check(result.ok && sends == 1 && result.event.state == 'queued' && result.event.delivery_state == 'not_submitted', 'definite preflight failure remains queued independently of unhealthy state');
check(alerts.summary().alert.state == 'abnormal', 'failed notification cannot turn business health normal');
check(!alerts.pending(), 'retry is not due immediately');
alerts.run_pending(); check(sends == 1, 'backoff prevents busy-loop transport retry');
now += 30000; outcome = { state: 'failed', delivery_state: 'rejected', http_status: 503, error: 'HTTP_REJECTED' };
result = alerts.run_pending();
check(sends == 2 && result.event.state == 'queued' && result.event.next_ms == now + 60000, 'HTTP503 uses increasing bounded backoff');
now += 60000; outcome = { state: 'done', delivery_state: 'accepted', http_status: 200, error: null };
result = alerts.run_pending();
check(sends == 3 && result.event.state == 'done' && !result.event.receipt_verified && result.event.delivery_state == 'accepted', 'acceptance is not user receipt');
now += 30000; alerts.run_pending(); check(sends == 3, 'accepted event is not resent');
let before = read_json(persistent + '/state.json', 524288);
sample('FAIL', true);
check(sprintf('%J', before) == sprintf('%J', read_json(persistent + '/state.json', 524288)), 'steady failure does not rewrite persistent sample/streak metadata');
sample('PASS', true); sample('PASS', true); now += 30000;
outcome = { state: 'unknown', delivery_state: 'unknown', error: 'DELIVERY_UNCONFIRMED', exit_code: 28 };
result = alerts.run_pending();
check(result.event.state == 'unknown' && result.event.delivery_state == 'unknown', 'timeout after possible submission is indeterminate');
let sent = sends; now += 1000000; alerts.run_pending();
check(sends == sent, 'indeterminate submissions are never replayed');
sample('FAIL', false);
check(read_json(root + '/observer.json', 2048).failure == 'COMMAND_TIMEOUT', 'abnormal observer is explicitly published');
sample('PASS', true);
check(read_json(root + '/observer.json', 2048).state == 'normal' && read_json(root + '/observer.json', 2048).failure == null, 'normal observer overwrites prior failure');
// Simulate a crash after durable submitted rename but before tmp publication.
let stale = read_json(root + '/alerts.json', 524288), journal = read_json(persistent + '/state.json', 524288);
journal.events[0].state = 'submitted'; journal.events[0].delivery_state = 'submitted';
journal.events[0].submitted_boot = 'oldboot'; journal.events[0].submitted_ms = 10;
stale.events[0].state = 'queued'; stale.events[0].delivery_state = 'not_submitted';
atomic_json(persistent, 'state.json', journal); atomic_json(root, 'alerts.json', stale);
sample('PASS', true);
check(read_json(root + '/alerts.json', 524288).events[0].state == 'unknown', 'durable write-ahead wins over stale queued tmp state after crash');
check(lstat(persistent + '/state.json').mode == 0600 && lstat(persistent).mode == 0700, 'private durable incident storage');
let durable_state = read_json(persistent + '/state.json', 524288);
unlink(root + '/alerts.json'); sample('FAIL', true);
check(read_json(root + '/alerts.json', 524288).events[0].state == 'unknown', 'tmp loss cannot revive an indeterminate persisted event');
config.notification.owner = 'central'; sample('FAIL', true); sample('FAIL', true);
now += 30000; sent = sends; alerts.run_pending();
check(sends == sent, 'central owner never falls back to local sender');
config.notification.owner = 'local'; sample('PASS', true); sample('PASS', true); now += 30000;
maintenance = 'active'; sent = sends; alerts.run_pending();
check(sends == sent, 'live maintenance guard prevents network submission between samples');
config.monitor.enabled = false; maintenance = 'idle'; alerts.run_pending();
check(sends == sent, 'disabled monitor does not dispatch retained work');
let observer_before = read_json(root + '/observer.json', 2048), failures_before = read_json(root + '/alerts.json', 524288).failures;
config.revision++;
let obsolete = alerts.record({ snapshot: { complete: true }, run: { run_id: 'boot:obsolete', boot_id: 'boot',
    node_id: config.node.stable_node_id, config_revision: config.revision - 1,
    overall: 'healthy', checks: [], flags: {}, finished_at: 2000 } });
check(!obsolete.ok && obsolete.reason == 'CONFIG_CHANGED' &&
    sprintf('%J', observer_before) == sprintf('%J', read_json(root + '/observer.json', 2048)) &&
    read_json(root + '/alerts.json', 524288).failures == failures_before,
    'old configuration evidence cannot count toward recovery or be stamped as a new observer');
unlink(root + '/alerts.json'); unlink(persistent + '/state.json');
config.monitor.enabled = true; config.notification.owner = 'local';
outcome = { state: 'failed', delivery_state: 'rejected', http_status: 503, error: 'HTTP_REJECTED' };
sample('FAIL', true); sample('FAIL', true); sample('FAIL', true); sent = sends;
for (let i = 0; i < 8; i++) {
    let event = read_json(root + '/alerts.json', 524288).events[0];
    now = max(now, event.next_ms); result = alerts.run_pending();
}
check(sends - sent == 8 && result.event.state == 'failed' && result.event.error == 'RETRY_EXHAUSTED' && !alerts.pending(),
    'persistent HTTP rejection exhausts eight bounded attempts rather than sending indefinitely');
unlink(root + '/alerts.json'); unlink(persistent + '/state.json');
sample('FAIL', true); sample('FAIL', true); sample('FAIL', true);
alerts.run_pending(); now += 30000; alerts.run_pending();
let failure_due = read_json(root + '/alerts.json', 524288).events[0].next_ms;
sample('PASS', true); sample('PASS', true); now += 30000; sent = sends;
alerts.run_pending();
check(sends == sent, 'recovery cannot overtake its backed-off failure notification');
now = failure_due; outcome = { state: 'done', delivery_state: 'accepted', http_status: 200, error: null };
result = alerts.run_pending();
check(result.event.kind == 'failure', 'earlier incident failure is submitted first when its backoff expires');
now += 30000; result = alerts.run_pending();
check(result.event.kind == 'recovery' && result.event.delivery_state == 'accepted',
    'recovery follows the terminal failure without stale failure delivery afterwards');
for (let name in lsdir(persistent)) unlink(persistent + '/' + name); rmdir(persistent);
for (let name in lsdir(root)) unlink(root + '/' + name); rmdir(root);
print('alert-runtime: ', n, ' assertions passed\n');

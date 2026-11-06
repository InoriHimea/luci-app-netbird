// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, mkdir, open, lsdir, unlink, rmdir, chmod } from 'fs';
import { create_notifications } from '../../luci-app-netbird/root/usr/share/netbird/health/notification.uc';
let root = mkdtemp('/tmp/nbh-notify-test.XXXXXX'), sinks = root + '/sinks', now = 1000, n = 0;
mkdir(sinks, 0700);
let config = { revision: 3, notification: { owner: 'none', sink_ref: null } };
let notify = create_notifications(root, () => config, sinks, () => now);
function check(ok, label) { if (!ok) die(label + '\n'); n++; }
check(notify.enqueue().reason == 'NOTIFICATION_NOT_CONFIGURED', 'unconfigured notification is not a fake delivery');
config.notification = { owner: 'central', sink_ref: 'fixture' };
check(notify.enqueue().reason == 'NOTIFICATION_NOT_CONFIGURED', 'central owner prevents local test transmission');
config.notification = { owner: 'local', sink_ref: '../secret' };
check(notify.enqueue().reason == 'SINK_INVALID', 'sink reference cannot choose paths');
config.notification.sink_ref = 'fixture';
check(notify.enqueue().reason == 'SINK_NOT_CONFIGURED', 'missing protected sink explicit');
let file = open(sinks + '/fixture.json', 'wx', 0600);
file.write(sprintf('%J', { schema: 1, kind: 'gotify', host: 'sink.test.invalid', port: 443, address: '10.99.0.2', token: 'isolatedFixtureToken' })); file.close();
chmod(sinks + '/fixture.json', 0644);
check(notify.enqueue().reason == 'SINK_INVALID', 'world-readable credential file rejected');
chmod(sinks + '/fixture.json', 0600);
let first = notify.enqueue();
let writer = open(root + '/notification.lock', 'a', 0600);
check(writer.lock('xn'), 'fixture holds notification metadata writer');
let contended = notify.enqueue();
check(contended.ok && contended.coalesced && contended.job.id == first.job.id,
    'coalescing a published test does not contend with transport completion');
writer.close();
let again = notify.enqueue();
check(first.ok && first.job.state == 'queued' && match(first.job.id, /^[0-9a-f]{32}$/), 'test request only issues an opaque asynchronous job');
check(again.ok && again.coalesced && again.job.id == first.job.id, 'concurrent test requests coalesce without sending twice');
check(notify.get('../file').reason == 'JOB_INVALID', 'notification job IDs are not paths');
check(notify.get('00000000000000000000000000000000').reason == 'JOB_UNKNOWN', 'unknown notification job explicit');
config.revision = 4;
let changed = notify.enqueue();
check(changed.ok && changed.job.id != first.job.id && changed.job.config_revision == 4 &&
    notify.get(first.job.id).job.error == 'CONFIG_CHANGED', 'new configuration cannot inherit an obsolete queued test');
check(notify.pending(), 'queued replacement remains dispatchable across old-worker teardown');
check(notify.launch_failed().ok && !notify.pending() && notify.get(changed.job.id).job.state == 'failed' &&
    notify.get(changed.job.id).job.error == 'WORKER_START_FAILED' &&
    notify.get(changed.job.id).job.delivery_state == 'not_submitted', 'worker launch failure is explicit terminal non-delivery');
check(notify.enqueue().job.id == changed.job.id && !notify.pending(), 'cooldown never replays a terminal launch failure');
now += 600001;
check(notify.get(first.job.id).reason == 'JOB_EXPIRED', 'expired notification job explicit');
unlink(sinks + '/fixture.json'); rmdir(sinks);
for (let name in lsdir(root)) unlink(root + '/' + name);
rmdir(root);
print('notification: ', n, ' assertions passed\n');

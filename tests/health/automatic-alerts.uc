// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, readfile, unlink } from 'fs';
import { create_alerts } from '../../luci-app-netbird/root/usr/share/netbird/health/alert-runtime.uc';
let root = mkdtemp('/tmp/nbh-auto-alerts.XXXXXX'), persistent = mkdtemp('/tmp/nbh-auto-alert-durable.XXXXXX');
let config = json(readfile('tests/health/fixtures/config-valid.json')), now = 100000, n = 0;
config.notification.owner = 'central';
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
let alerts = create_alerts(root, persistent, () => config, () => now);
let episode = { id: sprintf('%032x', 1), phase: 'finished', outcome: 'FAILED', reason: 'POST_CHECK_FAILED' };
let first = alerts.record_automatic_failure(episode);
check(first.ok && first.state.events[0].kind == 'automatic_failure' && first.state.events[0].overall == 'unknown',
    'failed automatic action creates explicit alert without claiming diagnostic recovery');
check(first.state.events[0].owner == 'central' && !alerts.pending(), 'central delivery owner is retained without local takeover');
let saved = readfile(persistent + '/state.json');
now += 1000;
check(alerts.record_automatic_failure(episode).duplicate, 'continued incident has no second failure event');
check(readfile(persistent + '/state.json') == saved, 'continued failure polls cause no durable rewrite');
unlink(root + '/alerts.json');
let restarted = create_alerts(root, persistent, () => config, () => now);
let recovered = restarted.record_automatic_failure(episode);
check(recovered.ok && recovered.duplicate && recovered.state.events[0].id == first.state.events[0].id,
    'monitor restart restores the original event instead of producing another alert');
episode.id = sprintf('%032x', 2); episode.outcome = 'PARTIAL';
check(restarted.record_automatic_failure(episode).state.events[1].kind == 'automatic_failure',
    'independently charged partial incident has its own explicit failure alert');
episode.id = sprintf('%032x', 3); episode.outcome = 'UNKNOWN';
check(restarted.record_automatic_failure(episode).ok, 'unknown recovery is alerted rather than silently considered restored');
episode.id = sprintf('%032x', 4); episode.outcome = 'RESTORED';
check(!restarted.record_automatic_failure(episode).ok, 'restored action does not emit an automatic failure event');
printf('PASS: %d automatic failure alert assertions\n', n);

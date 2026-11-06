// SPDX-License-Identifier: Apache-2.0
import { observe, advance, durable, restore } from '../../luci-app-netbird/root/usr/share/netbird/health/alerts.uc';
let n = 0;
function check(ok, label) { if (!ok) die(label + '\n'); n++; }
let config = { revision: 1, node: { stable_node_id: 'fixture', expected_connection_intent: 'connected' },
    monitor: { enabled: true, interval: 30, cycle_timeout: 2 },
    notification: { owner: 'central', sink_ref: null, failure_threshold: 3, recovery_threshold: 2, reminder: false } };
let run = { run_id: 'boot:1', boot_id: 'boot', finished_at: 1, overall: 'unhealthy', flags: {}, checks: [
    { id: 'port', category: 'endpoint', code: 'PORT_CLOSED', status: 'FAIL', fresh: true, executed: true, severity: 'critical' } ] };
let snapshot = { complete: true, agent: { ok: true, data: { management: true, signal: true, daemon_status: 'Connected' } } };
let now = 0, serial = 0, boot = 'boot', wall = 1000, state = null;
function step(observation) {
    now += 1000; serial++; run.run_id = boot + ':' + serial;
    let result = advance(state, observation, config, { now_ms: now, boot_id: boot, run_id: run.run_id, wall,
        id: sprintf('%032x', serial) });
    if (!result.ok) die(result.reason); state = result.state; return result;
}
let bad = observe(run, config, snapshot);
check(bad.categories[0] == 'BUSINESS_ENDPOINT' && !bad.upstream_down, 'A08 endpoint failure does not invent NetBird outage');
step(bad);
check(state.failures == 1 && state.episode.first_run_id == 'boot:1' && !length(state.events), 'first anomaly retained immediately without premature notification');
step(bad); check(!length(state.events), 'second failure below threshold');
step(bad); check(length(state.events) == 1 && state.events[0].kind == 'failure' && state.events[0].owner == 'central', 'third consecutive failure queues one central event');
let first = state.events[0].id;
for (let i = 0; i < 100; i++) step(bad);
check(length(state.events) == 1 && state.events[0].id == first, 'persistent incident is deduplicated and reminders default off');
let duplicate = advance(state, bad, config, { run_id: state.last_run_id });
check(duplicate.duplicate && duplicate.state.failures == state.failures, 'same sample is not another threshold observation');
run.checks[0].status = 'PASS'; run.overall = 'healthy';
let good = observe(run, config, snapshot);
step(good); check(length(state.events) == 1 && state.episode != null, 'first healthy sample is not recovery');
step(good); check(length(state.events) == 2 && state.events[1].kind == 'recovery' && !state.episode, 'second healthy sample queues one recovery');
step(good); check(length(state.events) == 2, 'continued healthy samples do not repeat recovery');
step(bad); step(bad); step(bad);
check(length(state.events) == 3 && state.events[2].episode_id != state.events[0].episode_id, 'new failure has a new incident after recovery');
let saved = durable(state); state = restore(saved, 'fixture'); boot = 'newboot'; now = 0;
step(bad); step(bad); step(bad);
check(length(state.events) == 3, 'reboot restores announced incident without replaying failure');
wall = -50000; config.revision++;
step(bad); check(length(state.events) == 3, 'wall clock reversal and config revision do not duplicate incident');
state.events[2].state = 'submitted'; state.events[2].delivery_state = 'submitted'; step(bad);
check(state.events[2].state == 'unknown' && state.events[2].delivery_state == 'unknown', 'orphan submitted transport is never automatically replayed');
config.notification.owner = 'local'; step(bad);
check(state.events[0].state == 'cancelled' && state.events[0].error == 'OWNER_OR_SINK_CHANGED', 'ownership changes cancel obsolete queued work rather than double sending');
snapshot.complete = false; snapshot.reason = 'COMMAND_TIMEOUT';
let broken = observe(run, config, snapshot);
check(broken.observer.state == 'abnormal' && broken.observer.failure == 'COMMAND_TIMEOUT' && index(broken.categories, 'MONITOR_SELF') >= 0, 'observer explicitly reports failed collection');
snapshot.complete = true; delete snapshot.reason;
let recovered = observe(run, config, snapshot);
check(recovered.observer.state == 'normal' && recovered.observer.failure == null && index(recovered.categories, 'MONITOR_SELF') < 0, 'A17 current normal observer clears old failure');
run.checks[0] = { id: 'backup', category: 'peer', code: 'BACKUP_TAKEOVER', status: 'FAIL', severity: 'warning', fresh: true, executed: true }; run.overall = 'degraded';
let backup = observe(run, config, snapshot);
check(backup.categories[0] == 'REDUNDANCY' && backup.overall == 'degraded', 'A06 backup takeover is redundancy degradation, not full-site outage');
run.flags.maintenance = true;
let maintained = observe(run, config, snapshot); step(maintained);
run.flags.maintenance = false; config.node.expected_connection_intent = 'disconnected';
check(observe(run, config, snapshot).intent == 'intentional_disconnect', 'intentional disconnect is not a control-plane alarm');
config.node.expected_connection_intent = 'connected'; snapshot.agent.data.management = false;
let upstream = observe(run, config, snapshot);
check(upstream.upstream_down && index(upstream.categories, 'CONTROL_PLANE') >= 0 && upstream.aggregation == 'upstream_with_downstream_details' && length(upstream.details) == 2, 'explicit upstream failure aggregates downstream evidence without discarding detail');
state = null; config.notification.owner = 'none'; step(bad); step(bad); step(bad);
check(state.events[0].state == 'suppressed' && state.events[0].error == 'OWNER_NONE', 'none owner never queues local or central sends');
state = null; config.notification.owner = 'central'; step(bad); now += 100000; step(bad); step(bad);
check(!length(state.events) && state.failures == 2, 'sampling gap resets consecutive failure threshold');
let uncertain = { ...good, state: 'unknown' }; step(uncertain); step(bad); step(bad);
check(!length(state.events) && state.failures == 2, 'UNKNOWN is neither success nor another consecutive failure');
state = null; config.notification.owner = 'local'; step(bad); step(bad); step(bad);
let pending_id = state.events[0].id;
step(maintained); step(bad);
check(state.events[0].id == pending_id && state.events[0].state == 'queued' && length(state.events) == 1,
    'maintenance pauses but does not permanently discard the only queued incident');
state = null; config.notification.owner = 'central';
for (let i = 0; i < 18; i++) { step(bad); step(bad); step(bad); step(good); step(good); }
check(length(state.events) == 32 && state.dropped_events == 4 && state.events[0].kind == 'failure',
    'queue overflow retains newest incidents with explicit dropped queued-event accounting');
state = null; step(bad); step(bad); step(bad);
state.events[0].state = 'submitted'; state.events[0].delivery_state = 'submitted';
state.events[0].submitted_boot = boot; state.events[0].submitted_ms = now;
step(bad);
check(state.events[0].state == 'submitted', 'a live bounded submission is not prematurely marked orphaned');
now += 6000; step(bad);
check(state.events[0].state == 'unknown' && length(state.events) == 1, 'expired submission is unknown without replacement delivery');
state = null; config.notification.reminder = true; step(bad); step(bad); step(bad);
for (let i = 0; i < 5; i++) { now += 3600000; step(bad); }
check(state.episode.reminders == 3 && length(state.events) == 4,
    'optional reminders stop after three per incident even across repeated hourly samples');
state = null; config.notification.reminder = false;
run.checks[0] = { id: 'missing-rule', category: 'rules', code: 'RULE_MISSING', status: 'FAIL', severity: 'critical', fresh: true, executed: true };
run.overall = 'unhealthy'; run.convergence = { checking: true, phase: 'converging' };
let waiting = observe(run, config, snapshot);
check(waiting.state == 'suppressed' && waiting.intent == 'network_convergence' && length(waiting.details) > 0,
    'bounded convergence pauses votes without discarding required-rule failure evidence');
step(waiting); step(waiting); step(waiting);
check(state.failures == 0 && !length(state.events), 'bounded wait never consumes consecutive failure votes or queues a notification');
run.convergence.checking = false; run.convergence.phase = 'failed';
let expired = observe(run, config, snapshot); step(expired); step(expired); step(expired);
check(state.failures == 3 && length(state.events) == 1 && state.events[0].kind == 'failure',
    'expired convergence resumes actual failure voting rather than permanently suppressing the incident');
state = null; run.convergence = { phase: 'unknown', checking: false, reason: 'CONVERGENCE_EVENT_DURING_CYCLE' };
let mixed = observe(run, config, snapshot); step(mixed); step(mixed); step(mixed);
check(mixed.intent == 'network_generation_changed' && state.failures == 0 && !length(state.events) && length(mixed.details) > 0,
    'mixed-generation failures retain diagnostics but cannot consume incident votes');
print('alerts: ', n, ' assertions passed\n');

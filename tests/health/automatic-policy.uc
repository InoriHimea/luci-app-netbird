// SPDX-License-Identifier: Apache-2.0
import { readfile } from 'fs';
import { assess_automatic as assess_native, create_automatic_streak } from '../../luci-app-netbird/root/usr/share/netbird/health/automatic-policy.uc';
let n = 0;
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
function copy(value) { return json(sprintf('%J', value)); }
const boot = '11111111-1111-4111-8111-111111111111', now = 200000;
let config = json(readfile('tests/health/fixtures/config-valid.json'));
config.monitor.enabled = true; config.paths[0].enabled = true;
let control = { schema: 1, boot_id: boot, config_revision: config.revision, event_sequence: 0 };
function assess_automatic(result, config, boot, now) { return assess_native(result, config, boot, now, control); }
let result = { snapshot: { boot_id: boot, complete: true, generation: 'native-generation',
    agent: { ok: true, data: { daemon_status: 'Connected', management: true, signal: true } } },
    run: { boot_id: boot, run_id: boot + ':190000', node_id: config.node.stable_node_id,
        config_revision: config.revision, generation: 'native-generation', monotonic_duration_ms: 1000,
        flags: {}, convergence: { phase: 'ready', checking: false, event_sequence: 0 }, checks: [] } };
for (let category in ['rules', 'routes', 'forward', 'peer', 'router', 'lan'])
    push(result.run.checks, { id: config.paths[0].id + ':' + category, category,
        status: 'PASS', code: 'VALID', fresh: true, executed: true, required: true });
push(result.run.checks, { id: 'node:collection', category: 'collection', status: 'PASS',
    fresh: true, executed: true, required: true });
check(assess_automatic(result, config, boot, now).restored, 'native same-generation complete structure and both business vantages can close an episode');
let fault = copy(result); fault.run.checks[0].status = 'FAIL'; fault.run.checks[0].code = 'RULE_MISSING';
fault.run.convergence.phase = 'failed';
check(assess_automatic(fault, config, boot, now).state == 'fault', 'expired convergence and actual missing native rule create a structural vote');
control.event_sequence++;
check(assess_automatic(fault, config, boot, now).state == 'blocked', 'new native route event invalidates a previously complete fault cycle');
control.event_sequence--;
check(assess_native(fault, config, boot, now, null).state == 'blocked', 'missing native convergence control cannot authorize recovery');
let business = copy(result); business.run.checks[4].status = 'FAIL';
check(assess_automatic(business, config, boot, now).state == 'normal' && !assess_automatic(business, config, boot, now).restored,
    'business timeout alone cannot trigger recovery or falsely clear the incident');
let lan = copy(result); lan.run.checks[5].status = 'UNKNOWN';
check(assess_automatic(lan, config, boot, now).layout_verified && !assess_automatic(lan, config, boot, now).restored,
    'verified structure does not claim missing LAN restored');
for (let phase in ['startup_grace', 'converging', 'unknown']) {
    let value = copy(fault); value.run.convergence.phase = phase;
    check(assess_automatic(value, config, boot, now).state == 'blocked', 'no automatic recovery during ' + phase);
}
for (let field in ['management', 'signal', 'daemon_status']) {
    let value = copy(fault); value.snapshot.agent.data[field] = field == 'daemon_status' ? 'NeedsLogin' : false;
    check(assess_automatic(value, config, boot, now).state == 'blocked', 'unverified control-plane ' + field + ' cannot authorize effects');
}
let value = copy(fault); value.run.flags.maintenance = true;
check(assess_automatic(value, config, boot, now).state == 'blocked', 'maintenance never creates an automatic vote');
value = copy(fault); value.snapshot.generation = 'other';
check(assess_automatic(value, config, boot, now).state == 'blocked', 'mixed snapshot generation cannot authorize recovery');
value = copy(fault); value.run.config_revision++;
check(assess_automatic(value, config, boot, now).state == 'blocked', 'previous approved configuration cannot authorize recovery');
value = copy(fault); value.run.checks[2].status = 'UNKNOWN';
check(assess_automatic(value, config, boot, now).state == 'blocked', 'missing actual forwarding proof cannot authorize recovery');
check(assess_automatic(fault, config, boot, 300000).state == 'blocked', 'old monotonic evidence cannot vote despite wall-clock freshness');
check(assess_automatic(fault, config, boot, 180000).state == 'blocked', 'future monotonic samples cannot vote after reversal');
let disabled = copy(config); disabled.monitor.enabled = false;
check(assess_automatic(fault, disabled, boot, now).state == 'blocked', 'disabled monitoring cannot vote');
disabled = copy(config); disabled.node.expected_connection_intent = 'disconnected';
check(assess_automatic(fault, disabled, boot, now).state == 'blocked', 'explicit disconnect cannot vote');
disabled = copy(config); disabled.paths[0].approval.approved = false;
check(assess_automatic(fault, disabled, boot, now).state == 'blocked', 'unapproved layout cannot vote');
let streak = create_automatic_streak(60, 20), vote = { state: 'fault' };
check(!streak.observe(vote, boot + ':100000', 100000).trigger, 'one failure cannot execute');
check(!streak.observe(vote, boot + ':100000', 160000).trigger, 're-reading the same failure cannot create a second vote');
check(!streak.observe(vote, boot + ':160000', 160000).trigger, 'two failures cannot execute');
check(streak.observe(vote, boot + ':220000', 220000).trigger, 'three distinct sustained cycles qualify for the separate durable budget');
streak.observe({ state: 'blocked' }, boot + ':220000', 221000);
check(!streak.observe(vote, boot + ':240000', 240000).trigger, 'unknown invalidates prior streak even with a duplicate run ID');
streak.observe(vote, boot + ':260000', 260000);
check(!streak.observe(vote, boot + ':420001', 420001).trigger, 'a collection gap invalidates sustained evidence');
streak.observe(vote, boot + ':430000', 430000); streak.observe(vote, null, 440000);
check(!streak.observe(vote, boot + ':450000', 450000).trigger, 'missing cycle identity clears the streak');
streak.observe(vote, boot + ':460000', 460000);
check(!streak.observe(vote, boot + ':400000', 400000).trigger && !streak.observe(vote, boot + ':470000', 470000).trigger,
    'monotonic reversal clears votes without minting an attempt');
streak = create_automatic_streak(60, 20);
streak.observe({ state: 'normal', restored: true }, boot + ':100000', 100000);
check(!streak.observe({ state: 'normal', restored: true }, boot + ':130000', 130000).clear,
    'a transient healthy sample does not reset the event budget');
check(streak.observe({ state: 'normal', restored: true }, boot + ':160000', 160000).clear,
    'sustained complete recovery can close the durable incident');
let delayed = create_automatic_streak(60, 20);
delayed.observe(vote, boot + ':100000', 100000);
delayed.observe(vote, boot + ':110000', 130000);
check(!delayed.observe(vote, boot + ':120000', 160000).trigger,
    'polling delay cannot turn twenty seconds of source samples into sixty seconds of structural fault');
let replay = create_automatic_streak(60, 20);
replay.observe(vote, boot + ':100000', 100000);
replay.observe(vote, boot + ':130000', 130000);
check(!replay.observe(vote, boot + ':100000', 160000).trigger,
    'nonadjacent replay A B A cannot create a third distinct fault sample');
let delayed_clear = create_automatic_streak(60, 20), restored = { state: 'normal', restored: true };
delayed_clear.observe(restored, boot + ':100000', 100000);
check(!delayed_clear.observe(restored, boot + ':110000', 160000).clear,
    'polling delay cannot prematurely close an incident with only ten seconds of healthy source evidence');
printf('PASS: %d automatic policy assertions\n', n);

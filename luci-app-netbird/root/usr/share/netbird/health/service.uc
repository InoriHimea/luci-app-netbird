// SPDX-License-Identifier: Apache-2.0
import * as uloop from 'uloop';
import { open, unlink, access } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { create_schedule, next_check, finish_check, request_check, route_event } from './scheduler.uc';
import { monotonic_ms, cleanup_commands } from './runner.uc';
import { read_config } from './settings.uc';
import { create_jobs } from './jobs.uc';
import { production_alerts } from './alert-runtime.uc';
import { convergence_policy, create_convergence, convergence_event, assess_convergence } from './convergence.uc';
const ROOT = '/tmp/netbird-health';
if (!private_dir(ROOT)) exit(2);
let lock = open(ROOT + '/service.lock', 'a', 0600);
if (!lock || !lock.lock('xn')) exit(3);
cleanup_commands();
function text(path) {
    let f = open(path, 'r'); if (!f) return null;
    let s = trim(f.read(128) || ''); f.close(); return s;
}
let config = read_config();
if (config?.monitor?.enabled !== true) exit(0);
let boot = text('/proc/sys/kernel/random/boot_id');
let stop_reason = null;
let initial_gate = open(ROOT + '/convergence.lock', 'a', 0600);
if (!initial_gate || !initial_gate.lock('x')) exit(4);
let now_start = monotonic_ms() / 1000, policy = convergence_policy(config.monitor);
let state = create_schedule(boot, now_start, config.monitor.interval, policy.event_debounce);
let convergence = create_convergence(boot, now_start, config.monitor,
    read_json(ROOT + '/convergence-control.json', 4096));
let convergence_result = null;
function store_control() {
    convergence.config_revision = config.revision;
    return atomic_json(ROOT, 'convergence-control.json', convergence);
}
if (!store_control()) exit(4);
initial_gate.close();
let child = null, listener = null, event_status = 'disabled', stopping = false;
let jobs = create_jobs(ROOT), active_job = null;
let alerts = production_alerts(), alert_child = null, next_alert_launch = 0;
let event_started_at = time(), event_overrun = false, overrun_observable = false;
let next_cleanup = monotonic_ms() / 1000 + 5;
uloop.init();
function publish(phase, reason) {
    atomic_json(ROOT, 'service.json', { phase, reason, boot_id: boot, sampled_at: time(),
        event_watch: event_status, event_gap: event_status != 'listening' || event_overrun || !overrun_observable,
        event_started_at, event_overrun, overrun_observable,
        convergence: convergence_result, event_sequence: convergence.event_sequence,
        interval: state.interval, active: state.active, config_revision: config.revision,
        job_id: active_job, attribution: 'cause_undetermined' });
}
function finish_cycle(budget, failed) {
    let now = monotonic_ms() / 1000;
    if (failed) convergence_result = assess_convergence(convergence, [], now, false);
    finish_check(state, now);
    if (!stopping && convergence.episode_open && now < convergence.deadline_at)
        state.convergence_due = min(now + max(5, budget), convergence.deadline_at);
}
function stop() {
    stopping = true;
    // Do not kill the independent deadline host or clear its cycle lock. Its
    // group is drained before another worker can acquire the kernel lock.
    publish('stopping', stop_reason || (child ? 'BOUNDED_WORKER_DRAINING' : null));
    if (!child && !alert_child) { publish('stopped', stop_reason); uloop.end(); }
}
function network_event() {
    let gate = open(ROOT + '/convergence.lock', 'a', 0600);
    if (!gate || !gate.lock('x')) { stop_reason = 'CONVERGENCE_STORAGE_FAILED'; stop(); return; }
    let now = monotonic_ms() / 1000;
    route_event(state, now);
    convergence_event(convergence, now, config.monitor);
    convergence_result = assess_convergence(convergence, [], now, false);
    let saved = store_control();
    publish(child ? 'running' : 'idle', 'NETWORK_EVENT');
    gate.close();
    if (!saved) { stop_reason = 'CONVERGENCE_STORAGE_FAILED'; stop(); }
}
if (config.monitor.event_watch === true) {
    try {
        let rtnl = require('rtnl');
        listener = rtnl.listener(network_event,
            [rtnl.const.RTM_NEWROUTE, rtnl.const.RTM_DELROUTE, rtnl.const.RTM_NEWRULE,
             rtnl.const.RTM_DELRULE, rtnl.const.RTM_NEWLINK, rtnl.const.RTM_DELLINK],
            [rtnl.const.RTNLGRP_IPV4_ROUTE, rtnl.const.RTNLGRP_IPV4_RULE, rtnl.const.RTNLGRP_LINK]);
        event_status = listener ? 'listening' : 'unavailable';
        if (listener && type(listener.set_overrun_handler) == 'function') {
            overrun_observable = listener.set_overrun_handler(() => {
                event_overrun = true;
                network_event();
            }) === true;
        }
    }
    catch (err) { event_status = 'unavailable'; }
}
let tick = uloop.interval(250, () => {
    if (stopping) return;
    // APK downgrade executes the incoming older package's scripts, which may
    // know nothing about this newly added service. Retire our own registration
    // when our installed entrypoints disappear; never touch another service.
    if (!access('/etc/init.d/luci-netbird-health', 'x') ||
        !access('/usr/share/netbird/health/service.uc', 'r')) {
        stop_reason = 'PACKAGE_REMOVED';
        system(['/bin/ubus', 'call', 'service', 'delete', '{"name":"luci-netbird-health"}'], 100);
        stop();
        return;
    }
    let now = monotonic_ms() / 1000;
    if (!state.active && now >= next_cleanup) { cleanup_commands(); next_cleanup = now + 5; }
    // Delivery runs independently of collection and its hard deadline.
    // Central-owned incidents never launch a local transport.
    if (alerts && !alert_child && now >= next_alert_launch && alerts.pending()) {
        next_alert_launch = now + 5;
        try {
            alert_child = uloop.process('/usr/bin/ucode', ['/usr/share/netbird/health/alert-worker.uc'], null,
                () => { alert_child = null; if (stopping && !child) uloop.end(); });
        }
        catch (e) { alert_child = null; }
    }
    let request = read_json(ROOT + '/request.json', 1024);
    if (request) { unlink(ROOT + '/request.json'); request_check(state, monotonic_ms() / 1000); }
    let reason = next_check(state, monotonic_ms() / 1000);
    if (!reason) return;
    let budget = config.monitor.cycle_timeout;
    if (type(budget) != 'int' || budget < 1 || budget > 20) budget = 20;
    let started = jobs.begin(config.revision);
    if (!started.ok) {
        finish_cycle(budget, true); publish('idle', started.reason); return;
    }
    active_job = started.job.id;
    publish('running', reason);
    try {
    child = uloop.process('/usr/bin/ucode', ['/usr/share/netbird/health/cycle-host.uc', '' + budget * 1000], null,
        (code) => {
            child = null;
            let latest = code == 0 ? read_json(ROOT + '/latest.json', 524288) : null;
            jobs.finish(active_job, latest?.run, code == 0 ? null : 'CYCLE_FAILED');
            let observed = latest?.run?.convergence;
            if (observed && latest.run.config_revision == config.revision &&
                latest.run.boot_id == boot && observed.event_sequence == convergence.event_sequence) {
                convergence_result = observed;
                if (observed.phase == 'ready') convergence.episode_open = false;
            }
            else convergence_result = assess_convergence(convergence, [], monotonic_ms() / 1000, false);
            convergence.last_now = monotonic_ms() / 1000;
            store_control();
            if (code != 0 && alerts) alerts.record({ snapshot: { complete: false, reason: 'CYCLE_FAILED' },
                run: { run_id: boot + ':monitor:' + monotonic_ms(), boot_id: boot,
                    node_id: config.node.stable_node_id, config_revision: config.revision,
                    finished_at: time(), overall: 'unknown', checks: [], flags: {},
                    convergence: monotonic_ms() / 1000 < convergence.deadline_at ? convergence_result : null } });
            active_job = null;
            finish_cycle(budget);
            publish(stopping ? 'stopped' : 'idle', stop_reason || (code == 0 ? null : 'CYCLE_FAILED'));
            if (stopping && !alert_child) uloop.end();
        });
    }
    catch (e) { child = null; }
    if (!child) {
        jobs.finish(active_job, null, 'WORKER_START_FAILED'); active_job = null;
        finish_cycle(budget, true); publish('idle', 'WORKER_START_FAILED');
    }
});
let term = uloop.signal(15, stop), interrupt = uloop.signal(2, stop);
publish('idle', null);
uloop.run();

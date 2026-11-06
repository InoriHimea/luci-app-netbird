// SPDX-License-Identifier: Apache-2.0
import * as uloop from 'uloop';
import { open, unlink, access } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { create_schedule, next_check, finish_check, request_check, route_event } from './scheduler.uc';
import { monotonic_ms, cleanup_commands } from './runner.uc';
import { read_config } from './settings.uc';
import { create_jobs } from './jobs.uc';
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
let state = create_schedule(boot, monotonic_ms() / 1000, config.monitor.interval);
let child = null, listener = null, event_status = 'disabled', stopping = false;
let jobs = create_jobs(ROOT), active_job = null;
let event_started_at = time(), event_overrun = false, overrun_observable = false;
let next_cleanup = monotonic_ms() / 1000 + 5;
uloop.init();
if (config.monitor.event_watch === true) {
    try {
        let rtnl = require('rtnl');
        listener = rtnl.listener(() => route_event(state, monotonic_ms() / 1000),
            [rtnl.const.RTM_NEWROUTE, rtnl.const.RTM_DELROUTE, rtnl.const.RTM_NEWRULE,
             rtnl.const.RTM_DELRULE, rtnl.const.RTM_NEWLINK, rtnl.const.RTM_DELLINK],
            [rtnl.const.RTNLGRP_IPV4_ROUTE, rtnl.const.RTNLGRP_IPV4_RULE, rtnl.const.RTNLGRP_LINK]);
        event_status = listener ? 'listening' : 'unavailable';
        if (listener && type(listener.set_overrun_handler) == 'function') {
            overrun_observable = listener.set_overrun_handler(() => {
                event_overrun = true;
                route_event(state, monotonic_ms() / 1000);
            }) === true;
        }
    }
    catch (err) { event_status = 'unavailable'; }
}
function publish(phase, reason) {
    atomic_json(ROOT, 'service.json', { phase, reason, boot_id: boot, sampled_at: time(),
        event_watch: event_status, event_gap: event_status != 'listening' || event_overrun || !overrun_observable,
        event_started_at, event_overrun, overrun_observable,
        interval: state.interval, active: state.active, config_revision: config.revision,
        job_id: active_job, attribution: 'cause_undetermined' });
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
    let request = read_json(ROOT + '/request.json', 1024);
    if (request) { unlink(ROOT + '/request.json'); request_check(state, monotonic_ms() / 1000); }
    let reason = next_check(state, monotonic_ms() / 1000);
    if (!reason) return;
    let budget = config.monitor.cycle_timeout;
    if (type(budget) != 'int' || budget < 1 || budget > 20) budget = 20;
    let started = jobs.begin(config.revision);
    if (!started.ok) {
        finish_check(state, monotonic_ms() / 1000); publish('idle', started.reason); return;
    }
    active_job = started.job.id;
    publish('running', reason);
    child = uloop.process('/usr/bin/ucode', ['/usr/share/netbird/health/cycle-host.uc', '' + budget * 1000], null,
        (code) => {
            child = null;
            let latest = code == 0 ? read_json(ROOT + '/latest.json', 524288) : null;
            jobs.finish(active_job, latest?.run, code == 0 ? null : 'CYCLE_FAILED');
            active_job = null;
            finish_check(state, monotonic_ms() / 1000);
            publish(stopping ? 'stopped' : 'idle', stop_reason || (code == 0 ? null : 'CYCLE_FAILED'));
            if (stopping) uloop.end();
        });
    if (!child) {
        jobs.finish(active_job, null, 'WORKER_START_FAILED'); active_job = null;
        finish_check(state, monotonic_ms() / 1000); publish('idle', 'WORKER_START_FAILED');
    }
});
function stop() {
    stopping = true;
    // Do not kill the independent deadline host or clear its cycle lock. Its
    // group is drained before another worker can acquire the kernel lock.
    publish('stopping', stop_reason || (child ? 'BOUNDED_WORKER_DRAINING' : null));
    if (!child) { publish('stopped', stop_reason); uloop.end(); }
}
let term = uloop.signal(15, stop), interrupt = uloop.signal(2, stop);
publish('idle', null);
uloop.run();

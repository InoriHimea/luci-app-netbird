// SPDX-License-Identifier: Apache-2.0
import { open, lsdir } from 'fs';
import { read_config, save_config } from './settings.uc';
import { read_json, atomic_json } from './storage.uc';
import { cached_view, refresh_page } from './cache.uc';
import { create_pages } from './pages.uc';
import { create_jobs } from './jobs.uc';
import { get_notification_job } from './notification.uc';
const ROOT = '/tmp/netbird-health';
let pages = create_pages(ROOT + '/pages'), jobs = create_jobs(ROOT);
function boot_id() {
    let file = open('/proc/sys/kernel/random/boot_id', 'r');
    if (!file) return null;
    let value = trim(file.read(128) || ''); file.close(); return value;
}
function cached() {
    return cached_view(read_json(ROOT + '/latest.json', 524288), read_config(), boot_id(), time(),
        read_json(ROOT + '/service.json', 4096));
}
function get_summary() {
    let view = cached();
    if (!view.ok) return view;
    let checks = view.run.checks;
    delete view.run.checks;
    view.check_count = length(checks);
    view.schema_version = 1;
    return view;
}
function get_checks(args) {
    if (args.cursor) return refresh_page(pages.next('checks', args.cursor), read_config(), boot_id(), time());
    let view = cached();
    if (!view.ok) return view;
    return pages.first('checks', view.run.checks, { run_id: view.run.run_id,
        config_revision: view.run.config_revision, current_config_revision: view.current_config_revision,
        sampled_at: view.sampled_at, boot_id: view.boot_id, baseline_revision: view.baseline_revision,
        max_age: view.max_age, fresh: view.fresh, reason: view.reason, scope: view.scope }, args.limit ?? 50);
}
function get_events(args) {
    if (args.cursor) return pages.next('events', args.cursor);
    let names = filter(lsdir(ROOT) || [], name => match(name, /^history-[0-9]{10}\.json$/));
    sort(names); reverse(names);
    let events = [], bytes = 0;
    // Retention is bounded independently by the single history writer. Read at
    // most its byte/count cap and report snapshot differences, never raw RTNL causes.
    for (let name in names) {
        if (length(events) >= 1000 || bytes >= 4194304) break;
        let item = read_json(ROOT + '/' + name, 524288);
        if (!item?.boundary || !item?.run) continue;
        bytes += length(sprintf('%J', item));
        push(events, { type: 'snapshot_difference', run_id: item.run.run_id,
            config_revision: item.run.config_revision, sampled_at: item.sampled_at,
            boundary: item.boundary, actor: 'unknown', attribution: 'cause_undetermined' });
    }
    return pages.first('events', events, { type: 'snapshot_difference', attribution: 'cause_undetermined',
        capture: 'bounded_retained_history', event_gaps_possible: true }, args.limit ?? 50);
}
function get_config() {
    let config = read_config();
    return config ? { ok: true, config, revision: config.revision,
        approval_identity: 'administrator_supplied_label' } : { ok: false, reason: 'CONFIG_UNAVAILABLE' };
}
function start_check(args) {
    let config = read_config();
    if (!config) return { ok: false, reason: 'CONFIG_UNAVAILABLE' };
    if (!config.monitor.enabled) return { ok: false, reason: 'MONITOR_DISABLED' };
    let approved = false;
    for (let path in config.paths) if (path.id == args.path_id && path.enabled) approved = true;
    if (!approved) return { ok: false, reason: 'PATH_NOT_CONFIGURED' };
    let service = read_json(ROOT + '/service.json', 4096);
    if (index(['idle', 'running'], service?.phase) < 0 || service.config_revision != config.revision ||
        type(service.sampled_at) != 'int' || time() < service.sampled_at ||
        time() - service.sampled_at > config.monitor.interval * 2 + config.monitor.cycle_timeout)
        return { ok: false, reason: 'SERVICE_UNAVAILABLE' };
    let issued = jobs.enqueue(config.revision);
    if (!issued.ok) return issued;
    if (issued.job.state == 'queued' && !atomic_json(ROOT, 'request.json', { job_id: issued.job.id }, 1024))
        return { ok: false, reason: 'REQUEST_UNAVAILABLE' };
    return { ok: true, job: issued.job, coalesced: issued.coalesced, requested_path_id: args.path_id,
        scope: 'full_approved_baseline' };
}
function get_job(args) {
    let baseline = jobs.get(args.id);
    if (baseline.ok || baseline.reason != 'JOB_UNKNOWN') return baseline;
    let notification = get_notification_job(args.id);
    return notification.reason == 'JOB_UNKNOWN' ? baseline : notification;
}
function set_config(args) {
    let result = save_config(args.config, args.expected_revision);
    if (!result.ok) return result;
    // Publish only the independent package's standard config-change event.
    // procd applies its own trigger asynchronously; no agent/network/firewall apply.
    let status = system(['/bin/ubus', 'call', 'service', 'event',
        '{"type":"config.change","data":{"package":"netbird_health"}}'], 1000);
    result.reload_state = status == 0 ? 'submitted' : 'submission_failed';
    return result;
}
export { get_summary, get_checks, get_events, get_config, start_check, get_job, set_config };

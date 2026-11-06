// SPDX-License-Identifier: Apache-2.0
// AuthorizedKeys forced command; cache reads only, never schedules a check.
import { read_config } from './settings.uc';
import { read_json } from './storage.uc';
import { cached_view } from './cache.uc';
import { readfile } from 'fs';
let command = getenv('SSH_ORIGINAL_COMMAND');
if ((command != null && command != 'netbird-health snapshot-v1') || length(ARGV)) {
    print('{"schema_version":1,"ok":false,"reason":"COMMAND_DENIED"}\n');
    exit(2);
}
let config = read_config(), boot = trim(readfile('/proc/sys/kernel/random/boot_id') || '');
let now = time(), result = read_json('/tmp/netbird-health/latest.json', 524288);
let view = cached_view(result, config, boot, now, read_json('/tmp/netbird-health/service.json', 4096));
if (!config || !view.ok) {
    printf('%J\n', { schema_version: 1, ok: false, node_id: config?.node?.stable_node_id || null,
        served_at: now, reason: view.reason || 'CONFIG_UNAVAILABLE' });
    exit(0);
}
let state = read_json('/etc/netbird-health/alerts/state.json', 524288), events = [];
let valid_state = state?.schema == 1 && state.node_id == config.node.stable_node_id && type(state.events) == 'array';
if (valid_state && config.notification.owner == 'central' && !view.run.flags?.maintenance) {
    for (let e in slice(state.events, 0, 32)) {
        if (e.owner != 'central' || e.node_id != config.node.stable_node_id ||
            e.state != 'queued' || e.paused === true || e.config_revision != config.revision) continue;
        let details = [];
        for (let d in slice(e.details || [], 0, 32))
            push(details, { category: d.category, id: d.id, code: d.code, severity: d.severity });
        push(events, { id: e.id, episode_id: e.episode_id, node_id: e.node_id,
            kind: e.kind, created_at: e.created_at, owner: 'central',
            categories: slice(e.categories || [], 0, 16), details });
    }
}
printf('%J\n', { schema_version: 1, ok: true, node_id: config.node.stable_node_id,
    boot_id: view.boot_id, run_id: view.run.run_id, sampled_at: view.sampled_at, served_at: now,
    config_revision: view.run.config_revision, baseline_revision: view.baseline_revision,
    max_age: view.max_age, fresh: view.fresh, monitor_enabled: config.monitor.enabled,
    overall: view.run.overall, coverage: view.run.coverage, events,
    event_gap: !valid_state || (state.dropped_events || 0) > 0,
    dropped_events: valid_state ? state.dropped_events || 0 : null });

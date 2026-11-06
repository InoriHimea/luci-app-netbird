// SPDX-License-Identifier: Apache-2.0
// Pure sampling state. An incident groups downstream evidence; delivery never
// edits the sampled health or claims that an API acceptance is a user receipt.
function copy(value) { return json(sprintf('%J', value)); }
function observe(run, config, snapshot) {
    let categories = [], details = [], unknown = false;
    function add(category, id, code, severity) {
        if (index(categories, category) < 0) push(categories, category);
        push(details, { category, id, code, severity });
    }
    let upstream = snapshot?.agent?.ok === true &&
        (snapshot.agent.data?.management === false || snapshot.agent.data?.signal === false ||
         snapshot.agent.data?.daemon_status != 'Connected');
    for (let check in run.checks || []) {
        if (check.required === false || check.status == 'DISABLED' || check.status == 'NOT_APPLICABLE') continue;
        if (check.status == 'UNKNOWN' || !check.fresh || !check.executed) { unknown = true; continue; }
        if (check.status != 'FAIL') continue;
        let category = check.category == 'control_plane' ? 'CONTROL_PLANE' :
            check.code == 'BACKUP_TAKEOVER' ? 'REDUNDANCY' :
            index(['rules', 'routes'], check.category) >= 0 ? 'ROUTE_RULE' :
            check.category == 'forward' || check.category == 'lan' ? 'FORWARD_PATH' :
            check.category == 'collection' ? 'MONITOR_SELF' : 'BUSINESS_ENDPOINT';
        add(category, check.id, check.code, check.severity);
    }
    let self_ok = snapshot?.complete === true;
    if (!self_ok) add('MONITOR_SELF', 'node:observer', snapshot?.reason || 'COLLECTION_UNAVAILABLE', 'warning');
    if (upstream && config.node.expected_connection_intent == 'connected' && index(categories, 'CONTROL_PLANE') < 0)
        add('CONTROL_PLANE', 'node:control_plane', 'CONTROL_PLANE_DISCONNECTED', 'critical');
    let intent = config.monitor.enabled !== true ? 'disabled' :
        config.node.expected_connection_intent != 'connected' ? 'intentional_disconnect' :
        run.flags?.maintenance === true ? 'maintenance' : null;
    let state = intent ? 'suppressed' : length(details) ? 'abnormal' : unknown || run.overall == 'unknown' ? 'unknown' : 'normal';
    return { state, intent, categories, details, upstream_down: upstream,
        aggregation: upstream ? 'upstream_with_downstream_details' : 'single_incident_with_details',
        overall: run.overall, observer: { state: self_ok ? 'normal' : 'abnormal',
            failure: self_ok ? null : snapshot?.reason || 'COLLECTION_UNAVAILABLE',
            run_id: run.run_id, boot_id: run.boot_id, sampled_at: run.finished_at,
            config_revision: config.revision, node_id: config.node.stable_node_id } };
}
function initial(node) {
    return { schema: 1, node_id: node, boot_id: null, last_run_id: null, last_ms: null,
        failures: 0, successes: 0, episode: null, events: [], dropped_events: 0 };
}
function advance(previous, observation, config, context) {
    let state = previous ? copy(previous) : initial(config.node.stable_node_id);
    if (state.schema !== 1 || state.node_id != config.node.stable_node_id || type(state.events) != 'array' || length(state.events) > 32)
        return { ok: false, reason: 'ALERT_STATE_INVALID' };
    if (state.last_run_id == context.run_id) return { ok: true, state, duplicate: true };
    if (state.boot_id != context.boot_id || state.last_ms == null || context.now_ms < state.last_ms ||
        context.now_ms - state.last_ms > (config.monitor.interval * 2 + config.monitor.cycle_timeout) * 1000) {
        state.failures = 0; state.successes = 0;
    }
    state.boot_id = context.boot_id; state.last_ms = context.now_ms; state.last_run_id = context.run_id;
    for (let event in state.events) {
        if (event.state == 'queued') event.paused = observation.state == 'suppressed';
        if (event.state == 'queued' && (event.owner != config.notification.owner ||
            event.sink_ref != config.notification.sink_ref)) {
            event.state = 'cancelled'; event.delivery_state = 'not_submitted'; event.error = 'OWNER_OR_SINK_CHANGED';
        }
        // Submitted work surviving a worker crash is indeterminate, never queued again.
        if (event.state == 'submitted' && (event.submitted_boot != context.boot_id ||
            type(event.submitted_ms) != 'int' || context.now_ms < event.submitted_ms || context.now_ms - event.submitted_ms > 6000)) {
            event.state = 'unknown'; event.delivery_state = 'unknown'; event.error = 'DELIVERY_UNCONFIRMED';
        }
    }
    function queue(kind, number) {
        let episode = state.episode;
        while (length(state.events) >= 32) {
            let removed = shift(state.events);
            if (removed.state == 'queued') state.dropped_events++;
        }
        let owner = config.notification.owner;
        push(state.events, { id: episode.id + ':' + kind + ':' + number, episode_id: episode.id, kind,
            owner, sink_ref: config.notification.sink_ref, config_revision: config.revision,
            node_id: config.node.stable_node_id, run_id: context.run_id, created_at: context.wall,
            boot_id: context.boot_id, next_ms: context.now_ms, attempts: 0,
            state: owner == 'none' ? 'suppressed' : 'queued', delivery_state: 'not_submitted',
            receipt_verified: false, paused: false, error: owner == 'none' ? 'OWNER_NONE' : null,
            categories: copy(observation.categories), details: copy(slice(observation.details, 0, 32)),
            detail_count: length(observation.details), evidence_run_id: context.run_id,
            overall: observation.overall, upstream_down: observation.upstream_down,
            aggregation: observation.aggregation, retry_risk: 'at_least_once_possible' });
    }
    if (observation.state == 'suppressed') {
        state.failures = 0; state.successes = 0;
    }
    else if (observation.state == 'abnormal') {
        state.failures = min(20, state.failures + 1); state.successes = 0;
        if (!state.episode) {
            if (!match(context.id || '', /^[0-9a-f]{32}$/)) return { ok: false, reason: 'ID_UNAVAILABLE' };
            state.episode = { id: context.id, first_run_id: context.run_id, first_at: context.wall,
                announced: false, reminders: 0, reminder_boot: context.boot_id, reminder_ms: context.now_ms };
        }
        if (!state.episode.announced && state.failures >= config.notification.failure_threshold) {
            queue('failure', 0); state.episode.announced = true;
            state.episode.reminder_boot = context.boot_id; state.episode.reminder_ms = context.now_ms;
        }
        // Optional reminders are bounded per incident and use monotonic time.
        else if (state.episode.announced && config.notification.reminder === true && state.episode.reminders < 3) {
            if (state.episode.reminder_boot != context.boot_id || context.now_ms < state.episode.reminder_ms) {
                state.episode.reminder_boot = context.boot_id; state.episode.reminder_ms = context.now_ms;
            }
            else if (context.now_ms - state.episode.reminder_ms >= 3600000) {
                state.episode.reminders++; queue('reminder', state.episode.reminders);
                state.episode.reminder_ms = context.now_ms;
            }
        }
    }
    else if (observation.state == 'normal') {
        state.failures = 0; state.successes = min(20, state.successes + 1);
        if (state.episode && state.successes >= config.notification.recovery_threshold) {
            if (state.episode.announced) queue('recovery', 0);
            state.episode = null;
        }
    }
    else { state.failures = 0; state.successes = 0; }
    state.observation = copy(observation);
    return { ok: true, state, duplicate: false };
}
function durable(state) {
    // Streaks/current observations live in tmpfs. Only incident/queue transitions
    // are persisted, not every normal sample or wall-clock tick.
    return { schema: 1, node_id: state.node_id, episode: state.episode?.announced ? state.episode : null,
        events: state.events, dropped_events: state.dropped_events, last_send: state.last_send || null };
}
function restore(saved, node) {
    let state = initial(node);
    if (!saved) return state;
    if (saved.schema !== 1 || saved.node_id != node || type(saved.events) != 'array' || length(saved.events) > 32) return null;
    state.episode = copy(saved.episode); state.events = copy(saved.events); state.dropped_events = saved.dropped_events || 0;
    state.last_send = copy(saved.last_send || null);
    return state;
}
export { observe, advance, durable, restore };

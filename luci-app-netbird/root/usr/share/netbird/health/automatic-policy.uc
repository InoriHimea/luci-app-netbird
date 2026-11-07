// SPDX-License-Identifier: Apache-2.0
// Pure policy: only native, fresh structural facts can vote for recovery.
const COOLDOWN_MS = 1800000, SUSTAIN_MS = 60000, FAILURE_SAMPLES = 3;
function assess_automatic(result, config, boot, now, control) {
    function blocked(reason) { return { state: 'blocked', reason, layout_verified: false, restored: false }; }
    if (config?.monitor?.enabled !== true) return blocked('MONITOR_DISABLED');
    if (config.node?.expected_connection_intent != 'connected') return blocked('AGENT_INTENTIONALLY_DISCONNECTED');
    let run = result?.run, snapshot = result?.snapshot;
    if (type(now) != 'int' || now < 0 || type(boot) != 'string' || !match(boot, /^[0-9a-f-]{36}$/) ||
        run?.boot_id != boot || snapshot?.boot_id != boot || run?.config_revision != config.revision ||
        run?.node_id != config.node.stable_node_id || snapshot?.complete !== true ||
        type(run.generation) != 'string' || !length(run.generation) || snapshot.generation != run.generation ||
        type(run.checks) != 'array' || length(run.checks) > 512)
        return blocked('AUTOMATIC_EVIDENCE_UNVERIFIED');
    if (control?.schema != 1 || control.boot_id != boot || control.config_revision != config.revision ||
        type(control.event_sequence) != 'int' || control.event_sequence < 0 ||
        control.event_sequence != run.convergence?.event_sequence)
        return blocked('AUTOMATIC_NETWORK_GENERATION_CHANGED');
    let parts = type(run.run_id) == 'string' ? split(run.run_id, ':') : [];
    if (length(parts) != 2 || parts[0] != boot || !match(parts[1], /^[0-9]{1,16}$/) ||
        int(parts[1]) > now || now - int(parts[1]) > (config.monitor.interval + config.monitor.cycle_timeout) * 1000 ||
        type(run.monotonic_duration_ms) != 'int' || run.monotonic_duration_ms < 0 || run.monotonic_duration_ms > 20000)
        return blocked('AUTOMATIC_EVIDENCE_STALE');
    let agent = snapshot.agent;
    if (agent?.ok !== true || agent.data?.daemon_status != 'Connected' ||
        agent.data.management !== true || agent.data.signal !== true)
        return blocked('AGENT_AUTH_OR_CONNECTION_UNVERIFIED');
    if (run.flags?.maintenance === true) return blocked('ACTION_MAINTENANCE_CONFLICT');
    if (run.convergence?.checking === true || index(['ready', 'failed'], run.convergence?.phase) < 0)
        return blocked('NETWORK_CONVERGENCE_UNVERIFIED');
    let checks = {}, count = 0, fault = false, restored = true;
    for (let check in run.checks) {
        if (type(check?.id) != 'string' || check.id in checks) return blocked('AUTOMATIC_EVIDENCE_INVALID');
        checks[check.id] = check;
    }
    function observed(check) {
        return check?.fresh === true && check.executed === true && index(['PASS', 'FAIL'], check.status) >= 0;
    }
    let collection = checks['node:collection'];
    if (!observed(collection) || collection.status != 'PASS') return blocked('COLLECTION_UNVERIFIED');
    for (let path in config.paths || []) if (path.enabled === true) {
        count++;
        if (path.approval?.approved !== true || path.approval.baseline_revision != config.node.baseline_revision)
            return blocked('LAYOUT_UNVERIFIED');
        for (let category in ['rules', 'routes', 'forward']) {
            let check = checks[path.id + ':' + category];
            if (!observed(check) || check.category != category) return blocked('STRUCTURE_UNVERIFIED');
            if (check.status == 'FAIL') {
                if (index(['RULE_MISSING', 'RULE_SHADOWED', 'NATIVE_RULE_DRIFT', 'ROUTE_MISSING',
                    'ROUTE_SHADOWED', 'INTERFACE_DOWN', 'FORWARD_LOOKUP_MISMATCH'], check.code) < 0)
                    return blocked('STRUCTURE_UNVERIFIED');
                fault = true;
            }
        }
        // LAN/peer/business omissions are never a recovered episode. They do
        // not turn a business-only timeout into a structural recovery vote.
        for (let category in ['peer', 'router', 'lan']) {
            let check = checks[path.id + ':' + category];
            if (!observed(check) || check.status != 'PASS') restored = false;
        }
    }
    if (!count) return blocked('NO_APPROVED_PATH');
    for (let check in run.checks) if (check.required !== false &&
        (!observed(check) || check.status != 'PASS')) restored = false;
    return { state: fault ? 'fault' : 'normal', reason: fault ? 'SUSTAINED_STRUCTURE_REQUIRED' : null,
        layout_verified: !fault, restored: !fault && restored && run.convergence.phase == 'ready' };
}
function automatic_budget_reason(state, revision, boot, now) {
    if (!state.enabled) return 'AUTOMATIC_DISABLED';
    if (state.verified_revision != revision) return 'LAYOUT_RECONFIRMATION_REQUIRED';
    if (state.episode) return 'AUTOMATIC_INCIDENT_ALREADY_ATTEMPTED';
    let last = state.last_attempt;
    if (last?.boot_id == boot && now < last.started_ms) return 'AUTOMATIC_CLOCK_REVERSED';
    // Across boots only this boot's uptime establishes a conservative delay.
    if (last && (last.boot_id == boot ? now - last.started_ms : now) < COOLDOWN_MS)
        return 'AUTOMATIC_COOLDOWN';
    return null;
}
function create_automatic_streak(interval, cycle_timeout) {
    let previous = null, first = null, last = null, samples = 0, last_run = null, last_sample = null, sample_boot = null;
    function observe(observation, run_id, now) {
        let parts = type(run_id) == 'string' ? split(run_id, ':') : [];
        if (type(now) != 'int' || now < 0 || length(parts) != 2 ||
            !match(parts[0], /^[0-9a-f-]{36}$/) || !match(parts[1], /^[0-9]{1,16}$/) ||
            int(parts[1]) > now || last != null && now < last) {
            previous = null; first = null; last = null; samples = 0; last_run = null;
            last_sample = null; sample_boot = null;
            return { trigger: false, clear: false, reason: 'AUTOMATIC_EVIDENCE_INVALID' };
        }
        let sample = int(parts[1]);
        let state = observation?.state == 'fault' ? 'fault' : observation?.restored === true ? 'restored' : null;
        if (!state) { previous = null; samples = 0; first = null; }
        if (last_run == run_id) return { trigger: false, clear: false, reason: 'DUPLICATE_SAMPLE' };
        if (last_sample != null && (sample_boot != parts[0] || sample <= last_sample)) {
            previous = null; first = null; samples = 0; last = now;
            return { trigger: false, clear: false, reason: 'AUTOMATIC_SAMPLE_REPLAY' };
        }
        if (!state || state != previous || last == null ||
            now - last > (interval * 2 + cycle_timeout) * 1000 ||
            last_sample != null && sample - last_sample > (interval * 2 + cycle_timeout) * 1000) {
            samples = 0; first = sample;
        }
        samples = state ? min(FAILURE_SAMPLES, samples + 1) : 0;
        previous = state; last = now; last_run = run_id; last_sample = sample; sample_boot = parts[0];
        return { trigger: state == 'fault' && samples >= FAILURE_SAMPLES && sample - first >= SUSTAIN_MS,
            clear: state == 'restored' && samples >= 2 && sample - first >= SUSTAIN_MS,
            samples, reason: observation?.reason || null };
    }
    return { observe };
}
export { assess_automatic, create_automatic_streak, automatic_budget_reason, COOLDOWN_MS, SUSTAIN_MS, FAILURE_SAMPLES };

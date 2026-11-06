// SPDX-License-Identifier: Apache-2.0
// Supervisor-owned episode state; workers only assess a captured generation.
function bounded(value, low, high, fallback) {
    return type(value) == 'int' && value >= low && value <= high ? value : fallback;
}
function convergence_policy(monitor) {
    return { grace_period: bounded(monitor?.grace_period, 0, 600, 30),
        convergence_timeout: bounded(monitor?.convergence_timeout, 5, 600, 60),
        event_debounce: bounded(monitor?.event_debounce, 1, 10, 2) };
}
function create_convergence(boot_id, now, monitor, previous) {
    let policy = convergence_policy(monitor);
    let valid = previous?.schema == 1 && previous.boot_id == boot_id &&
        type(previous.event_sequence) == 'int' && previous.event_sequence >= 0 &&
        index(['int', 'double'], type(previous.started_at)) >= 0 && previous.started_at >= 0 &&
        index(['int', 'double'], type(previous.deadline_at)) >= 0 && previous.deadline_at >= previous.started_at &&
        previous.deadline_at - previous.started_at <= 600 &&
        index(['int', 'double'], type(previous.last_now)) >= 0 && previous.last_now <= now &&
        type(previous.episode_open) == 'bool' && index(['startup', 'event'], previous.trigger) >= 0;
    let state = valid ? json(sprintf('%J', previous)) : {
        schema: 1, boot_id, event_sequence: 0, started_at: 0,
        deadline_at: policy.grace_period, episode_open: now < policy.grace_period, trigger: 'startup', last_now: now };
    // A reload never lengthens a pending deadline. Startup is boot-relative,
    // not process-relative, so repeatedly crashing the service cannot renew it.
    state.deadline_at = min(state.deadline_at, state.started_at +
        (state.trigger == 'startup' ? policy.grace_period : policy.convergence_timeout));
    state.last_now = now;
    return state;
}
function convergence_event(state, now, monitor) {
    let policy = convergence_policy(monitor);
    state.event_sequence++;
    if (!state.episode_open) {
        state.started_at = now;
        state.deadline_at = now + policy.convergence_timeout;
        state.trigger = 'event';
        state.episode_open = true;
    }
    // Once an episode is open, even a sustained event flood or failed check
    // cannot reset it. Only complete fresh readiness closes the episode.
    state.last_now = max(state.last_now, now);
}
function assess_convergence(state, checks, now, changed) {
    let result = { phase: 'unknown', reason: 'CONVERGENCE_CONTEXT_INVALID', checking: false,
        event_sequence: state?.event_sequence ?? 0,
        started_at: state?.started_at ?? 0, deadline_at: state?.deadline_at ?? 0 };
    if (!state || state.schema != 1 || now < state.last_now) return result;
    if (changed) { result.reason = 'CONVERGENCE_EVENT_DURING_CYCLE'; return result; }
    let failure = false, unknown = false, present = {}, count = 0;
    for (let check in checks || []) {
        if (check.required === false || index(['DISABLED', 'NOT_APPLICABLE'], check.status) >= 0) continue;
        count++;
        present[check.category] = true;
        if (!check.fresh || !check.executed || check.status == 'UNKNOWN') unknown = true;
        else if (check.status == 'FAIL') failure = true;
        else if (check.status != 'PASS') unknown = true;
    }
    // Neither a Connected daemon nor prefix presence alone proves forwarding
    // and business readiness. Missing coverage remains UNKNOWN after expiry.
    let complete = count > 0 && present.rules && present.routes && present.forward && present.endpoint;
    if (complete && !failure && !unknown) {
        result.phase = 'ready'; result.reason = 'CONVERGENCE_READY'; return result;
    }
    if (state.episode_open && now < state.deadline_at) {
        result.phase = state.trigger == 'startup' ? 'startup_grace' : 'converging';
        result.reason = state.trigger == 'startup' ? 'STARTUP_GRACE' : 'NETWORK_CONVERGING';
        result.checking = true;
    }
    else if (failure) { result.phase = 'failed'; result.reason = 'CONVERGENCE_FAILED'; }
    else result.reason = complete ? 'CONVERGENCE_EVIDENCE_UNKNOWN' : 'CONVERGENCE_BASELINE_INCOMPLETE';
    return result;
}
export { convergence_policy, create_convergence, convergence_event, assess_convergence };

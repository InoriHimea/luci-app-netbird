// SPDX-License-Identifier: Apache-2.0
// All deadlines use monotonic seconds. Wall time is evidence only.
export function create_schedule(boot_id, now, interval) {
    return { boot_id, interval: type(interval) == 'int' && interval >= 30 && interval <= 3600 ? interval : 60,
        active: false, manual: false, event_first: null, event_last: null,
        manual_until: now, next_periodic: now, last_now: now, clock_boundary: false };
};
export function request_check(state, now) {
    // A short completed check also satisfies the same burst of UI requests.
    now ??= state.last_now;
    if (!state.active && now >= state.manual_until) state.manual = true;
};
export function route_event(state, now) {
    if (state.event_first == null) state.event_first = now;
    state.event_last = now;
};
export function next_check(state, now) {
    if (now < state.last_now) {
        state.clock_boundary = true;
        state.next_periodic = now;
        state.manual_until = now;
        state.event_first = null;
        state.event_last = null;
    }
    state.last_now = now;
    if (state.active) return null;
    let reason = state.clock_boundary ? 'clock_boundary' : state.manual ? 'manual' : null;
    if (!reason && state.event_first != null &&
        (now - state.event_last >= 2 || now - state.event_first >= 5)) reason = 'event';
    if (!reason && now >= state.next_periodic) reason = 'periodic';
    if (!reason) return null;
    state.active = true;
    state.manual = false;
    state.manual_until = now + 2;
    state.event_first = null;
    state.event_last = null;
    state.next_periodic = now + state.interval;
    return reason;
};
export function finish_check(state, now) {
    state.active = false;
    state.clock_boundary = false;
    state.last_now = now;
};

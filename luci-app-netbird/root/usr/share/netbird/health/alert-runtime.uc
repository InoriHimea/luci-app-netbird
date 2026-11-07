// SPDX-License-Identifier: Apache-2.0
import { open, lstat } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { observe, advance, automatic_failure, durable, restore } from './alerts.uc';
import { read_config } from './settings.uc';
import { opaque_id } from './jobs.uc';
import { monotonic_ms } from './runner.uc';
import { maintenance_state } from './maintenance.uc';
import { create_notifications } from './notification.uc';
const LIMIT = 524288;
function public_state(state, policy) {
    let events = state.events || [], recent = length(events) ? events[length(events) - 1] : null;
    let pending = length(filter(events, e => e.state == 'queued'));
    let delivery = recent?.delivery_state || 'not_requested';
    return { owner: policy.owner, state: state.observation?.state || 'unknown',
        failures: state.failures || 0, successes: state.successes || 0,
        episode_id: state.episode?.id || null, first_run_id: state.episode?.first_run_id || null,
        pending, dropped_events: state.dropped_events || 0,
        categories: state.observation?.categories || [], upstream_down: state.observation?.upstream_down === true,
        aggregation: state.observation?.aggregation || null,
        run_id: state.last_run_id, boot_id: state.boot_id,
        sampled_at: state.observation?.observer?.sampled_at ?? null,
        config_revision: state.observation?.observer?.config_revision ?? null,
        delivery_state: pending ? 'pending' : delivery, receipt_verified: false,
        delivery_problem: length(filter(events, e => e.error && e.state != 'suppressed' && e.state != 'cancelled')) > 0 ?
            'NOTIFICATION_DELIVERY' : null,
        recent: recent ? { id: recent.id, kind: recent.kind, state: recent.state,
            delivery_state: recent.delivery_state, attempts: recent.attempts, error: recent.error,
            http_status: recent.http_status ?? null, receipt_verified: false } : null,
        retry_risk: 'at_least_once_possible', ownership_takeover: false };
}
function create_alerts(root, persistent, settings, clock, sender, guard) {
    settings ??= read_config; clock ??= monotonic_ms;
    sender ??= create_notifications(root, settings, null, clock, persistent).send_alert;
    guard ??= maintenance_state;
    function transaction(action) {
        if (!private_dir(root) || !private_dir(persistent)) return { ok: false, reason: 'ALERT_STORAGE_UNAVAILABLE' };
        let lock = open(root + '/alerts.lock', 'a', 0600);
        if (!lock || !lock.lock('xn')) { if (lock) lock.close(); return { ok: false, reason: 'ALERT_BUSY' }; }
        let result;
        try {
            let config = settings(), saved_path = persistent + '/state.json', runtime_path = root + '/alerts.json';
            if (!config) result = { ok: false, reason: 'CONFIG_UNAVAILABLE' };
            else {
                let saved_stat = lstat(saved_path), runtime_stat = lstat(runtime_path);
                let saved = read_json(saved_path, LIMIT), runtime = read_json(runtime_path, LIMIT);
                if ((saved_stat && (saved_stat.type != 'file' || saved_stat.uid != 0 || saved_stat.mode != 0600 || !saved)) ||
                    (runtime_stat && (runtime_stat.type != 'file' || runtime_stat.uid != 0 || runtime_stat.mode != 0600 || !runtime)))
                    result = { ok: false, reason: 'ALERT_STATE_INVALID' };
                else {
                    let state = runtime || restore(saved, config.node.stable_node_id);
                    let previous_durable = sprintf('%J', saved);
                    if (state && saved) {
                        let recovered = restore(saved, config.node.stable_node_id);
                        if (!recovered) state = null;
                        else {
                            state.events = recovered.events;
                            state.episode = recovered.episode || (state.episode?.announced === false ? state.episode : null);
                            state.dropped_events = recovered.dropped_events; state.last_send = recovered.last_send;
                            state.automatic_failure_id = recovered.automatic_failure_id;
                        }
                    }
                    if (!state || state.schema !== 1 || state.node_id != config.node.stable_node_id ||
                        type(state.events) != 'array' || length(state.events) > 32) result = { ok: false, reason: 'ALERT_STATE_INVALID' };
                    else {
                        result = action(state, config, clock());
                        if (result.ok && result.state) {
                            let projection = durable(result.state);
                            // Durable write-ahead precedes tmp publication and every submission.
                            if ((sprintf('%J', projection) != previous_durable &&
                                !atomic_json(persistent, 'state.json', projection, LIMIT)) ||
                                !atomic_json(root, 'alerts.json', result.state, LIMIT))
                                result = { ok: false, reason: 'ALERT_STORAGE_UNAVAILABLE' };
                            else result.summary = public_state(result.state, config.notification);
                        }
                    }
                }
            }
        }
        catch (e) { result = { ok: false, reason: 'ALERT_STATE_INVALID' }; }
        lock.close(); return result;
    }
    function record(result) {
        let sampled = transaction((state, config, now) => {
            if (result.run?.config_revision != config.revision || result.run?.node_id != config.node.stable_node_id)
                return { ok: false, reason: 'CONFIG_CHANGED' };
            let observation = observe(result.run, config, result.snapshot);
            return advance(state, observation, config, { run_id: result.run.run_id, boot_id: result.run.boot_id,
                now_ms: now, wall: result.run.finished_at,
                id: observation.state == 'abnormal' ? state.episode?.id || opaque_id() : null });
        });
        if (sampled.ok) atomic_json(root, 'observer.json', sampled.state.observation.observer, 2048);
        return sampled;
    }
    function record_automatic_failure(episode) {
        return transaction((state, config, now) => automatic_failure(state, episode, config,
            { run_id: state.last_run_id || 'automatic:' + episode.id,
                boot_id: state.boot_id, now_ms: now, wall: time() }));
    }
    function pending() {
        let state = read_json(root + '/alerts.json', LIMIT), now = clock();
        return type(state?.events) == 'array' && length(state.events) <= 32 &&
            length(filter(state.events, e => e.owner == 'local' && e.state == 'queued' && !e.paused &&
                (e.boot_id != state.boot_id || now >= e.next_ms))) > 0;
    }
    function run_pending() {
        if (!private_dir(root)) return { ok: false, reason: 'ALERT_STORAGE_UNAVAILABLE' };
        let lease = open(root + '/alert-worker.lock', 'a', 0600);
        if (!lease || !lease.lock('xn')) { if (lease) lease.close(); return { ok: false, reason: 'ALERT_BUSY' }; }
        let claimed = transaction((state, config, now) => {
            if (config.monitor.enabled !== true || config.node.expected_connection_intent != 'connected' || guard()?.state != 'idle')
                return { ok: false, reason: 'NOTIFICATION_INTENT_SUPPRESSED' };
            let event = null, earlier = {};
            for (let candidate in state.events) {
                if (candidate.state != 'queued' || candidate.owner != 'local' || candidate.paused) continue;
                if (candidate.owner != config.notification.owner || candidate.sink_ref != config.notification.sink_ref) {
                    candidate.state = 'cancelled'; candidate.error = 'OWNER_OR_SINK_CHANGED'; continue;
                }
                if (candidate.boot_id != state.boot_id) { candidate.boot_id = state.boot_id; candidate.next_ms = now + 30000; }
                let blocked = earlier[candidate.episode_id];
                earlier[candidate.episode_id] = true;
                if (!blocked && candidate.next_ms <= now && !event) event = candidate;
            }
            if (!event) return { ok: true, state, reason: 'NO_PENDING_NOTIFICATION' };
            if (state.last_send?.boot_id == state.boot_id && now >= state.last_send.ms && now - state.last_send.ms < 30000)
                return { ok: true, state, reason: 'RATE_LIMITED' };
            event.state = 'submitted'; event.delivery_state = 'submitted'; event.attempts++;
            event.submitted_ms = now; event.submitted_boot = state.boot_id;
            state.last_send = { boot_id: state.boot_id, ms: now };
            return { ok: true, state, event: json(sprintf('%J', event)) };
        });
        if (!claimed.ok || !claimed.event) { lease.close(); return claimed; }
        let delivery;
        try { delivery = sender(claimed.event); }
        catch (e) { delivery = { state: 'unknown', delivery_state: 'unknown', error: 'DELIVERY_UNCONFIRMED' }; }
        let finished = transaction((state, config, now) => {
            let event = null;
            for (let candidate in state.events) if (candidate.id == claimed.event.id) event = candidate;
            if (!event || event.state != 'submitted') return { ok: false, reason: 'SUBMISSION_NOT_CURRENT' };
            let safe_preflight = delivery.delivery_state == 'not_submitted' ||
                (delivery.delivery_state == 'unknown' && index([6, 7, 60], delivery.exit_code) >= 0);
            let rejected_retryable = delivery.delivery_state == 'rejected' &&
                (delivery.http_status == 429 || delivery.http_status >= 500);
            for (let key in ['delivery_state', 'error', 'http_status', 'exit_code', 'transport_reason', 'duration_ms'])
                if (key in delivery) event[key] = delivery[key];
            if (safe_preflight) event.delivery_state = 'not_submitted';
            let retry = (safe_preflight || rejected_retryable) && event.attempts < 8 &&
                event.owner == config.notification.owner && event.sink_ref == config.notification.sink_ref;
            event.state = retry ? 'queued' : delivery.state;
            event.next_ms = now + min(900000, 30000 * (2 ** (event.attempts - 1)));
            event.receipt_verified = false;
            if (!retry && event.attempts >= 8 && (safe_preflight || rejected_retryable)) event.error = 'RETRY_EXHAUSTED';
            return { ok: true, state, event };
        });
        lease.close(); return finished;
    }
    function summary() {
        let config = settings(), state = read_json(root + '/alerts.json', LIMIT);
        return config && state ? { ok: true, alert: public_state(state, config.notification) } :
            { ok: false, reason: 'ALERT_STATE_UNAVAILABLE' };
    }
    return { record, record_automatic_failure, pending, run_pending, summary };
}
function production_alerts() {
    if (!private_dir('/etc/netbird-health')) return null;
    return create_alerts('/tmp/netbird-health', '/etc/netbird-health/alerts');
}
export { create_alerts, production_alerts, public_state };

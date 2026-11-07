// SPDX-License-Identifier: Apache-2.0
import { create_automatic_store } from './automatic-store.uc';
import { assess_automatic, create_automatic_streak, automatic_budget_reason } from './automatic-policy.uc';
import { create_recovery_jobs } from './recovery-jobs.uc';
import { recovery_eligibility } from './recovery-policy.uc';
import { dispatch_recovery } from './recovery.uc';
import { monotonic_ms } from './runner.uc';
import { read_json } from './storage.uc';
function create_automatic_runtime(config, boot, failure_alert) {
    let store = create_automatic_store(), jobs = create_recovery_jobs();
    let streak = create_automatic_streak(config.monitor.interval, config.monitor.cycle_timeout);
    function observe(result) {
        let now = monotonic_ms(), loaded = store.get();
        if (!loaded.ok) {
            streak.observe(null, result?.run?.run_id, now);
            return { enabled: false, state: 'unknown', reason: loaded.reason };
        }
        let state = loaded.state, episode = state.episode;
        if (episode?.phase == 'reserved') {
            let prior = jobs.get(episode.id, episode.actor);
            if (prior.ok && index(['finished', 'unknown'], prior.job.state) >= 0) {
                store.finish(episode.id, prior.job.outcome, prior.job.reason);
                loaded = store.get();
            }
            else if (!prior.ok && prior.reason == 'JOB_UNKNOWN' &&
                (state.last_attempt.boot_id != boot || now >= state.last_attempt.started_ms + 90000)) {
                // Crash between durable budget claim and job publication. No
                // dispatch replay; retain the charged incident as UNKNOWN.
                store.finish(episode.id, 'UNKNOWN', 'DISPATCH_UNCONFIRMED');
                loaded = store.get();
            }
            if (!loaded.ok) return { enabled: false, state: 'unknown', reason: loaded.reason };
            state = loaded.state; episode = state.episode;
        }
        if (episode?.phase == 'finished' && episode.outcome != 'RESTORED' && failure_alert)
            failure_alert(episode);
        let observation = assess_automatic(result, config, boot, now,
            read_json('/tmp/netbird-health/convergence-control.json', 4096));
        let votes = streak.observe(observation, result?.run?.run_id, now);
        if (episode?.phase == 'finished' && votes.clear) {
            let cleared = store.clear(episode.id, true);
            if (!cleared.ok) return { enabled: state.enabled, state: 'unknown', reason: cleared.reason };
            state = cleared.state; episode = null;
        }
        let summary = { enabled: state.enabled, verified_revision: state.verified_revision,
            episode, state: episode ? 'stopped_for_incident' : observation.state,
            reason: automatic_budget_reason(state, config.revision, boot, now) || observation.reason };
        if (!votes.trigger || summary.reason && summary.reason != 'SUSTAINED_STRUCTURE_REQUIRED') return summary;
        let policy = recovery_eligibility(false);
        if (!policy.ok) { summary.state = 'blocked'; summary.reason = policy.reason; return summary; }
        // Read-only preflight above means cooldown/conflict/continued incident
        // polls do not write approvals. A single serialized supervisor dispatches.
        let prepared = jobs.prepare(state.actor, config.revision, 'automatic');
        if (!prepared.ok) { summary.reason = prepared.reason; return summary; }
        let reserved = store.reserve(prepared.id, config.revision);
        if (!reserved.ok) { summary.reason = reserved.reason; return summary; }
        let claimed = jobs.claim(prepared.id, state.actor, config.revision, true, result);
        if (!claimed.ok) {
            store.finish(prepared.id, 'UNKNOWN', claimed.reason);
            summary.reason = claimed.reason; summary.state = 'stopped_for_incident'; return summary;
        }
        let dispatched = dispatch_recovery(claimed);
        return { enabled: true, verified_revision: config.revision, episode: reserved.state.episode,
            state: 'submitted', reason: dispatched.dispatch == 'submitted' ? 'RECOVERY_SUBMITTED' : 'DISPATCH_UNCONFIRMED' };
    }
    return { observe };
}
export { create_automatic_runtime };

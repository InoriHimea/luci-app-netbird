// SPDX-License-Identifier: Apache-2.0
import { freshness } from './boundary.uc';
import { aggregate } from './model.uc';
import { assess_convergence } from './convergence.uc';
function cached_view(result, config, boot, now, service) {
    if (type(result?.run?.checks) != 'array' || length(result.run.checks) > 4096)
        return { ok: false, reason: 'NO_RESULT' };
    if (type(config?.monitor?.interval) != 'int') return { ok: false, reason: 'CONFIG_UNAVAILABLE' };
    let age = freshness(result, boot, now, config.monitor.interval * 2 + config.monitor.cycle_timeout);
    let same_scope = result.run.config_revision == config.revision && result.baseline_revision == config.node.baseline_revision;
    let event_changed = result.run.convergence && service?.boot_id == boot && service.event_sequence != null &&
        service.event_sequence != result.run.convergence.event_sequence;
    let reason = !same_scope ? 'CONFIG_CHANGED' : event_changed ? 'CONVERGENCE_EVENT_DURING_CYCLE' : age.reason;
    let stale = !same_scope || event_changed || !age.fresh;
    // Preserve the cached original for diagnostics/export. Only this effective
    // view downgrades sampled PASS/FAIL to UNKNOWN when proof is no longer valid.
    let run = json(sprintf('%J', result.run));
    let convergence_remaining_ms = null;
    let convergence_expires_at = null;
    for (let item in run.checks) {
        if (stale) {
            item.fresh = false;
            if (item.status == 'PASS' || item.status == 'FAIL') { item.status = 'UNKNOWN'; item.code = reason; }
        }
    }
    if (run.convergence) {
        let sampled = run.convergence, mono = clock(true);
        run.convergence = assess_convergence({ schema: 1, last_now: 0,
            event_sequence: sampled.event_sequence, started_at: sampled.started_at,
            deadline_at: sampled.deadline_at, episode_open: sampled.checking,
            trigger: sampled.phase == 'startup_grace' ? 'startup' : 'event' },
            run.checks, mono[0] + mono[1] / 1000000000, stale ||
                index(['CONVERGENCE_CONTEXT_INVALID', 'CONVERGENCE_EVENT_DURING_CYCLE'], sampled.reason) >= 0);
        if (run.convergence.checking) {
            convergence_remaining_ms = max(0, int((run.convergence.deadline_at - mono[0] - mono[1] / 1000000000) * 1000));
            convergence_expires_at = now + int(convergence_remaining_ms / 1000);
        }
    }
    let checking = service?.boot_id == boot && service.phase == 'running' &&
        type(service.sampled_at) == 'int' && now >= service.sampled_at &&
        now - service.sampled_at <= config.monitor.cycle_timeout + 2;
    let summary;
    try { summary = aggregate(run.checks, { stale, checking: checking || run.convergence?.checking === true,
        enabled: config.monitor.enabled, maintenance: run.flags?.maintenance === true }); }
    catch (e) { return { ok: false, reason: 'CACHE_INVALID' }; }
    for (let key, value in summary) run[key] = value;
    if (run.overall == 'healthy' && run.convergence && run.convergence.phase != 'ready') run.overall = 'unknown';
    return { ok: true, run, fresh: !stale, reason, sampled_at: result.sampled_at, convergence_expires_at, convergence_remaining_ms,
        event_sequence: result.run.convergence?.event_sequence ?? null,
        boot_id: result.snapshot?.boot_id, baseline_revision: result.baseline_revision,
        max_age: config.monitor.interval * 2 + config.monitor.cycle_timeout,
        scope: same_scope ? 'full_approved_baseline' : 'previous_approved_baseline', current_config_revision: config.revision };
}
function refresh_page(page, config, boot, now, service) {
    if (!page.ok) return page;
    if (!config) return { ok: false, reason: 'CONFIG_UNAVAILABLE' };
    let metadata = page.metadata;
    if (type(metadata?.max_age) != 'int' || metadata.max_age < 0)
        return { ok: false, reason: 'PAGE_STATE_INVALID' };
    let age = freshness({ sampled_at: metadata.sampled_at, snapshot: { boot_id: metadata.boot_id } },
        boot, now, metadata.max_age);
    let same_scope = metadata.config_revision == config.revision && metadata.baseline_revision == config.node.baseline_revision;
    let event_changed = metadata.event_sequence != null && service?.boot_id == boot &&
        service.event_sequence != null && service.event_sequence != metadata.event_sequence;
    let reason = !same_scope ? 'CONFIG_CHANGED' : event_changed ? 'CONVERGENCE_EVENT_DURING_CYCLE' : age.reason || metadata.reason;
    let view = json(sprintf('%J', page));
    view.metadata.current_config_revision = config.revision;
    view.metadata.scope = same_scope ? metadata.scope : 'previous_approved_baseline';
    view.metadata.fresh = metadata.fresh === true && !reason;
    view.metadata.reason = reason;
    if (!view.metadata.fresh) {
        for (let item in view.items) {
            item.fresh = false;
            if (item.status == 'PASS' || item.status == 'FAIL') { item.status = 'UNKNOWN'; item.code = reason; }
        }
    }
    return view;
}
export { cached_view, refresh_page };

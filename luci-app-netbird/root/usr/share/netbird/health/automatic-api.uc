// SPDX-License-Identifier: Apache-2.0
import { readfile } from 'fs';
import { read_config } from './settings.uc';
import { read_json } from './storage.uc';
import { monotonic_ms } from './runner.uc';
import { assess_automatic, automatic_budget_reason } from './automatic-policy.uc';
import { create_automatic_store } from './automatic-store.uc';
import { recovery_eligibility } from './recovery-policy.uc';
function public_state(state, config, boot, now) {
    let episode = state.episode;
    return { enabled: state.enabled, verified_revision: state.verified_revision,
        current_revision: config?.revision, reason: automatic_budget_reason(state, config?.revision, boot, now),
        cooldown_seconds: 1800, attempts_per_incident: 1,
        episode: episode ? { id: episode.id, phase: episode.phase, outcome: episode.outcome, reason: episode.reason } : null };
}
function get_automatic() {
    let loaded = create_automatic_store().get();
    if (!loaded.ok) return loaded;
    return { ok: true, automatic: public_state(loaded.state, read_config(),
        trim(readfile('/proc/sys/kernel/random/boot_id') || ''), monotonic_ms()) };
}
function set_automatic(args, actor) {
    if (type(args) != 'object') return { ok: false, reason: 'AUTOMATIC_ARGUMENT_INVALID' };
    for (let key in keys(args)) if (index(['enabled', 'expected_revision', 'confirmed', 'ubus_rpc_session'], key) < 0)
        return { ok: false, reason: 'AUTOMATIC_ARGUMENT_INVALID' };
    if (type(args.enabled) != 'bool' || type(args.expected_revision) != 'int' || args.confirmed !== true)
        return { ok: false, reason: 'AUTOMATIC_ARGUMENT_INVALID' };
    let config = read_config();
    if (!config && args.enabled) return { ok: false, reason: 'CONFIG_UNAVAILABLE' };
    if (args.enabled && config.revision != args.expected_revision) return { ok: false, reason: 'CONFIG_CHANGED' };
    let boot = trim(readfile('/proc/sys/kernel/random/boot_id') || ''), now = monotonic_ms(), verified = false;
    if (args.enabled) {
        let eligibility = recovery_eligibility(false);
        if (!eligibility.ok) return eligibility;
        let assessment = assess_automatic(read_json('/tmp/netbird-health/latest.json', 524288), config, boot, now,
            read_json('/tmp/netbird-health/convergence-control.json', 4096));
        if (!assessment.layout_verified) return { ok: false, reason: assessment.reason || 'LAYOUT_UNVERIFIED' };
        verified = true;
    }
    // Disable remains available during maintenance, stale evidence, and revision
    // changes. It revokes late workers without deleting the charged incident.
    let changed = create_automatic_store().set_enabled(args.enabled, actor, config?.revision ?? args.expected_revision, verified);
    if (!changed.ok) return changed;
    return { ok: true, automatic: public_state(changed.state, config, boot, now) };
}
export { get_automatic, set_automatic };

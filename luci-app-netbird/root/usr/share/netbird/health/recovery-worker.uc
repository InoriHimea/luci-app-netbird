// SPDX-License-Identifier: Apache-2.0
// Private root worker: the only operand is a previously claimed opaque job ID.
import { readfile } from 'fs';
import { create_recovery_jobs } from './recovery-jobs.uc';
import { create_action_journal } from './action-journal.uc';
import { read_config } from './settings.uc';
import { read_json } from './storage.uc';
import { recovery_eligibility } from './recovery-policy.uc';
import { recovery_verdict } from './recovery-verdict.uc';
import { maintenance_state } from './maintenance.uc';
import { run_action_command, run_command, monotonic_ms } from './runner.uc';
import { create_automatic_store } from './automatic-store.uc';
import { assess_automatic } from './automatic-policy.uc';
if (length(ARGV) != 1 || !match(ARGV[0], /^[0-9a-f]{32}$/)) exit(2);
const id = ARGV[0], jobs = create_recovery_jobs();
let begun = jobs.begin(id);
if (!begun.ok) exit(3);
let job = begun.job, gate = loadfile('/usr/share/rpcd/ucode/lib/action_lock.uc')().create();
let automatic = job.mode == 'automatic', owner = automatic ? 'automatic-recovery' : 'manual-recovery';
let automatic_store = automatic ? create_automatic_store() : null;
function automatic_reason(current) {
    if (!automatic) return null;
    let loaded = automatic_store.get();
    if (!loaded.ok) return loaded.reason;
    let state = loaded.state, episode = state.episode;
    if (!state.enabled) return 'AUTOMATIC_DISABLED';
    if (state.verified_revision != current?.revision) return 'LAYOUT_RECONFIRMATION_REQUIRED';
    if (episode?.id != id || episode.actor != job.actor || episode.phase != 'reserved' ||
        episode.authorization_id != state.authorization_id) return 'AUTOMATIC_AUTHORIZATION_CHANGED';
    let assessed = assess_automatic(read_json('/tmp/netbird-health/latest.json', 524288), current,
        job.boot_id, monotonic_ms(), read_json('/tmp/netbird-health/convergence-control.json', 4096));
    return assessed.state == 'fault' ? null : assessed.reason || 'AUTOMATIC_STRUCTURE_FAULT_CLEARED';
}
let acquired = gate.acquire(owner);
let command = { ok: false, invoked: false, cleanup_confirmed: true, exit_code: null };
if (!acquired.ok) { jobs.finish(id, command, 'UNKNOWN', 'ACTION_BUSY', null); exit(4); }
let policy = recovery_eligibility(true), config = read_config(), reason = null;
if (!policy.ok) reason = policy.reason;
else if (config?.revision != job.revision) reason = 'CONFIG_CHANGED';
else if (config.monitor.enabled !== true) reason = 'MONITOR_DISABLED';
if (!reason) reason = automatic_reason(config);
let journal = create_action_journal(), reserved = null;
if (!reason) {
    reserved = journal.reserve(id, owner, job.actor, 'restart');
    if (!reserved.ok) reason = reserved.reason;
}
if (!reason) {
    // Atomic rename alone does not establish power-loss ordering. Persist the
    // claimed job, pre-action evidence and budget before permitting an effect.
    let barrier = run_command(['/bin/busybox', 'sync'], 3000);
    if (!barrier.ok) reason = 'ACTION_AUDIT_SYNC_FAILED';
}
if (!reason) {
    let current_job = jobs.get(id, job.actor);
    if (!current_job.ok || current_job.job.state != 'running' || current_job.job.boot_id != job.boot_id)
        reason = 'RECOVERY_JOB_NO_LONGER_ACTIVE';
    if (!reason && automatic) {
        let latest_config = read_config(), latest_policy = recovery_eligibility(true);
        if (!latest_policy.ok) reason = latest_policy.reason;
        else if (latest_config?.revision != job.revision) reason = 'CONFIG_CHANGED';
        else reason = automatic_reason(latest_config);
    }
}
if (reason) {
    if (reserved?.ok) journal.finish(id, command);
    jobs.finish(id, command, 'UNKNOWN', reason, null);
    if (automatic) automatic_store.finish(id, 'UNKNOWN', reason);
    gate.release(); exit(4);
}
command = run_action_command('restart');
let recorded = journal.finish(id, command), after = null;
let verdict = { outcome: 'UNKNOWN', reason: 'POST_CHECK_UNVERIFIED' }, drained = command.cleanup_confirmed;
if (command.invoked && command.cleanup_confirmed) {
    let post_started = monotonic_ms();
    let checked = run_command(['/usr/bin/ucode', '/usr/share/netbird/health/cycle-host.uc', '20000'], 20000);
    drained = drained && checked.cleanup_confirmed;
    if (checked.ok) {
        after = read_json('/tmp/netbird-health/latest.json', 524288);
        let current = read_config(), boot = trim(readfile('/proc/sys/kernel/random/boot_id') || '');
        verdict = current?.revision == job.revision ? recovery_verdict(command, after, current, boot, post_started) :
            { outcome: 'UNKNOWN', reason: 'CONFIG_CHANGED' };
    }
    else verdict = { outcome: command.ok ? 'UNKNOWN' : 'FAILED', reason: 'POST_CHECK_UNAVAILABLE' };
}
else verdict = recovery_verdict(command, null, config, '', 0);
let final_maintenance = maintenance_state();
if (final_maintenance.markers.update_settings || final_maintenance.markers.settings)
    verdict = { outcome: 'UNKNOWN', reason: 'SETTINGS_APPLICATION_PENDING' };
if (!recorded.ok) verdict = { outcome: 'UNKNOWN', reason: 'ACTION_AUDIT_FAILED' };
let finished = jobs.finish(id, command, verdict.outcome, verdict.reason, after);
if (automatic && finished.ok) automatic_store.finish(id, verdict.outcome, verdict.reason);
// Preserve the owner marker after an uncertain drain. Kernel lease release is
// not proof that orphan commands stopped; subsequent actions quarantine it.
if (!command.invoked || drained) gate.release();
exit(finished.ok ? 0 : 5);

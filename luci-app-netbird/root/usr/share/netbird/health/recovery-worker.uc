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
if (length(ARGV) != 1 || !match(ARGV[0], /^[0-9a-f]{32}$/)) exit(2);
const id = ARGV[0], jobs = create_recovery_jobs();
let begun = jobs.begin(id);
if (!begun.ok) exit(3);
let job = begun.job, gate = loadfile('/usr/share/rpcd/ucode/lib/action_lock.uc')().create();
let acquired = gate.acquire('manual-recovery');
let command = { ok: false, invoked: false, cleanup_confirmed: true, exit_code: null };
if (!acquired.ok) { jobs.finish(id, command, 'UNKNOWN', 'ACTION_BUSY', null); exit(4); }
let policy = recovery_eligibility(true), config = read_config(), reason = null;
if (!policy.ok) reason = policy.reason;
else if (config?.revision != job.revision) reason = 'CONFIG_CHANGED';
else if (config.monitor.enabled !== true) reason = 'MONITOR_DISABLED';
let journal = create_action_journal(), reserved = null;
if (!reason) {
    reserved = journal.reserve(id, 'manual-recovery', job.actor, 'restart');
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
}
if (reason) {
    if (reserved?.ok) journal.finish(id, command);
    jobs.finish(id, command, 'UNKNOWN', reason, null);
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
// Preserve the owner marker after an uncertain drain. Kernel lease release is
// not proof that orphan commands stopped; subsequent actions quarantine it.
if (!command.invoked || drained) gate.release();
exit(finished.ok ? 0 : 5);

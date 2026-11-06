// SPDX-License-Identifier: Apache-2.0
// Private root CLI. The environment flag is an invocation guard, not an
// authentication boundary. No RPC command, executable or target is accepted.
import { lstat } from 'fs';
import { maintenance_state } from './health/maintenance.uc';
import { run_action_command, run_command } from './health/runner.uc';
import { create_action_journal } from './health/action-journal.uc';
if (getenv('NB_ACTION_WORKER') != '1' || length(ARGV) != 1 || ARGV[0] != 'settings') exit(2);
const lib = getenv('NBLIB') || '/usr/share/rpcd/ucode/lib';
let lock = loadfile(lib + '/action_lock.uc')().create();
let acquired = lock.acquire('settings');
if (!acquired.ok) { print('ACTION_DEFERRED\n'); exit(75); }
let state = maintenance_state();
if (lstat('/etc/netbird-update/transaction.json') && (state.transaction_phase == null ||
    index(['committed', 'rolled_back', 'aborted', 'idle'], state.transaction_phase) < 0)) {
    lock.release(); print('ACTION_DEFERRED\n'); exit(75);
}
let journal = create_action_journal();
let reservation = journal.reserve(acquired.id, 'settings', 'local-root', 'settings');
if (!reservation.ok) {
    lock.release(); print('SETTINGS_ACTION_FAILED ' + reservation.reason + '\n'); exit(1);
}
// The reservation must survive loss of power before any settings effect can run.
let barrier = run_command(['/bin/busybox', 'sync'], 3000);
if (!barrier.ok) {
    journal.finish(acquired.id, { ok: false, invoked: false, cleanup_confirmed: true, exit_code: null });
    lock.release(); print('SETTINGS_ACTION_FAILED ACTION_AUDIT_SYNC_FAILED\n'); exit(1);
}
// Only this fixed child re-enters reload_service. Untrusted RPC/config inputs
// cannot set process environment; a root caller already controls the service.
let result = run_action_command('settings');
let recorded = journal.finish(acquired.id, result);
// An uncertain drain leaves the marker behind. Owner exit closes its kernel
// lease, but the next caller must quarantine orphan commands before proceeding.
if (!result.invoked || result.cleanup_confirmed) lock.release();
if (!result.ok) print(sprintf('SETTINGS_ACTION_FAILED %s exit=%s\n', result.reason, result.exit_code ?? 'unknown'));
if (!recorded.ok) { print('SETTINGS_ACTION_FAILED ' + recorded.reason + '\n'); if (result.ok) exit(1); }
exit(result.ok ? 0 : type(result.exit_code) == 'int' && result.exit_code > 0 && result.exit_code < 256 ? result.exit_code : 1);

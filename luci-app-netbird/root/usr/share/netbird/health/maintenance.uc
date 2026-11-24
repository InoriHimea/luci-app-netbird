// SPDX-License-Identifier: Apache-2.0
import { lstat } from 'fs';
import { read_json } from './storage.uc';
// root is an internal isolated-test seam, never a configuration/RPC argument.
export function maintenance_state(root) {
    root ??= '';
    let journal = root + '/etc/netbird-update/transaction.json';
    let exists = lstat(journal) != null;
    let transaction = exists ? read_json(journal, 65536) : null;
    let phase = type(transaction?.phase) == 'string' && match(transaction.phase, /^[a-z_]{1,64}$/) ? transaction.phase : null;
    let markers = {
        binary_operation: lstat(root + '/tmp/nb-binop.lock') != null,
        update_settings: lstat(root + '/etc/netbird-update/settings.pending') != null,
        settings: lstat(root + '/etc/netbird-settings.pending') != null
    };
    let phase_active = phase != null && index(['committed', 'rolled_back', 'aborted', 'idle'], phase) < 0;
    // Durable maintenance excludes the short-lived binary-operation lease: the
    // watchdog takes it for ~0.1s every ~30s, so it is not a generation signal.
    let durable_active = markers.update_settings || markers.settings || phase_active;
    let active = markers.binary_operation || durable_active;
    return { state: active ? 'active' : exists && phase == null ? 'unknown' : 'idle',
        durable_active, journal_unreadable: exists && phase == null, transaction_phase: phase, markers,
        // Existing watchdogs expose no reliable per-action audit/ownership marker.
        // Their activity cannot be inferred from temporal proximity or daemon PID.
        watchdog: { state: 'unknown', reason: 'WATCHDOG_ACTIVITY_UNOBSERVABLE' },
        attribution: 'cause_undetermined' };
};
// Generation identity of a maintenance observation. The binary-operation lease
// is deliberately excluded: any network mutation made under it is still caught
// by the process/rules/routes/links/firewall comparison.
export function maintenance_identity(m) {
    if (type(m) != 'object') return null;
    // Derived from markers/phase rather than durable_active so snapshots cached
    // before this field existed compare consistently with new ones.
    let phase = type(m.transaction_phase) == 'string' ? m.transaction_phase : null;
    let update_settings = m.markers?.update_settings === true, settings = m.markers?.settings === true;
    let durable = update_settings || settings ||
        (phase != null && index(['committed', 'rolled_back', 'aborted', 'idle'], phase) < 0);
    // A damaged journal stays unknown even while the lease masks state as active.
    return { state: m.state == 'unknown' || m.journal_unreadable === true ? 'unknown' : durable ? 'active' : 'idle',
        transaction_phase: phase, update_settings, settings };
};

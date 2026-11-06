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
    let active = markers.binary_operation || markers.update_settings || markers.settings ||
        (phase != null && index(['committed', 'rolled_back', 'aborted', 'idle'], phase) < 0);
    return { state: active ? 'active' : exists && phase == null ? 'unknown' : 'idle',
        transaction_phase: phase, markers,
        // Existing watchdogs expose no reliable per-action audit/ownership marker.
        // Their activity cannot be inferred from temporal proximity or daemon PID.
        watchdog: { state: 'unknown', reason: 'WATCHDOG_ACTIVITY_UNOBSERVABLE' },
        attribution: 'cause_undetermined' };
};

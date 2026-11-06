// SPDX-License-Identifier: Apache-2.0
import { open, lstat, readfile } from 'fs';
import { private_dir, atomic_json, read_json } from './storage.uc';
import { monotonic_ms } from './runner.uc';
const WINDOW_MS = 3600000, COOLDOWN_MS = 60000;
// All effects still require the shared action owner. This shorter storage lock
// serializes reservations/publication only and is never an execution lease.
function create_action_journal(root, clock, boot) {
    root ??= '/etc/netbird-actions'; clock ??= monotonic_ms;
    boot ??= trim(readfile('/proc/sys/kernel/random/boot_id') || '');
    function valid(state) {
        if (state?.schema_version != 1 || type(state.boot_id) != 'string' ||
            !match(state.boot_id, /^[0-9a-f-]{36}$/) || type(state.last_ms) != 'int' || state.last_ms < 0 ||
            type(state.attempts) != 'array' || length(state.attempts) > 3 ||
            type(state.events) != 'array' || length(state.events) > 64) return false;
        for (let at in state.attempts) if (type(at) != 'int' || at < 0 || at > state.last_ms) return false;
        for (let item in state.events)
            if (type(item) != 'object' || type(item.id) != 'string' || !match(item.id, /^[0-9a-f]{32}$/)) return false;
        return true;
    }
    function transact(action) {
        if (!match(boot, /^[0-9a-f-]{36}$/) || !private_dir(root))
            return { ok: false, reason: 'ACTION_STORAGE_UNAVAILABLE' };
        let st = lstat(root + '/journal.lock');
        if (st && (st.type != 'file' || st.uid != 0 || st.mode != 0600))
            return { ok: false, reason: 'ACTION_STORAGE_UNAVAILABLE' };
        let lock = open(root + '/journal.lock', 'ae', 0600);
        if (!lock || !lock.lock('xn')) { lock?.close(); return { ok: false, reason: 'ACTION_JOURNAL_BUSY' }; }
        let result;
        try {
            let path = root + '/journal.json', stored = lstat(path), now = clock();
            let safe = !stored || stored.type == 'file' && stored.uid == 0 && stored.mode == 0600 && stored.size <= 65536;
            let state = stored && safe ? read_json(path, 65536) :
                { schema_version: 1, boot_id: boot, last_ms: now, attempts: [], events: [] };
            if (!safe || !valid(state)) result = { ok: false, reason: 'ACTION_JOURNAL_INVALID' };
            else if (type(now) != 'int' || now < 0 || state.boot_id == boot && now < state.last_ms)
                result = { ok: false, reason: 'ACTION_CLOCK_REVERSED' };
            else {
                // Elapsed time across boots is unprovable. Reanchor every retained
                // charge once, rather than minting a new budget on each reboot.
                let changed = state.boot_id != boot;
                if (changed) {
                    state.attempts = map(state.attempts, () => now);
                    state.boot_id = boot;
                }
                state.last_ms = now;
                state.attempts = filter(state.attempts, at => now - at < WINDOW_MS);
                result = action(state, now);
                if ((changed || result.dirty) && !atomic_json(root, 'journal.json', state, 65536))
                    result = { ok: false, reason: 'ACTION_STORAGE_UNAVAILABLE' };
                delete result.dirty;
            }
        }
        catch (e) { result = { ok: false, reason: 'ACTION_JOURNAL_INVALID' }; }
        lock.close(); return result;
    }
    function reserve(id, owner, actor, kind) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/) ||
            type(owner) != 'string' || !match(owner, /^[a-z][a-z0-9_-]{0,47}$/) ||
            type(actor) != 'string' || !match(actor, /^[A-Za-z0-9_.@+-]{1,96}$/) ||
            index(['restart', 'settings', 'lifecycle', 'update'], kind) < 0)
            return { ok: false, reason: 'ACTION_ARGUMENT_INVALID' };
        return transact((state, now) => {
            for (let item in state.events) if (item.id == id)
                return { ok: false, reason: 'ACTION_ALREADY_RESERVED', id };
            // Configuration is user intent, including an explicit service stop.
            // It must not be turned into a silently deferred recovery request.
            if (kind != 'settings') {
                if (length(state.attempts) && now - state.attempts[length(state.attempts) - 1] < COOLDOWN_MS)
                    return { ok: false, reason: 'ACTION_COOLDOWN' };
                if (length(state.attempts) >= 3) return { ok: false, reason: 'ACTION_BUDGET_EXHAUSTED' };
            }
            let event = { id, owner, actor, kind, boot_id: boot, started_ms: now,
                started_at: time(), phase: 'reserved', outcome: 'UNKNOWN' };
            while (length(state.events) >= 64) shift(state.events);
            push(state.events, event); push(state.attempts, now);
            while (length(state.attempts) > 3) shift(state.attempts);
            return { ok: true, id, dirty: true };
        });
    }
    function finish(id, command) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/) || type(command) != 'object' ||
            type(command.invoked) != 'bool' || type(command.cleanup_confirmed) != 'bool' ||
            type(command.ok) != 'bool' || command.reason != null &&
                (type(command.reason) != 'string' || !match(command.reason, /^[A-Z][A-Z0-9_]{0,63}$/)) ||
            command.exit_code != null && (type(command.exit_code) != 'int' || command.exit_code < -255 || command.exit_code > 255))
            return { ok: false, reason: 'ACTION_ARGUMENT_INVALID' };
        return transact((state, now) => {
            for (let item in state.events) if (item.id == id) {
                if (item.phase != 'reserved') return { ok: false, reason: 'ACTION_ALREADY_FINISHED' };
                item.phase = 'command_finished'; item.finished_ms = now; item.finished_at = time();
                item.command = { ok: command.ok, reason: command.reason, exit_code: command.exit_code,
                    invoked: command.invoked, cleanup_confirmed: command.cleanup_confirmed };
                // Command exit is never a path/business-health verdict.
                return { ok: true, id, dirty: true };
            }
            return { ok: false, reason: 'ACTION_UNKNOWN' };
        });
    }
    return { reserve, finish };
}
export { create_action_journal };

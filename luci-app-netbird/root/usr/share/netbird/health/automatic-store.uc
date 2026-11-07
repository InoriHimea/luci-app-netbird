// SPDX-License-Identifier: Apache-2.0
// Independent opt-in and event budget. No poll/heartbeat writes; disable and
// re-enable never erase the incident or its last charged monotonic deadline.
import { open, lstat, readfile } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { monotonic_ms } from './runner.uc';
import { automatic_budget_reason } from './automatic-policy.uc';
import { opaque_id } from './jobs.uc';
function create_automatic_store(root, clock, boot) {
    root ??= '/etc/netbird-automatic'; clock ??= monotonic_ms;
    boot ??= trim(readfile('/proc/sys/kernel/random/boot_id') || '');
    function valid(state) {
        if (type(state) != 'object' || length(keys(state)) != 7) return false;
        for (let key in ['schema', 'enabled', 'verified_revision', 'actor', 'authorization_id', 'last_attempt', 'episode'])
            if (!(key in state)) return false;
        if (state?.schema != 1 || type(state.enabled) != 'bool' ||
            state.verified_revision != null && (type(state.verified_revision) != 'int' || state.verified_revision < 0) ||
            state.actor != null && (type(state.actor) != 'string' || !match(state.actor, /^[A-Za-z0-9_.@+-]{1,96}$/))) return false;
        if (state.authorization_id != null && (type(state.authorization_id) != 'string' ||
            !match(state.authorization_id, /^[0-9a-f]{32}$/))) return false;
        let attempt = state.last_attempt;
        if (attempt != null && (type(attempt) != 'object' || type(attempt.boot_id) != 'string' ||
            !match(attempt.boot_id, /^[0-9a-f-]{36}$/) || type(attempt.started_ms) != 'int' || attempt.started_ms < 0)) return false;
        let episode = state.episode;
        if (episode != null && (type(episode) != 'object' || type(episode.id) != 'string' ||
            !match(episode.id, /^[0-9a-f]{32}$/) || index(['reserved', 'finished'], episode.phase) < 0 ||
            type(episode.actor) != 'string' || !match(episode.actor, /^[A-Za-z0-9_.@+-]{1,96}$/) ||
            type(episode.authorization_id) != 'string' || !match(episode.authorization_id, /^[0-9a-f]{32}$/) ||
            index(['UNKNOWN', 'FAILED', 'PARTIAL', 'RESTORED'], episode.outcome) < 0 ||
            type(episode.revision) != 'int' || episode.revision < 0 || attempt == null ||
            type(episode.reason) != 'string' || !match(episode.reason, /^[A-Z][A-Z0-9_]{0,63}$/))) return false;
        return state.enabled !== true || type(state.verified_revision) == 'int' &&
            type(state.actor) == 'string' && type(state.authorization_id) == 'string';
    }
    function transact(action) {
        if (!match(boot, /^[0-9a-f-]{36}$/) || !private_dir(root))
            return { ok: false, reason: 'AUTOMATIC_STORAGE_UNAVAILABLE' };
        let lock_stat = lstat(root + '/state.lock');
        if (lock_stat && (lock_stat.type != 'file' || lock_stat.uid != 0 || lock_stat.mode != 0600))
            return { ok: false, reason: 'AUTOMATIC_STORAGE_UNAVAILABLE' };
        let lock = open(root + '/state.lock', 'ae', 0600);
        if (!lock || !lock.lock('xn')) { lock?.close(); return { ok: false, reason: 'AUTOMATIC_STATE_BUSY' }; }
        let result;
        try {
            let st = lstat(root + '/state.json'), safe = !st ||
                st.type == 'file' && st.uid == 0 && st.mode == 0600 && st.size <= 8192;
            let state = st && safe ? read_json(root + '/state.json', 8192) :
                { schema: 1, enabled: false, verified_revision: null, actor: null, authorization_id: null,
                    last_attempt: null, episode: null };
            let now = clock();
            if (!safe || !valid(state)) result = { ok: false, reason: 'AUTOMATIC_STATE_INVALID' };
            else if (type(now) != 'int' || now < 0) result = { ok: false, reason: 'AUTOMATIC_CLOCK_INVALID' };
            else {
                result = action(state, now);
                if (result.dirty && !atomic_json(root, 'state.json', state, 8192))
                    result = { ok: false, reason: 'AUTOMATIC_STORAGE_UNAVAILABLE' };
                delete result.dirty;
            }
        }
        catch (e) { result = { ok: false, reason: 'AUTOMATIC_STATE_INVALID' }; }
        lock.close(); return result;
    }
    function get() { return transact((state) => ({ ok: true, state })); }
    function set_enabled(enabled, actor, revision, layout_verified) {
        if (type(enabled) != 'bool' || type(actor) != 'string' || !match(actor, /^[A-Za-z0-9_.@+-]{1,96}$/) ||
            type(revision) != 'int' || revision < 0 || revision > 2147483647)
            return { ok: false, reason: 'AUTOMATIC_ARGUMENT_INVALID' };
        if (enabled && layout_verified !== true) return { ok: false, reason: 'LAYOUT_UNVERIFIED' };
        return transact((state) => {
            if (state.enabled === enabled && (!enabled || state.verified_revision == revision && state.actor == actor))
                return { ok: true, state };
            let authorization = enabled ? opaque_id() : null;
            if (enabled && (type(authorization) != 'string' || !match(authorization, /^[0-9a-f]{32}$/)))
                return { ok: false, reason: 'ID_UNAVAILABLE' };
            state.authorization_id = authorization;
            state.enabled = enabled;
            if (enabled) { state.verified_revision = revision; state.actor = actor; }
            return { ok: true, state, dirty: true };
        });
    }
    function reserve(id, revision) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/) || type(revision) != 'int' || revision < 0)
            return { ok: false, reason: 'AUTOMATIC_ARGUMENT_INVALID' };
        return transact((state, now) => {
            let reason = automatic_budget_reason(state, revision, boot, now);
            if (reason) return { ok: false, reason };
            state.last_attempt = { boot_id: boot, started_ms: now };
            state.episode = { id, revision, actor: state.actor, authorization_id: state.authorization_id,
                phase: 'reserved', outcome: 'UNKNOWN', reason: 'DISPATCH_UNCONFIRMED' };
            return { ok: true, state, dirty: true };
        });
    }
    function finish(id, outcome, reason) {
        if (index(['UNKNOWN', 'FAILED', 'PARTIAL', 'RESTORED'], outcome) < 0 ||
            type(reason) != 'string' || !match(reason, /^[A-Z][A-Z0-9_]{0,63}$/))
            return { ok: false, reason: 'AUTOMATIC_ARGUMENT_INVALID' };
        return transact((state) => {
            if (state.episode?.id != id) return { ok: false, reason: 'AUTOMATIC_INCIDENT_UNKNOWN' };
            if (state.episode.phase != 'reserved') return { ok: false, reason: 'AUTOMATIC_ALREADY_FINISHED' };
            state.episode.phase = 'finished'; state.episode.outcome = outcome; state.episode.reason = reason;
            return { ok: true, state, dirty: true };
        });
    }
    function clear(id, restored) {
        if (restored !== true) return { ok: false, reason: 'AUTOMATIC_RECOVERY_UNVERIFIED' };
        return transact((state) => {
            if (state.episode?.id != id || state.episode.phase != 'finished')
                return { ok: false, reason: 'AUTOMATIC_INCIDENT_NOT_FINISHED' };
            state.episode = null;
            return { ok: true, state, dirty: true };
        });
    }
    return { get, set_enabled, reserve, finish, clear };
}
export { create_automatic_store };

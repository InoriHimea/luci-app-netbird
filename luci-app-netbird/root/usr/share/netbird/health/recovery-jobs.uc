// SPDX-License-Identifier: Apache-2.0
import { open, lstat, readfile } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { opaque_id } from './jobs.uc';
import { monotonic_ms } from './runner.uc';
import { evidence } from './export.uc';
const LIMIT = 524288, SNAPSHOT_LIMIT = 98304;
function identifier(value) { return type(value) == 'string' && !!match(value, /^[0-9a-f]{32}$/); }
function actor_valid(value) { return type(value) == 'string' && !!match(value, /^[A-Za-z0-9_.@+-]{1,96}$/); }
function revision_valid(value) { return type(value) == 'int' && value >= 0 && value <= 2147483647; }
function create_recovery_jobs(root, clock, boot) {
    root ??= '/etc/netbird-recovery'; clock ??= monotonic_ms;
    boot ??= trim(readfile('/proc/sys/kernel/random/boot_id') || '');
    function valid(state) {
        if (state?.schema_version != 1 || type(state.boot_id) != 'string' ||
            !match(state.boot_id, /^[0-9a-f-]{36}$/) || type(state.last_ms) != 'int' || state.last_ms < 0 ||
            type(state.approvals) != 'array' || length(state.approvals) > 8 ||
            type(state.jobs) != 'array' || length(state.jobs) > 2) return false;
        let ids = {};
        for (let item in state.approvals) {
            if (!identifier(item?.id) || ids[item.id] || !actor_valid(item.actor) ||
                !revision_valid(item.revision) || type(item.created_ms) != 'int' || item.created_ms < 0 ||
                type(item.expires_ms) != 'int' || item.expires_ms != item.created_ms + 120000) return false;
            ids[item.id] = true;
        }
        for (let job in state.jobs) {
            if (!identifier(job?.id) || ids[job.id] || !actor_valid(job.actor) || !revision_valid(job.revision) ||
                index(['queued', 'running', 'finished', 'unknown'], job.state) < 0 ||
                type(job.created_ms) != 'int' || job.created_ms < 0 ||
                type(job.deadline_ms) != 'int' || job.deadline_ms != job.created_ms + 90000 ||
                type(job.before) != 'object' || index(['RESTORED', 'PARTIAL', 'FAILED', 'UNKNOWN'], job.outcome) < 0)
                return false;
            ids[job.id] = true;
        }
        return true;
    }
    function transact(action) {
        if (!match(boot, /^[0-9a-f-]{36}$/) || !private_dir(root))
            return { ok: false, reason: 'RECOVERY_STORAGE_UNAVAILABLE' };
        let st = lstat(root + '/recovery.lock');
        if (st && (st.type != 'file' || st.uid != 0 || st.mode != 0600))
            return { ok: false, reason: 'RECOVERY_STORAGE_UNAVAILABLE' };
        let lock = open(root + '/recovery.lock', 'ae', 0600);
        if (!lock || !lock.lock('xn')) { lock?.close(); return { ok: false, reason: 'RECOVERY_BUSY' }; }
        let result;
        try {
            let stored = lstat(root + '/state.json'), now = clock();
            let safe = !stored || stored.type == 'file' && stored.uid == 0 && stored.mode == 0600 && stored.size <= LIMIT;
            let state = stored && safe ? read_json(root + '/state.json', LIMIT) :
                { schema_version: 1, boot_id: boot, last_ms: now, approvals: [], jobs: [] };
            if (!safe || !valid(state)) result = { ok: false, reason: 'RECOVERY_STATE_INVALID' };
            else if (type(now) != 'int' || now < 0 || state.boot_id == boot && now < state.last_ms)
                result = { ok: false, reason: 'RECOVERY_CLOCK_REVERSED' };
            else {
                // A claimed job is never queued again, including after a reboot or
                // a lost worker-start acknowledgement. Query reports uncertainty.
                let changed = state.boot_id != boot, dirty = changed;
                if (changed) { state.approvals = []; state.boot_id = boot; }
                state.approvals = filter(state.approvals, item => now < item.expires_ms);
                for (let job in state.jobs) if (index(['queued', 'running'], job.state) >= 0 &&
                    (changed || now >= job.deadline_ms)) {
                    job.state = 'unknown'; job.outcome = 'UNKNOWN';
                    job.reason = changed ? 'WORKER_INTERRUPTED_BY_BOOT' : 'WORKER_RESULT_UNKNOWN'; dirty = true;
                }
                state.last_ms = now;
                result = action(state, now);
                if ((dirty || result.dirty) && !atomic_json(root, 'state.json', state, LIMIT))
                    result = { ok: false, reason: 'RECOVERY_STORAGE_UNAVAILABLE' };
                delete result.dirty;
            }
        }
        catch (e) { result = { ok: false, reason: 'RECOVERY_STATE_INVALID' }; }
        lock.close(); return result;
    }
    function prepare(actor, revision) {
        if (!actor_valid(actor) || !revision_valid(revision)) return { ok: false, reason: 'RECOVERY_ARGUMENT_INVALID' };
        return transact((state, now) => {
            let id = opaque_id();
            if (!identifier(id)) return { ok: false, reason: 'ID_UNAVAILABLE' };
            while (length(state.approvals) >= 8) shift(state.approvals);
            push(state.approvals, { id, actor, revision, created_ms: now, expires_ms: now + 120000 });
            return { ok: true, id, actor, revision, expires_in_ms: 120000,
                operation: 'managed_agent_restart', automatic_retry: false, dirty: true };
        });
    }
    function claim(id, actor, revision, confirmed, before) {
        if (!identifier(id) || !actor_valid(actor) || !revision_valid(revision) || confirmed !== true)
            return { ok: false, reason: 'RECOVERY_CONFIRMATION_REQUIRED' };
        return transact((state, now) => {
            for (let job in state.jobs) if (job.id == id)
                return job.actor == actor ? { ok: true, job, coalesced: true } : { ok: false, reason: 'RECOVERY_DENIED' };
            let approval = null;
            for (let item in state.approvals) if (item.id == id) approval = item;
            if (!approval || approval.actor != actor) return { ok: false, reason: 'RECOVERY_DENIED' };
            if (approval.revision != revision) return { ok: false, reason: 'CONFIG_CHANGED' };
            for (let job in state.jobs) if (index(['queued', 'running'], job.state) >= 0)
                return { ok: false, reason: 'RECOVERY_BUSY' };
            let snapshot = evidence(before);
            if (!snapshot || length(sprintf('%J', snapshot)) > SNAPSHOT_LIMIT)
                return { ok: false, reason: 'RECOVERY_EVIDENCE_UNAVAILABLE' };
            let job = { id, actor, revision, boot_id: boot, created_ms: now, created_at: time(),
                deadline_ms: now + 90000, state: 'queued', outcome: 'UNKNOWN', reason: 'QUEUED', before: snapshot };
            while (length(state.jobs) >= 2) shift(state.jobs);
            push(state.jobs, job);
            state.approvals = filter(state.approvals, item => item.id != id);
            return { ok: true, job, coalesced: false, dirty: true };
        });
    }
    function begin(id) {
        if (!identifier(id)) return { ok: false, reason: 'RECOVERY_ARGUMENT_INVALID' };
        return transact((state, now) => {
            for (let job in state.jobs) if (job.id == id) {
                if (job.state != 'queued') return { ok: false, reason: 'RECOVERY_ALREADY_CLAIMED' };
                job.state = 'running'; job.started_ms = now; job.reason = 'RUNNING';
                return { ok: true, job, dirty: true };
            }
            return { ok: false, reason: 'JOB_UNKNOWN' };
        });
    }
    function finish(id, command, outcome, reason, after) {
        if (!identifier(id) || index(['RESTORED', 'PARTIAL', 'FAILED', 'UNKNOWN'], outcome) < 0 ||
            type(reason) != 'string' || !match(reason, /^[A-Z][A-Z0-9_]{0,63}$/) ||
            type(command?.invoked) != 'bool' || type(command.cleanup_confirmed) != 'bool' ||
            type(command.ok) != 'bool' || command.exit_code != null &&
                (type(command.exit_code) != 'int' || command.exit_code < -255 || command.exit_code > 255))
            return { ok: false, reason: 'RECOVERY_ARGUMENT_INVALID' };
        let snapshot = after == null ? null : evidence(after);
        if (after != null && (!snapshot || length(sprintf('%J', snapshot)) > SNAPSHOT_LIMIT))
            return { ok: false, reason: 'RECOVERY_EVIDENCE_UNAVAILABLE' };
        return transact((state, now) => {
            for (let job in state.jobs) if (job.id == id) {
                if (job.state != 'running') return { ok: false, reason: 'RECOVERY_ALREADY_FINISHED' };
                job.state = 'finished'; job.finished_ms = now; job.finished_at = time();
                job.command = { invoked: command.invoked, cleanup_confirmed: command.cleanup_confirmed,
                    ok: command.ok, exit_code: command.exit_code };
                job.outcome = outcome; job.reason = reason; job.after = snapshot;
                return { ok: true, job, dirty: true };
            }
            return { ok: false, reason: 'JOB_UNKNOWN' };
        });
    }
    function get(id, actor) {
        if (!identifier(id) || !actor_valid(actor)) return { ok: false, reason: 'RECOVERY_ARGUMENT_INVALID' };
        // Atomic publication makes a read lock unnecessary. The worker may be
        // updating its phase during an immediate duplicate confirmation; that
        // must return the same job, not fail on its short storage lease.
        if (!private_dir(root)) return { ok: false, reason: 'RECOVERY_STORAGE_UNAVAILABLE' };
        let st = lstat(root + '/state.json');
        if (!st) return { ok: false, reason: 'JOB_UNKNOWN' };
        if (st.type != 'file' || st.uid != 0 || st.mode != 0600 || st.size > LIMIT)
            return { ok: false, reason: 'RECOVERY_STATE_INVALID' };
        let state = read_json(root + '/state.json', LIMIT), now = clock();
        if (!valid(state)) return { ok: false, reason: 'RECOVERY_STATE_INVALID' };
        if (type(now) != 'int' || now < 0 || state.boot_id == boot && now < state.last_ms)
            return { ok: false, reason: 'RECOVERY_CLOCK_REVERSED' };
        for (let job in state.jobs) if (job.id == id) {
            if (job.actor != actor) return { ok: false, reason: 'RECOVERY_DENIED' };
            if (index(['queued', 'running'], job.state) >= 0 && (state.boot_id != boot || now >= job.deadline_ms)) {
                job.state = 'unknown'; job.outcome = 'UNKNOWN';
                job.reason = state.boot_id != boot ? 'WORKER_INTERRUPTED_BY_BOOT' : 'WORKER_RESULT_UNKNOWN';
            }
            return { ok: true, job };
        }
        return { ok: false, reason: 'JOB_UNKNOWN' };
    }
    return { prepare, claim, begin, finish, get };
}
export { create_recovery_jobs };

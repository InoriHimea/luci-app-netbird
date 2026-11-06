// SPDX-License-Identifier: Apache-2.0
import { open, unlink } from 'fs';
import { private_dir, atomic_json, read_json } from './storage.uc';
import { monotonic_ms } from './runner.uc';
function opaque_id() {
    let source = open('/dev/urandom', 'r');
    if (!source) return null;
    let bytes = source.read(16); source.close();
    if (type(bytes) != 'string' || length(bytes) != 16) return null;
    let id = '';
    for (let i = 0; i < 16; i++) id += sprintf('%02x', ord(bytes, i));
    return id;
}
function create_jobs(root, clock) {
    clock ??= monotonic_ms;
    function expired(job, now) { return now < job.created_ms || now > job.expires_ms; }
    // Cycles have an independent 20s hard deadline. Allow 10s for publication
    // and group draining; retention lifetime must never act as execution lease.
    function overdue(job, now) {
        return job?.state == 'running' && (type(job.started_ms) != 'int' ||
            now < job.started_ms || now - job.started_ms > 30000);
    }
    function retire(job, now) {
        job.state = 'failed'; job.error = 'EXECUTION_LEASE_EXPIRED'; job.finished_ms = now;
    }
    function find(state, id) {
        for (let job in state.jobs) if (job.id == id) return job;
        return null;
    }
    function transact(action) {
        if (!private_dir(root)) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        let lock = open(root + '/jobs.lock', 'a', 0600);
        if (!lock || !lock.lock('xn')) { if (lock) lock.close(); return { ok: false, reason: 'JOBS_BUSY' }; }
        let result;
        try {
            let state = read_json(root + '/jobs.json', 32768) || { active: null, recent: null, jobs: [] };
            if (type(state.jobs) != 'array' || length(state.jobs) > 16) result = { ok: false, reason: 'JOB_STATE_INVALID' };
            else {
                let now = clock();
                let active = find(state, state.active), recovered = overdue(active, now);
                if (recovered) { retire(active, now); state.active = null; state.recent = active.id; }
                result = action(state, now);
                if (recovered) result.dirty = true;
                if (result.dirty && !atomic_json(root, 'jobs.json', state, 32768)) result = { ok: false, reason: 'STORAGE_UNAVAILABLE' };
                delete result.dirty;
            }
        }
        catch (e) { result = { ok: false, reason: 'JOB_STATE_INVALID' }; }
        lock.close();
        return result;
    }
    function add(state, revision, now, running) {
        if (type(revision) != 'int' || revision < 0 || revision > 2147483647) return { ok: false, reason: 'REVISION_INVALID' };
        let active = find(state, state.active);
        if (active && !expired(active, now) && index(['queued', 'running'], active.state) >= 0) {
            if (active.config_revision != revision) {
                if (active.state == 'running') return { ok: false, reason: 'CONFIG_CHANGED' };
                active.state = 'failed'; active.error = 'CONFIG_CHANGED'; active.finished_ms = now;
                state.active = null;
            }
            else {
                if (running && active.state == 'queued') {
                    active.state = 'running'; active.started_ms = now;
                    return { ok: true, job: active, coalesced: true, dirty: true };
                }
                return { ok: true, job: active, coalesced: true };
            }
        }
        let recent = find(state, state.recent);
        if (!running && recent && recent.error != 'EXECUTION_LEASE_EXPIRED' && !expired(recent, now) && recent.config_revision == revision &&
            recent.finished_ms != null && now >= recent.finished_ms && now - recent.finished_ms <= 2000)
            return { ok: true, job: recent, coalesced: true };
        let id = opaque_id();
        if (!id || find(state, id)) return { ok: false, reason: 'ID_UNAVAILABLE' };
        // Evict before publication, bounding metadata and result bytes even if
        // the publisher dies immediately after its next atomic rename.
        while (length(state.jobs) >= 16) {
            let old = shift(state.jobs);
            if (type(old.id) == 'string' && match(old.id, /^[0-9a-f]{32}$/)) unlink(root + '/job-' + old.id + '.json');
        }
        let job = { id, state: running ? 'running' : 'queued', config_revision: revision,
            scope: 'full_approved_baseline', created_ms: now, started_ms: running ? now : null,
            finished_ms: null, expires_ms: now + 600000, error: null };
        push(state.jobs, job); state.active = id;
        return { ok: true, job, coalesced: false, dirty: true };
    }
    function enqueue(revision) {
        if (type(revision) != 'int' || revision < 0 || revision > 2147483647)
            return { ok: false, reason: 'REVISION_INVALID' };
        if (!private_dir(root)) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        // Existing issued jobs need no mutation. A supervisor's atomic state
        // transition must not turn concurrent requests into spurious JOBS_BUSY.
        let state = read_json(root + '/jobs.json', 32768), now = clock();
        if (type(state?.jobs) == 'array' && length(state.jobs) <= 16) {
            let active = find(state, state.active), recent = find(state, state.recent);
            if (active && !expired(active, now) && active.config_revision == revision &&
                index(['queued', 'running'], active.state) >= 0 && !overdue(active, now))
                return { ok: true, job: active, coalesced: true };
            if (recent && recent.error != 'EXECUTION_LEASE_EXPIRED' && !expired(recent, now) && recent.config_revision == revision && recent.finished_ms != null &&
                now >= recent.finished_ms && now - recent.finished_ms <= 2000)
                return { ok: true, job: recent, coalesced: true };
        }
        return transact((state, now) => add(state, revision, now, false));
    }
    function begin(revision) { return transact((state, now) => add(state, revision, now, true)); }
    function get(id) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/)) return { ok: false, reason: 'JOB_INVALID' };
        // Reads never acquire a writer lock, create directories or run probes.
        let state = read_json(root + '/jobs.json', 32768), job;
        if (type(state?.jobs) != 'array' || length(state.jobs) > 16 || !(job = find(state, id)))
            return { ok: false, reason: 'JOB_UNKNOWN' };
        let now = clock();
        if (expired(job, now)) return { ok: false, reason: 'JOB_EXPIRED' };
        if (overdue(job, now)) retire(job, now);
        let run = null;
        if (job.state == 'done') {
            run = read_json(root + '/job-' + id + '.json', 524288);
            if (!run) return { ok: false, reason: 'JOB_RESULT_UNAVAILABLE' };
        }
        return { ok: true, job, run };
    }
    function finish(id, run, error) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/)) return { ok: false, reason: 'JOB_INVALID' };
        return transact((state, now) => {
            let job = find(state, id);
            if (!job) return { ok: false, reason: 'JOB_UNKNOWN' };
            if (expired(job, now)) return { ok: false, reason: 'JOB_EXPIRED' };
            if (state.active != id || job.state != 'running') return { ok: false, reason: 'JOB_NOT_RUNNING' };
            if (!error && (type(run) != 'object' || run.config_revision != job.config_revision)) error = 'CONFIG_CHANGED';
            if (!error && !atomic_json(root, 'job-' + id + '.json', run)) error = 'JOB_RESULT_UNAVAILABLE';
            job.state = error ? 'failed' : 'done';
            job.error = error ? (match(error, /^[A-Z][A-Z0-9_]{0,63}$/) ? error : 'JOB_FAILED') : null;
            job.finished_ms = now; state.active = null; state.recent = id;
            return { ok: true, job, dirty: true };
        });
    }
    return { enqueue, begin, get, finish };
}
export { create_jobs, opaque_id };

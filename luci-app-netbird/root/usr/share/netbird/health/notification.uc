// SPDX-License-Identifier: Apache-2.0
import { open, lstat, unlink } from 'fs';
import * as uloop from 'uloop';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { read_config } from './settings.uc';
import { hostname, permitted_address } from './config.uc';
import { opaque_id } from './jobs.uc';
import { monotonic_ms, run_command } from './runner.uc';
function create_notifications(root, settings, sink_root, clock) {
    settings ??= read_config;
    sink_root ??= '/etc/netbird-health/sinks';
    clock ??= monotonic_ms;
    function sink(config) {
        if (config?.notification?.owner != 'local' || !config.notification.sink_ref)
            return { ok: false, reason: 'NOTIFICATION_NOT_CONFIGURED' };
        let ref = config.notification.sink_ref;
        if (type(ref) != 'string' || !match(ref, /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$/))
            return { ok: false, reason: 'SINK_INVALID' };
        let dir = lstat(sink_root), path = sink_root + '/' + ref + '.json', st = lstat(path);
        if (!dir || !st) return { ok: false, reason: 'SINK_NOT_CONFIGURED' };
        if (dir.type != 'directory' || dir.uid != 0 || dir.mode != 0700 ||
            st.type != 'file' || st.uid != 0 || st.mode != 0600)
            return { ok: false, reason: 'SINK_INVALID' };
        let data = read_json(path, 8192), allowed = ['schema', 'kind', 'host', 'port', 'address', 'token'];
        if (!data || length(keys(data)) != length(allowed)) return { ok: false, reason: 'SINK_INVALID' };
        for (let key in keys(data)) if (index(allowed, key) < 0) return { ok: false, reason: 'SINK_INVALID' };
        if (data.schema !== 1 || data.kind != 'gotify' || !hostname(data.host) || !match(data.host, /[A-Za-z]$/) ||
            type(data.port) != 'int' || data.port < 1 || data.port > 65535 || !permitted_address(data.address) ||
            type(data.token) != 'string' || length(data.token) > 512 || !match(data.token, /^[A-Za-z0-9_-]+$/))
            return { ok: false, reason: 'SINK_INVALID' };
        return { ok: true, data, ref };
    }
    function transact(action) {
        if (!private_dir(root)) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        let lock = open(root + '/notification.lock', 'a', 0600);
        if (!lock || !lock.lock('xn')) { if (lock) lock.close(); return { ok: false, reason: 'NOTIFICATION_BUSY' }; }
        let result;
        try {
            let state = read_json(root + '/notification-jobs.json', 32768) || { jobs: [], active: null, recent: null };
            if (type(state.jobs) != 'array' || length(state.jobs) > 16) result = { ok: false, reason: 'JOB_STATE_INVALID' };
            else {
                result = action(state, clock());
                if (result.dirty && !atomic_json(root, 'notification-jobs.json', state, 32768))
                    result = { ok: false, reason: 'STORAGE_UNAVAILABLE' };
                delete result.dirty;
            }
        }
        catch (e) { result = { ok: false, reason: 'NOTIFICATION_FAILED' }; }
        lock.close(); return result;
    }
    function find(state, id) { for (let job in state.jobs) if (job.id == id) return job; return null; }
    function expired(job, now) { return now < job.created_ms || now > job.expires_ms; }
    function enqueue() {
        let config = settings(), approved = sink(config);
        if (!approved.ok) return { ok: false, reason: approved.reason };
        let published = read_json(root + '/notification-jobs.json', 32768), sampled = clock();
        if (type(published?.jobs) == 'array' && length(published.jobs) <= 16) {
            let current = find(published, published.active || published.recent);
            if (current && !expired(current, sampled) && current.config_revision == config.revision && current.sink_ref == approved.ref) {
                if (current.state == 'running' && sampled - current.started_ms > 6000) {
                    current.state = 'unknown'; current.delivery_state = 'unknown'; current.error = 'DELIVERY_UNCONFIRMED';
                }
                if (current.state == 'queued' || current.state == 'running' || sampled - current.created_ms < 30000)
                    return { ok: true, job: current, coalesced: true };
            }
        }
        return transact((state, now) => {
            let recent = find(state, state.active || state.recent);
            if (recent && !expired(recent, now)) {
                if (recent.config_revision != config.revision || recent.sink_ref != approved.ref) {
                    if (recent.state == 'running' && now - recent.started_ms <= 6000)
                        return { ok: false, reason: 'NOTIFICATION_BUSY' };
                    if (recent.state == 'queued') {
                        recent.state = 'failed'; recent.delivery_state = 'not_submitted'; recent.error = 'CONFIG_CHANGED';
                    }
                    else if (recent.state == 'running') {
                        recent.state = 'unknown'; recent.delivery_state = 'unknown'; recent.error = 'DELIVERY_UNCONFIRMED';
                    }
                    state.active = null;
                }
                else {
                    if (recent.state == 'running' && now - recent.started_ms > 6000) {
                        recent.state = 'unknown'; recent.delivery_state = 'unknown'; recent.error = 'DELIVERY_UNCONFIRMED';
                        state.active = null; state.recent = recent.id;
                    }
                    if (recent.state == 'queued' || recent.state == 'running' || now - recent.created_ms < 30000)
                        return { ok: true, job: recent, coalesced: true, dirty: true };
                }
            }
            let id = opaque_id();
            if (!id || find(state, id)) return { ok: false, reason: 'ID_UNAVAILABLE' };
            while (length(state.jobs) >= 16) shift(state.jobs);
            let job = { id, namespace: 'notification', scope: 'notification_test', state: 'queued',
                delivery_state: 'not_submitted', receipt_verified: false, config_revision: config.revision,
                sink_ref: approved.ref, created_ms: now, expires_ms: now + 600000, started_ms: null, error: null };
            push(state.jobs, job); state.active = id;
            return { ok: true, job, coalesced: false, dirty: true };
        });
    }
    function get(id) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/)) return { ok: false, reason: 'JOB_INVALID' };
        let state = read_json(root + '/notification-jobs.json', 32768);
        if (type(state?.jobs) != 'array' || length(state.jobs) > 16) return { ok: false, reason: 'JOB_UNKNOWN' };
        let job = find(state, id), now = clock();
        if (!job) return { ok: false, reason: 'JOB_UNKNOWN' };
        if (expired(job, now)) return { ok: false, reason: 'JOB_EXPIRED' };
        if (job.state == 'running' && now - job.started_ms > 6000) {
            job.state = 'unknown'; job.delivery_state = 'unknown'; job.error = 'DELIVERY_UNCONFIRMED';
        }
        return { ok: true, job };
    }
    function pending() {
        let state = read_json(root + '/notification-jobs.json', 32768);
        if (type(state?.jobs) != 'array' || length(state.jobs) > 16) return false;
        let job = find(state, state.active);
        return job?.state == 'queued' && !expired(job, clock());
    }
    function launch_failed() {
        return transact((state, now) => {
            let job = find(state, state.active);
            if (!job || job.state != 'queued') return { ok: false, reason: 'NO_PENDING_NOTIFICATION' };
            job.state = 'failed'; job.delivery_state = 'not_submitted'; job.error = 'WORKER_START_FAILED';
            job.finished_ms = now; state.active = null; state.recent = job.id;
            return { ok: true, dirty: true };
        });
    }
    function run_pending() {
        if (!private_dir(root)) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        let lease = open(root + '/notification-send.lock', 'a', 0600);
        if (!lease || !lease.lock('xn')) { if (lease) lease.close(); return { ok: false, reason: 'NOTIFICATION_BUSY' }; }
        let claimed = transact((state, now) => {
            let job = find(state, state.active);
            if (!job || job.state != 'queued' || expired(job, now)) return { ok: false, reason: 'NO_PENDING_NOTIFICATION' };
            job.state = 'running'; job.started_ms = now; job.delivery_state = 'submitted';
            return { ok: true, job, dirty: true };
        });
        if (!claimed.ok) { lease.close(); return claimed; }
        let job = claimed.job, config = settings(), approved = sink(config), delivery;
        let staging = root + '/notification-transport.new';
        try {
            if (!approved.ok || config.revision != job.config_revision || approved.ref != job.sink_ref)
                delivery = { state: 'failed', delivery_state: 'not_submitted', error: 'CONFIG_CHANGED' };
            else {
                let stale = lstat(staging);
                if (stale && (stale.type != 'file' || stale.uid != 0 || stale.mode != 0600 || !unlink(staging)))
                    delivery = { state: 'failed', delivery_state: 'not_submitted', error: 'STORAGE_UNAVAILABLE' };
                let file = delivery ? null : open(staging, 'wx', 0600);
                if (!delivery && !file) delivery = { state: 'failed', delivery_state: 'not_submitted', error: 'STORAGE_UNAVAILABLE' };
                if (file) {
                    let sink = approved.data;
                    let transport = 'url = "https://' + sink.host + ':' + sink.port + '/message"\n' +
                        'header = "X-Gotify-Key: ' + sink.token + '"\n' +
                        'header = "Content-Type: application/json"\n';
                    let written = file.write(transport); file.close();
                    let result = written == length(transport) ? run_command(['/usr/bin/curl', '--config', staging,
                        '--proto', '=https', '--noproxy', '*', '--max-redirs', '0', '--max-time', '4',
                        '--connect-timeout', '2', '--silent', '--output', '/dev/null', '--write-out', '%{http_code}',
                        '--resolve', sink.host + ':' + sink.port + ':' + sink.address,
                        '--request', 'POST', '--data-binary', '{"title":"NetBird health diagnostic test","message":"Explicit notification delivery test.","priority":5}'], 5000) : null;
                    let status = result?.ok && match(result.stdout, /^[0-9]{3}$/) ? int(result.stdout) : null;
                    delivery = status >= 200 && status < 300 ? { state: 'done', delivery_state: 'accepted', http_status: status, error: null } :
                        status != null ? { state: 'failed', delivery_state: 'rejected', http_status: status, error: 'HTTP_REJECTED' } :
                        { state: 'unknown', delivery_state: 'unknown', http_status: null, error: 'DELIVERY_UNCONFIRMED' };
                    delivery.transport_reason = result?.reason || null;
                    delivery.exit_code = result?.exit_code ?? null;
                    delivery.output_bytes = result?.output_bytes ?? 0;
                    delivery.duration_ms = result?.duration_ms ?? 0;
                }
            }
        }
        catch (e) { delivery = { state: 'unknown', delivery_state: 'unknown', error: 'DELIVERY_UNCONFIRMED' }; }
        unlink(staging);
        let finished = transact((state, now) => {
            let current = find(state, job.id);
            if (!current || state.active != job.id || current.state != 'running') return { ok: false, reason: 'JOB_NOT_RUNNING' };
            for (let key, value in delivery) current[key] = value;
            current.finished_ms = now; state.active = null; state.recent = job.id;
            return { ok: true, job: current, dirty: true };
        });
        lease.close(); return finished;
    }
    return { enqueue, get, run_pending, pending, launch_failed };
}
let notification = create_notifications('/tmp/netbird-health'), worker = null, dispatch;
function worker_done() {
    worker = null;
    // A new revision may have queued work after the previous terminal publish
    // but before this exit callback. Only queued work is dispatchable: an
    // indeterminate submitted job is never replayed.
    dispatch();
}
dispatch = function() {
    if (worker || !notification.pending()) return true;
    try {
        uloop.init();
        worker = uloop.process('/usr/bin/ucode', ['/usr/share/netbird/health/notify-worker.uc'], null, worker_done);
    }
    catch (e) { worker = null; }
    if (!worker) notification.launch_failed();
    return worker != null;
};
function test_notification() {
    let result = notification.enqueue();
    if (!result.ok || result.job.state != 'queued') return result;
    return dispatch() ? result : { ok: false, reason: 'WORKER_START_FAILED' };
}
function get_notification_job(id) { return notification.get(id); }
function run_pending() { return notification.run_pending(); }
export { create_notifications, test_notification, get_notification_job, run_pending };

// SPDX-License-Identifier: Apache-2.0
// Shared by lifecycle, update, settings and health recovery workers. The legacy
// directory remains observable by existing maintenance guards; ownership itself
// is a kernel lease plus a finite orphan fence, not a reusable PID alone.
import { open, lstat, readfile, rename, unlink, rmdir, lsdir, chmod } from 'fs';
import { private_dir, read_json, atomic_json } from '../../../netbird/health/storage.uc';
import { opaque_id } from '../../../netbird/health/jobs.uc';
import { monotonic_ms } from '../../../netbird/health/runner.uc';
function process_identity(path) {
    let text = readfile(path) || '', m = match(text, /^([0-9]+) \(.*\) (.+)$/s);
    let fields = m ? split(trim(m[2]), ' ') : [];
    if (!m || length(fields) < 20 || !match(fields[19], /^[0-9]+$/)) return null;
    return { pid: m[1], started: fields[19], state: fields[0] };
}
function create(root, clock) {
    root ??= '';
    clock ??= monotonic_ms;
    const boot = trim(readfile(root + '/proc/sys/kernel/random/boot_id') || '');
    const dir = root + '/tmp/netbird-actions';
    const marker = root + '/tmp/nb-binop.lock';
    const stage = dir + '/marker';
    let lease = null, identity = null;
    function marker_state() {
        let st = lstat(marker);
        if (!st) return { present: false, busy: false };
        if (st.type != 'directory' || st.uid != 0 || (st.mode & 0022))
            return { present: true, busy: true, reason: 'ACTION_OWNER_CONFLICT' };
        let owner_stat = lstat(marker + '/owner');
        let owner = owner_stat?.type == 'file' && owner_stat.uid == 0 && owner_stat.size <= 32 ?
            trim(readfile(marker + '/owner') || '') : '';
        if (!match(owner, /^[1-9][0-9]{0,9}$/))
            return { present: true, busy: true, reason: 'ACTION_OWNER_UNKNOWN' };
        let running = process_identity(root + '/proc/' + owner + '/stat');
        let saved = read_json(marker + '/identity.json', 2048);
        // Old markers have only owner. Never remove an old marker whose owner
        // might still run. New markers bind PID start time and boot, and fence
        // orphan commands for the existing updater's 600s maximum deadline.
        // Callers must independently bound/drain destructive command groups;
        // releasing a kernel descriptor alone does not prove children stopped.
        let busy = !!running && running.state != 'Z', reason = busy ? 'ACTION_BUSY' : null;
        if (lstat(marker + '/identity.json')) {
            if (saved?.schema_version != 1 || saved.pid != owner ||
                type(saved.started) != 'string' || !match(saved.started, /^[0-9]+$/) ||
                type(saved.boot_id) != 'string' || !match(saved.boot_id, /^[0-9a-f-]{36}$/) ||
                type(saved.id) != 'string' || !match(saved.id, /^[0-9a-f]{32}$/))
                return { present: true, busy: true, reason: 'ACTION_OWNER_CONFLICT' };
            busy = saved.boot_id == boot && !!running && running.state != 'Z' && running.started == saved.started;
        }
        if (!busy && (!saved || saved.boot_id == boot)) {
            let fence_id = saved?.id || 'legacy-' + owner;
            let fence = read_json(marker + '/orphan.json', 2048), now = clock();
            if (!lstat(marker + '/orphan.json'))
                return { present: true, busy: true, reason: 'ACTION_DRAIN_PENDING', needs_fence: true, fence_id };
            if (fence?.id != fence_id || fence.boot_id != boot || type(fence.detected_ms) != 'int' || fence.detected_ms < 0)
                return { present: true, busy: true, reason: 'ACTION_OWNER_CONFLICT' };
            if (now < fence.detected_ms || now - fence.detected_ms < 600000) {
                busy = true; reason = 'ACTION_DRAIN_PENDING';
            }
        }
        return { present: true, busy, reason: busy ? reason || 'ACTION_BUSY' : null };
    }
    function remove_marker(path) {
        let st = lstat(path);
        if (!st) return true;
        if (st.type != 'directory' || st.uid != 0 || (st.mode & 0022)) return false;
        let names = lsdir(path) || [];
        for (let name in names) {
            let item = lstat(path + '/' + name);
            if (index(['owner', 'identity.json', 'identity.json.new', 'orphan.json', 'orphan.json.new'], name) < 0 ||
                item?.type != 'file' || item.uid != 0 || (item.mode & 0022)) return false;
        }
        for (let name in names) if (!unlink(path + '/' + name)) return false;
        return !!rmdir(path);
    }
    function release() {
        if (!lease) return false;
        let saved = read_json(marker + '/identity.json', 2048);
        let owned = identity && saved?.id == identity.id && saved.pid == identity.pid &&
            saved.started == identity.started;
        let removed = owned && remove_marker(marker);
        identity = null;
        lease.close(); lease = null;
        return !!removed;
    }
    function acquire(owner) {
        if (lease) return { ok: false, reason: 'ACTION_BUSY' };
        if (type(owner) != 'string' || !match(owner, /^[a-z][a-z0-9_-]{0,47}$/))
            return { ok: false, reason: 'ACTION_OWNER_INVALID' };
        if (!private_dir(dir)) return { ok: false, reason: 'ACTION_STORAGE_UNAVAILABLE' };
        let path = dir + '/owner.lock', st = lstat(path);
        if (st && (st.type != 'file' || st.uid != 0 || st.mode != 0600))
            return { ok: false, reason: 'ACTION_STORAGE_UNAVAILABLE' };
        // fclose after owner death must release exclusion even if a bounded
        // command still runs. Native fs accepts e (FD_CLOEXEC); plain a leaks.
        let candidate = open(path, 'ae', 0600);
        if (!candidate || !candidate.lock('xn')) {
            candidate?.close(); return { ok: false, reason: 'ACTION_BUSY' };
        }
        let result = { ok: false, reason: 'ACTION_STORAGE_UNAVAILABLE' };
        try {
            let status = marker_state();
            if (status.needs_fence) {
                let safe = true;
                for (let name in lsdir(marker) || []) {
                    let item = lstat(marker + '/' + name);
                    if (index(['owner', 'identity.json', 'identity.json.new', 'orphan.json.new'], name) < 0 ||
                        item?.type != 'file' || item.uid != 0 || (item.mode & 0022)) safe = false;
                }
                if (!safe) status.reason = 'ACTION_OWNER_CONFLICT';
                // Legacy mkdir markers are normally 0755. Restrict only a
                // recognized app-owned marker, never unknown external data.
                else if (!chmod(marker, 0700) || !atomic_json(marker, 'orphan.json',
                    { id: status.fence_id, boot_id: boot, detected_ms: clock() }, 2048))
                    status.reason = 'ACTION_STORAGE_UNAVAILABLE';
            }
            if (status.busy) result = { ok: false, reason: status.reason };
            else {
                let proc = process_identity(root + '/proc/self/stat'), id = opaque_id();
                if (proc && id && match(boot, /^[0-9a-f-]{36}$/) && (!status.present || remove_marker(marker)) &&
                    remove_marker(stage) && private_dir(stage)) {
                    let saved = { schema_version: 1, id, owner, pid: proc.pid, started: proc.started, boot_id: boot };
                    // Publish a complete directory. A killed new owner cannot
                    // leave an ownerless marker requiring a clock-based guess.
                    let owner_file = open(stage + '/owner', 'wx', 0600);
                    let owner_written = owner_file && owner_file.write(proc.pid + '\n') == length(proc.pid) + 1;
                    owner_file?.close();
                    if (owner_written &&
                        atomic_json(stage, 'identity.json', saved, 2048) && !lstat(marker) && rename(stage, marker)) {
                        lease = candidate; identity = saved;
                        return { ok: true, owner, id };
                    }
                }
            }
        }
        catch (e) { /* No raw filesystem exception reaches RPC or logs. */ }
        candidate.close();
        return result;
    }
    function available() {
        let attempt = acquire('maintenance-probe');
        return attempt.ok ? release() : false;
    }
    return { acquire, release, marker_state, available };
}
return { create };

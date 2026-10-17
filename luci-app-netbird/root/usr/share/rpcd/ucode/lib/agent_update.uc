// SPDX-License-Identifier: Apache-2.0
// One install state machine for manual and unattended updates. Download validation
// and the shared binary-operation lock belong to the caller. Never truncate a live
// binary. The synced journal precedes every destructive action.
import { readfile, writefile, rename, stat, lstat, chmod, access, lsdir } from 'fs';

function create(ctx) {
    const dir = ctx.state_dir || '/etc/netbird-update';
    const journal = dir + '/transaction.json';
    const cancel_file = dir + '/cancel';
    const q = ctx.quote;
    const run = ctx.run;
    const now = ctx.now;
    const boot_id = trim(readfile('/proc/sys/kernel/random/boot_id') || '');
    function uptime() { return ctx.uptime ? ctx.uptime() : int(split(readfile('/proc/uptime') || '0', ' ')[0]); }
    function read_json(path) {
        try { return json(readfile(path) || 'null'); } catch (e) { return null; }
    }
    function owner(pid) {
        let text = readfile('/proc/' + pid + '/stat') || '';
        let m = match(text, /^[0-9]+ \(.*\) (.+)$/);
        let fields = m ? split(m[1], ' ') : [];
        return { pid: '' + pid, start: fields[19] || '', state: fields[0] || '', group: fields[2] || '', session: fields[3] || '', boot: boot_id };
    }
    function alive(o) {
        if (!o || !match(o.pid || '', /^[1-9][0-9]*$/) || !o.start || !o.boot) return false;
        let actual = owner(o.pid);
        return actual.state != 'Z' && actual.start == o.start && actual.boot == o.boot;
    }
    function group_members(o) {
        let members = [];
        for (let pid in (lsdir('/proc') || [])) {
            if (!match(pid, /^[1-9][0-9]*$/)) continue;
            let p = owner(pid);
            if (p.group == o.pid && p.session == o.pid && p.start && p.state != 'Z') push(members, p);
        }
        return members;
    }
    function stop_group(o) {
        if (!o || o.boot != boot_id) return true;
        let current = owner(o.pid);
        // A reused leader PID means the previous group no longer exists. Linux
        // retains the group/session ID while any original member remains alive.
        if (current.start && current.start != o.start) return true;
        if (o.group != o.pid || o.session != o.pid || o.pid == '' + ctx.pid()) return false;
        if (!length(group_members(o))) return true;
        run('kill -9 -' + o.pid);
        for (let n = 0; n < 5; n++) {
            if (!length(group_members(o))) return true;
            ctx.sleep(1);
        }
        return !length(group_members(o));
    }
    function persistent(path) {
        let r = run('readlink -f ' + q(path));
        let real = trim(r.out);
        if (r.code != 0 || !real || match(real, /^\/(tmp|run|dev|proc|sys)(\/|$)/)) return false;
        // OpenWrt need not ship the stat applet. The kernel mount table is the
        // authority; the longest mount-point prefix identifies a bind/submount.
        let mount_path = '', fs_type = '';
        for (let line in split(readfile('/proc/mounts') || '', '\n')) {
            let parts = split(line, ' ');
            let at = parts[1] || '';
            if (at && (real == at || at == '/' || index(real, at + '/') == 0) && length(at) > length(mount_path)) {
                mount_path = at; fs_type = parts[2] || '';
            }
        }
        return !!fs_type && !match(fs_type, /^(tmpfs|ramfs|rootfs|proc|sysfs|devpts|squashfs)$/);
    }
    function storage_device(path) {
        let real = trim(run('readlink -f ' + q(path)).out);
        let best = '', upper = '';
        for (let line in split(readfile('/proc/mounts') || '', '\n')) {
            let p = split(line, ' '), at = p[1] || '';
            if (at && (real == at || at == '/' || index(real, at + '/') == 0) && length(at) > length(best)) {
                best = at; upper = '';
                if (p[2] == 'overlay') {
                    let m = match(p[3] || '', /upperdir=([^,]+)/);
                    if (m) upper = m[1];
                }
            }
        }
        // OpenWrt /etc and /usr use overlayfs while /overlay exposes the same
        // physical storage directly. Sum their reservations, not separate budgets.
        let backing = upper ? stat(upper) : null;
        return '' + (backing ? backing.dev : stat(path).dev);
    }
    function ready_dir() {
        let s = lstat(dir);
        if (s && (s.type != 'directory' || s.uid != 0 || (s.mode & 18))) return false;
        if (run('umask 077; mkdir -p ' + q(dir) + ' && chmod 0700 ' + q(dir)).code != 0) return false;
        return persistent(dir);
    }
    function save(s) {
        s.updated_at = now();
        let text = sprintf('%J\n', s);
        if (writefile(journal + '.new', text) != length(text) || !chmod(journal + '.new', 384))
            die('Could not persist the update journal.');
        if (run('sync').code != 0 || !rename(journal + '.new', journal) || run('sync').code != 0)
            die('Could not sync the update journal.');
    }
    function pending(s) {
        return s && s.phase != 'committed' && s.phase != 'rolled_back' && s.phase != 'aborted' && s.phase != 'idle';
    }
    function load() {
        let s = read_json(journal);
        if (!s && access(journal, 'f'))
            return { phase: 'rollback_failed', paused: true, message: 'Unreadable transaction journal; preserve files and repair manually.' };
        return s;
    }
    function public_status() {
        let s = load() || {};
        return { phase: s.phase || 'idle', result: s.result || '', message: s.message || '',
            from_version: s.from_version || '', to_version: s.to_version || '',
            paused: !!s.paused, blocked_version: s.blocked_version || '', blocked_versions: s.blocked_versions || [],
            started_at: s.started_at || 0, deadline: s.deadline || 0,
            worker_pid: s.owner ? s.owner.pid || '' : '', transaction_id: s.transaction_id || '',
            updated_at: s.updated_at || 0, active: !!s.phase && !!pending(s), cancel_requested: !!access(cancel_file, 'f') };
    }
    function fail(message, code) { return { ok: false, code: code || 'install_failed', message: message }; }
    function canceled() { return access(cancel_file, 'f') || (ctx.canceled && ctx.canceled()); }
    function sha(path) {
        let r = run('sha256sum ' + q(path));
        let m = r.code == 0 ? match(r.out, /^([0-9a-f]{64})\s/) : null;
        return m ? m[1] : '';
    }
    function free_kb(path) {
        let r = run('df -k ' + q(path));
        let lines = split(trim(r.out), '\n');
        let fields = split(trim(lines[length(lines) - 1] || ''), /\s+/);
        let v = fields[length(fields) - 3];
        return r.code == 0 && match(v || '', /^[0-9]+$/) ? int(v) : -1;
    }
    function used_kb(path) {
        let r = run('du -sk ' + q(path));
        let m = r.code == 0 ? match(r.out, /^([0-9]+)/) : null;
        return m ? int(m[1]) : -1;
    }
    function healthy(sample, baseline, version) {
        if (!sample || !sample.ok || !sample.pid || sample.version != version ||
            !sample.management_connected || !sample.signal_connected) return false;
        for (let key in ['public_key', 'mesh_ip', 'management_url', 'dns_fingerprint'])
            if (!sample[key] || !baseline || sample[key] != baseline[key]) return false;
        return true;
    }
    function stop() {
        let pid = ctx.daemon_pid ? ctx.daemon_pid() : '';
        let original = pid ? owner(pid) : null;
        run('/etc/init.d/netbird stop 2>&1');
        for (let n = 0; n < 15; n++) {
            if ((ctx.stopped ? ctx.stopped() : !ctx.running()) && !alive(original)) return true;
            ctx.sleep(1);
        }
        return (ctx.stopped ? ctx.stopped() : !ctx.running()) && !alive(original);
    }
    function invariants_changed(sample, baseline) {
        if (!sample || !sample.ok) return false;
        for (let key in ['public_key', 'mesh_ip', 'management_url', 'dns_fingerprint'])
            if (sample[key] && sample[key] != baseline[key]) return true;
        return false;
    }
    function expired(s) {
        return owner(ctx.pid()).boot != s.owner.boot || uptime() >= s.stop_uptime + 600;
    }
    function observe(s, version, rollback) {
        let connect_until = uptime() + 120;
        let stable_since = null;
        let stable_pid = '';
        while (uptime() <= connect_until || stable_since != null) {
            let sampled_at = uptime();
            if (!rollback && (canceled() || expired(s))) return false;
            let sample = ctx.sample();
            if (sample && sample.pid) {
                if (stable_pid && sample.pid != stable_pid) return false;
                stable_pid = sample.pid;
            }
            if (invariants_changed(sample, s.baseline)) return false;
            let good = healthy(sample, s.baseline, version) && (!s.probe_url || ctx.probe(s.probe_url));
            if (good) {
                if (stable_since == null) stable_since = uptime();
                // Recovery proves sustained health too; no file-only rollback success.
                if (uptime() - stable_since >= (rollback ? 20 : 300)) return true;
            } else if (stable_since != null) {
                return false;
            }
            if (stable_since == null && uptime() >= connect_until) return false;
            if (rollback && uptime() >= connect_until) return false;
            let wait = 10 - (uptime() - sampled_at);
            if (wait > 0) ctx.sleep(wait);
        }
        return false;
    }
    function cleanup(s) {
        // These exact private paths are ours, never a user supplied recursive path.
        run('rm -f ' + q(dir + '/profile.tar') + ' ' + q(dir + '/profile.tar.new') +
            ' ' + q(dir + '/old-binary') + ' ' + q(dir + '/old-park') + ' ' +
            q(s.staged || dir + '/unused') + ' ' + q(cancel_file) + ' ' + q((s.park_path || dir + '/unused') + '.nb-update-new'));
    }
    function restore(s, boot) {
        s.phase = 'rolling_back';
        s.result = 'failed';
        if (s.activation_requested) {
            s.blocked_version = s.to_version;
            s.blocked_versions = s.blocked_versions || [];
            if (index(s.blocked_versions, s.to_version) < 0) push(s.blocked_versions, s.to_version);
        }
        save(s);
        if (s.activation_requested && s.stop_requested && !stop()) die('Could not stop the new daemon; old files were not overwritten.');
        if (s.activation_requested && s.backup_ready) {
            if (!s.old_sha || sha(dir + '/old-binary') != s.old_sha) die('Persistent binary backup failed verification.');
            let r = s.old_link
                ? run('ln -sf ' + q(s.old_link) + ' ' + q(s.staged))
                : run('cp -p ' + q(dir + '/old-binary') + ' ' + q(s.staged) + ' && chmod 0755 ' + q(s.staged) + ' && sync');
            if (r.code != 0 || sha(s.staged) != s.old_sha || ctx.version(s.staged) != s.from_version)
                die('Could not prepare the old binary for atomic restore.');
            if (run('mv -f ' + q(s.staged) + ' ' + q(s.target) + ' && sync').code != 0)
                die('Could not atomically restore the old binary.');
        } else if (!s.had_target && s.activation_requested) {
            if (run('rm -f ' + q(s.target) + ' && sync').code != 0) die('Could not remove the newly installed binary.');
        }
        if (s.activation_requested && s.source_to && !ctx.set_source(s.source_from)) die('Could not restore the original binary source configuration.');
        if (s.park_path && s.park_requested) {
            if (s.park_had_target) {
                if (!s.park_backup_ready || sha(dir + '/old-park') != s.park_old_sha ||
                    run('cp -p ' + q(dir + '/old-park') + ' ' + q(s.park_path + '.nb-update-new') +
                        ' && chmod 0755 ' + q(s.park_path + '.nb-update-new') + ' && sync && mv -f ' +
                        q(s.park_path + '.nb-update-new') + ' ' + q(s.park_path) + ' && sync').code != 0)
                    die('Could not restore the previous parked release.');
            } else if (run('rm -f ' + q(s.park_path) + ' && sync').code != 0)
                die('Could not remove the transaction-created parked release.');
        }
        if (s.activation_requested && s.snapshot_ready) {
            // A 0600 tar preserves original live file modes without exposing any
            // private-key backup, even when the original profile had loose modes.
            if (!s.snapshot_sha || sha(dir + '/profile.tar') != s.snapshot_sha)
                die('The persistent identity snapshot failed verification; original files were not removed.');
            if (run('find ' + q(s.real_profile) + ' -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -xf ' +
                q(dir + '/profile.tar') + ' -C ' + q(s.real_profile) + ' && sync').code != 0)
                die('Old binary restored, but restoring the identity snapshot failed.');
        }
        if (boot && s.was_running && s.stop_requested) {
            s.phase = 'restored_waiting_health';
            s.message = 'Old files restored at boot; awaiting normal service startup and health verification.';
            s.owner = null;
            save(s);
            return { ok: true, data: public_status() };
        }
        if (s.was_running && s.stop_requested) {
            if (run('/etc/init.d/netbird start 2>&1').code != 0 ||
                (s.baseline && !observe(s, s.from_version, true)))
                die('Old binary restored; connection has not recovered. Automatic updates paused.');
        }
        s.phase = s.activation_requested ? 'rolled_back' : 'aborted';
        s.result = s.activation_requested ? (s.baseline ? 'rolled_back' : 'restored_unverified') : 'failed';
        s.message = (s.failure || 'Interrupted update') + (s.activation_requested ?
            (s.baseline ? '; previous version restored and health verified.' : '; previous binary restored; pre-upgrade connectivity was unknown and is not claimed as recovered.') : '; original version preserved.');
        s.paused = false;
        save(s);
        cleanup(s);
        return fail(s.message);
    }
    function rollback(s, reason, boot) {
        s.failure = reason;
        try { return restore(s, boot); }
        catch (e) {
            s.phase = 'rollback_failed';
            s.result = 'rollback_failed';
            s.paused = true;
            if (s.activation_requested) s.blocked_version = s.to_version;
            s.message = `${e}`;
            try { save(s); } catch (ignored) {}
            return fail(s.message);
        }
    }
    function install(o) {
        let previous = load();
        if (pending(previous)) return fail('A transaction needs recovery before another binary operation.');
        if (!ready_dir()) return fail('A root-owned persistent update directory is required.');
        if (!match(o.target || '', /^\/[A-Za-z0-9_./-]+$/) || index(o.target, '/..') >= 0)
            return fail('Unsafe binary target path.');
        let st = lstat(o.target);
        if (st && st.type != 'file' && !(o.source && st.type == 'link')) return fail('Refusing to replace a non-regular binary target.');
        let target_stat = stat(o.target);
        let old_link = st && st.type == 'link' ? trim(run('readlink ' + q(o.target)).out) : '';
        if (old_link && (!match(old_link, /^\/[A-Za-z0-9_./-]+$/) || !target_stat)) return fail('The original binary symlink cannot be safely preserved.');
        let worker = owner(ctx.pid());
        if ((st || o.was_running) && (worker.group != worker.pid || worker.session != worker.pid))
            return fail('Use start_binary_update/start_binary_source_switch or an isolated setsid worker for existing binaries.');
        let candidate = stat(o.candidate);
        if (!candidate || candidate.size < 1 || ctx.version(o.candidate) != o.version)
            return fail('Candidate version verification failed.');
        let baseline = o.baseline;
        if (o.strict && (!o.active || !o.was_running || !baseline || !healthy(baseline, baseline, baseline.version) || !o.probe_url || !ctx.probe(o.probe_url)))
            return fail('A healthy connected baseline and reachable Mesh service probe are required.');
        let profile = '';
        if (o.active && o.was_running) {
            if (!o.profile_dir) return fail('Cannot locate the running daemon identity directory; installation refused.');
            let r = run('readlink -f ' + q(o.profile_dir));
            profile = trim(r.out);
            let p = stat(profile);
            if (r.code != 0 || !p || p.type != 'directory' || p.uid != 0 || (p.mode & 18) || !persistent(profile) ||
                profile == '/' || index(dir + '/', profile + '/') == 0 || index(profile + '/', dir + '/') == 0)
                return fail('The actual identity/profile directory must be persistent, root owned, and separate from update storage.');
            let links = run('find ' + q(profile) + ' -type l -print');
            if (links.code != 0 || length(trim(links.out))) return fail('Identity snapshots cannot safely include internal symlinks; resolve the profile layout before updating.');
        }
        let old_kb = target_stat ? int((target_stat.size + 1023) / 1024) : 0;
        let new_kb = int((candidate.size + 1023) / 1024);
        let profile_kb = profile ? used_kb(profile) : 0;
        if (profile_kb < 0) return fail('Could not measure the profile snapshot.');
        let parent = replace(o.target, /\/[^/]+$/, '');
        if (run('mkdir -p ' + q(parent)).code != 0 || !persistent(parent)) return fail('The binary destination must be persistent.');
        let park_stat = o.park_path ? stat(o.park_path) : null;
        let park_kb = park_stat ? int((park_stat.size + 1023) / 1024) : 0;
        let park_parent = o.park_path ? replace(o.park_path, /\/[^/]+$/, '') : dir;
        if (o.park_path && (run('mkdir -p ' + q(park_parent)).code != 0 || !persistent(park_parent)))
            return fail('The parked release destination must be persistent.');
        let needs = {};
        for (let item in [{path: dir, kb: old_kb + park_kb + profile_kb + 1024},
            {path: parent, kb: new_kb + old_kb + 1024},
            {path: profile || dir, kb: profile_kb + 1024},
            {path: park_parent, kb: o.park_path ? (old_kb > park_kb ? old_kb : park_kb) + 1024 : 0}]) {
            let device = storage_device(item.path);
            if (!needs[device]) needs[device] = { path: item.path, kb: 0 };
            needs[device].kb += item.kb;
        }
        for (let device, need in needs) {
            let free = free_kb(need.path);
            if (free < need.kb) return fail(sprintf('Reliable rollback requires %d KB free at %s; available %d KB. Nothing changed.', need.kb, need.path, free), 'insufficient_space');
        }
        let s = { phase: 'prepared', result: '', target: o.target, staged: o.target + '.nb-update-new',
            schema: 1, prepare_uptime: uptime(),
            transaction_id: trim(readfile('/proc/sys/kernel/random/uuid') || ''),
            from_version: st ? ctx.version(o.target) : '', to_version: o.version, had_target: !!st,
            active: !!o.active, was_running: !!o.was_running, baseline: baseline,
            real_profile: profile, probe_url: o.probe_url || '', started_at: now(),
            owner: owner(ctx.pid()), old_sha: '', backup_ready: false, snapshot_ready: false,
            stop_requested: false, activation_requested: false, paused: false,
            old_link: old_link, source_to: o.source || '', source_from: o.source ? ctx.source() : '',
            park_path: o.park_path || '', park_had_target: !!park_stat, park_requested: false, park_backup_ready: false,
            blocked_version: previous ? previous.blocked_version || '' : '' };
        if (!match(s.transaction_id, /^[0-9a-f-]{36}$/)) return fail('Could not allocate a unique transaction identity.');
        s.blocked_versions = previous ? previous.blocked_versions || [] : [];
        try {
            save(s);
            if (st) {
                s.old_sha = sha(o.target);
                if (!s.old_sha || run('cp -p ' + q(o.target) + ' ' + q(dir + '/old-binary') + ' && chmod 0600 ' + q(dir + '/old-binary') + ' && sync').code != 0 ||
                    sha(dir + '/old-binary') != s.old_sha) die('Could not create a complete persistent rollback binary.');
                s.backup_ready = true;
                save(s);
            }
            if (o.park_path) {
                if (park_stat) {
                    s.park_old_sha = sha(o.park_path);
                    if (!s.park_old_sha || run('cp -p ' + q(o.park_path) + ' ' + q(dir + '/old-park') + ' && chmod 0600 ' + q(dir + '/old-park') + ' && sync').code != 0 || sha(dir + '/old-park') != s.park_old_sha)
                        die('Could not preserve the previous parked release.');
                    s.park_backup_ready = true; save(s);
                }
                if (run('cp -p ' + q(o.target) + ' ' + q(o.park_path + '.nb-update-new') + ' && chmod 0755 ' + q(o.park_path + '.nb-update-new') + ' && sync').code != 0 || sha(o.park_path + '.nb-update-new') != s.old_sha)
                    die('Could not prepare the official release parking file.');
            }
            let prepared = o.target_link
                ? run('ln -sf ' + q(o.target_link) + ' ' + q(s.staged))
                : run('cp ' + q(o.candidate) + ' ' + q(s.staged) + ' && chmod 0755 ' + q(s.staged) + ' && sync');
            if (prepared.code != 0 || sha(s.staged) != sha(o.candidate) || ctx.version(s.staged) != o.version)
                die('Could not prepare and verify the same-filesystem candidate.');
            if (canceled()) die('Update canceled before service stop.');
            if (o.active && o.was_running) {
                // Recheck immediately before stop, not merely before the download.
                if (o.strict && (!healthy(ctx.sample(), baseline, baseline.version) || !ctx.probe(o.probe_url)))
                    die('The baseline became unhealthy while preparing the update.');
                s.phase = 'stopping'; s.stop_requested = true;
                s.stop_uptime = uptime(); s.deadline = now() + 600;
                save(s);
                if (ctx.arm_deadline && !ctx.arm_deadline()) die('Could not arm the independent activation deadline.');
                if (!stop()) die('The daemon did not stop; candidate not activated.');
                if (profile) {
                    s.phase = 'snapshotting'; save(s);
                    if (run('tar -cf ' + q(dir + '/profile.tar.new') + ' -C ' + q(profile) +
                        ' . && chmod 0600 ' + q(dir + '/profile.tar.new') + ' && tar -tf ' + q(dir + '/profile.tar.new') +
                        ' >/dev/null && sync && mv -f ' + q(dir + '/profile.tar.new') + ' ' + q(dir + '/profile.tar') + ' && sync').code != 0)
                        die('Could not take a consistent identity snapshot after stopping the daemon.');
                    s.snapshot_sha = sha(dir + '/profile.tar');
                    if (!s.snapshot_sha) die('Could not verify the identity snapshot.');
                    s.snapshot_ready = true; save(s);
                }
            }
            if (canceled()) die('Update canceled before activation.');
            s.phase = 'activating'; s.activation_requested = true; save(s);
            if (s.park_path) {
                s.park_requested = true; save(s);
                if (run('mv -f ' + q(s.park_path + '.nb-update-new') + ' ' + q(s.park_path) + ' && sync').code != 0)
                    die('Could not atomically park the official release.');
            }
            if (run('mv -f ' + q(s.staged) + ' ' + q(s.target) + ' && sync').code != 0 || ctx.version(s.target) != o.version)
                die('Atomic activation or installed version verification failed.');
            if (o.source && !ctx.set_source(o.source)) die('Could not save the new binary source.');
            if (s.stop_requested) {
                s.phase = 'trial'; save(s);
                if (run('/etc/init.d/netbird start 2>&1').code != 0) die('The new daemon could not start.');
                if (baseline && !observe(s, o.version, false)) die('The new version failed its health window or was canceled.');
                if (!baseline && !ctx.running()) die('The installed daemon is not running.');
            }
            s.phase = 'committed'; s.result = 'success'; s.message = 'Binary installed and required health checks passed.';
            s.paused = false; save(s);
            cleanup(s);
            if (o.remove_candidate_on_commit && o.candidate != o.target)
                run('rm -f ' + q(o.candidate));
            return { ok: true, data: { from: s.from_version, to: o.version, path: o.target } };
        } catch (e) { return rollback(s, `${e}`, false); }
    }
    function recover(o) {
        let s = load();
        if (!pending(s) || (s.phase == 'rollback_failed' && !(o && o.retry))) return { ok: !s || !s.paused, data: public_status() };
        if (s.schema != 1 || !match(s.target || '', /^\/[A-Za-z0-9_./-]+$/) || index(s.target, '/..') >= 0 || s.target == '/' ||
            s.staged != s.target + '.nb-update-new' || !s.owner && s.phase != 'restored_waiting_health' && s.phase != 'rollback_failed')
            return fail('Journal requires manual recovery.');
        if (s.snapshot_ready && (!s.real_profile || s.real_profile == '/' || !persistent(s.real_profile) ||
            index(dir + '/', s.real_profile + '/') == 0 || index(s.real_profile + '/', dir + '/') == 0))
            return fail('Unsafe identity recovery path; preserve the transaction for manual recovery.');
        let owner_alive = alive(s.owner);
        let retry_self = owner_alive && s.phase == 'rollback_failed' && s.owner.pid == '' + ctx.pid() && o && o.retry;
        if (owner_alive && !retry_self && s.phase != 'rollback_failed' &&
            ((!s.stop_requested && uptime() < s.prepare_uptime + 1800) || (s.stop_requested && !expired(s))))
            return { ok: true, data: public_status() };
        // Killing only the ucode leader is insufficient: an orphan cp/tar may
        // still be writing a staged file after SIGKILL/OOM. Drain its whole group.
        if (!retry_self && (s.had_target || s.was_running) && !stop_group(s.owner)) {
            s.phase = 'rollback_failed'; s.paused = true;
            s.message = 'Could not stop isolated transaction writers; preserve files and repair locally before recovery.';
            try { save(s); } catch (e) {}
            return fail(s.message);
        }
        let lock = dir + '/recovery.lock';
        let lock_owner = read_json(lock + '/owner');
        if (access(lock, 'f') && !alive(lock_owner)) {
            if (!stop_group(lock_owner)) return fail('An interrupted recovery still has live writer processes.');
            run('rm -rf ' + q(lock));
        }
        if (run('mkdir -m 0700 ' + q(lock)).code != 0) return fail('Recovery already in progress.');
        writefile(lock + '/owner', sprintf('%J', owner(ctx.pid())));
        let result;
        try { result = rollback(s, s.failure || 'Update interrupted before commit', !!(o && o.boot)); }
        catch (e) { result = fail(`${e}`); }
        run('rm -rf ' + q(lock));
        let after = load();
        if (after && (after.phase == 'aborted' || after.phase == 'rolled_back')) return { ok: true, data: public_status() };
        return result;
    }
    function record(result) {
        if (!ready_dir()) return fail('Cannot persist update result.');
        let s = load() || { phase: 'idle' };
        if (pending(s)) return fail('A transaction is still active.');
        for (let key in ['result', 'message']) if (result[key] != null) s[key] = result[key];
        save(s);
        return { ok: true, data: public_status() };
    }
    function wait_deadline() {
        let bound = load();
        if (!bound || !bound.transaction_id || !bound.stop_requested) return { ok: true };
        while (true) {
            let s = load();
            if (!pending(s) || s.transaction_id != bound.transaction_id || s.phase == 'rollback_failed') return { ok: true };
            let remaining = s.stop_uptime + 600 - uptime();
            if (remaining <= 0) return recover({});
            ctx.sleep(remaining < 5 ? remaining : 5);
        }
    }
    return { install: install, recover: recover, status: public_status,
        busy: function() { return !!pending(load()); }, persistent: persistent,
        wait_deadline: wait_deadline,
        canceled: canceled,
        clear_cancel: function() { return run('rm -f ' + q(cancel_file)).code == 0; },
        cancel: function() {
            if (!ready_dir()) return fail('Cannot persist cancellation.');
            if (writefile(cancel_file, '1') != 1) return fail('Could not request cancellation.');
            return { ok: true, data: public_status() };
        },
        reset_failure: function() {
            let s = load();
            if (pending(s)) return fail('Recover or repair the unresolved transaction before clearing failures.');
            if (access(dir + '/boot-held', 'f')) {
                if (run('/etc/init.d/netbird enable').code != 0) return fail('Could not re-enable the repaired NetBird boot service.');
                if (run('rm -f ' + q(dir + '/boot-held')).code != 0) return fail('Could not clear the boot recovery hold.');
            }
            if (s) { s.blocked_version = ''; s.blocked_versions = []; s.paused = false; save(s); }
            return { ok: true, data: public_status() };
        }, record: record };
}
return { create: create };

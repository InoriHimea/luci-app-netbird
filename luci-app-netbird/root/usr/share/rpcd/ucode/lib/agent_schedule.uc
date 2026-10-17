// SPDX-License-Identifier: Apache-2.0
import { readfile, writefile, rename, access, lsdir } from 'fs';
import * as uci from 'uci';

function create(ctx) {
    const dir = '/etc/netbird-update';
    const q = ctx.quote;
    const run = ctx.run;
    const engine = ctx.engine;
    const launch = '/tmp/nb-agent-launch.lock';
    function fail(message) { return { ok: false, code: 'invalid_input', message: message }; }
    function config() {
        let c = uci.cursor();
        function get(key, fallback) { let v = c.get('netbird_bin', 'auto_update', key); return v == null || v == '' ? fallback : v; }
        return { enabled: get('enabled', '0') == '1', time: get('time', '03:30'), timezone: get('timezone', 'UTC-8'),
            min_age_hours: int(get('min_age_hours', '48')), probe_url: get('probe_url', ''), profile_dir: get('profile_dir', '/var/lib/netbird') };
    }
    function timezone(cfg) {
        if (cfg.timezone != 'system') return cfg.timezone;
        let c = uci.cursor();
        return c.get_first('system', 'system', 'timezone') || 'UTC0';
    }
    function local_time(cfg) {
        let r = run('TZ=' + q(timezone(cfg)) + ' date "+%Y%m%d %H:%M %Y-%m-%d %z"');
        let m = match(trim(r.out), /^([0-9]{8}) ([0-9]{2}):([0-9]{2}) ([0-9-]+) ([+-][0-9]{4})$/);
        return r.code == 0 && m ? { day: m[1], minute: int(m[2]) * 60 + int(m[3]), date: m[4], offset: m[5] } : null;
    }
    function next_run(cfg) {
        let t = local_time(cfg);
        if (!cfg.enabled || !t) return '';
        let when = t.date;
        let scheduled = int(substr(cfg.time, 0, 2)) * 60 + int(substr(cfg.time, 3, 2));
        if (t.minute >= scheduled) {
            // Noon + 24h selects the next civil date even on DST transition days.
            let noon = run('TZ=' + q(timezone(cfg)) + ' date -d ' + q(t.date + ' 12:00:00') + ' +%s');
            if (noon.code != 0) return '';
            let tomorrow = run('TZ=' + q(timezone(cfg)) + ' date -d ' + q('@' + (int(trim(noon.out)) + 86400)) + ' +%Y-%m-%d');
            if (tomorrow.code != 0) return '';
            when = trim(tomorrow.out);
        }
        return when + ' ' + cfg.time + ' (' + cfg.timezone + ')';
    }
    function valid_probe(url) {
        if (type(url) != 'string' || length(url) > 512 || match(url, /[ \r\n\t]/)) return false;
        return !!match(url, /^https?:\/\/[A-Za-z0-9][A-Za-z0-9.:-]*(\/[A-Za-z0-9_./?=&%:+~-]*)?$/);
    }
    function readiness(cfg) {
        if (engine.busy()) return { ok: false, reason: 'An update transaction requires completion or recovery.' };
        if (!valid_probe(cfg.probe_url)) return { ok: false, reason: 'Configure an HTTP(S) Mesh service probe before enabling unattended updates.' };
        if (!access('/usr/bin/curl', 'x')) return { ok: false, reason: 'Install curl: bounded HTTP(S) service probing requires it.' };
        if (!ctx.profile_matches(cfg.profile_dir)) return { ok: false, reason: 'The configured profile directory could not be proven to be the running daemon identity directory.' };
        if (!engine.persistent(cfg.profile_dir)) return { ok: false, reason: 'The identity/profile directory is not on persistent storage.' };
        if (!access('/etc/rc.d/S04luci-netbird-recover', 'f') || !access('/etc/rc.d/S95luci-netbird-updater', 'f'))
            return { ok: false, reason: 'Enable the early recovery and independent updater services first.' };
        if (!ctx.monitor_running()) return { ok: false, reason: 'The independent updater monitor is not running.' };
        let daemon_start = false;
        for (let file in (lsdir('/etc/rc.d') || [])) {
            let m = match(file, /^S([0-9]{2})netbird$/);
            if (m) { if (int(m[1]) <= 4) return { ok: false, reason: 'NetBird starts before its recovery hook; adjust boot order before enabling updates.' }; daemon_start = true; }
        }
        if (!daemon_start) return { ok: false, reason: 'The NetBird boot service is not enabled; recovery startup order is unverified.' };
        // Presence of an unrelated watchdog is not treated as integration. The
        // executable adapter installs a verifiable early guard, not just a marker.
        if (access('/root/ztn-watchdog.sh', 'f') && !ctx.external_guarded())
            return { ok: false, reason: 'External /root/ztn-watchdog.sh is not integrated. Run agent-update-worker.uc integrate-watchdog explicitly.' };
        return { ok: true, reason: '' };
    }
    function admission(cfg) {
        let r = readiness(cfg);
        if (!r.ok) return r;
        let c = uci.cursor();
        if (ctx.active_source() != 'release') return { ok: false, reason: 'Custom binary sources are never automatically replaced.' };
        if (c.get('netbird', 'settings', 'service_enabled') == '0') return { ok: false, reason: 'NetBird service is disabled.' };
        if (c.get('netbird', 'runtime', 'desired_connected') != '1') return { ok: false, reason: 'Connection was not requested; no unattended restart.' };
        let s = ctx.sample();
        if (!s.ok || !s.management_connected || !s.signal_connected || !s.public_key || !s.mesh_ip || !s.version || !s.pid)
            return { ok: false, reason: 'The existing daemon is not fully connected and identifiable.' };
        if (!ctx.probe(cfg.probe_url)) return { ok: false, reason: 'The configured Mesh service probe is not reachable before upgrade.' };
        return { ok: true, baseline: s };
    }
    function save_config(req) {
        let a = req && req.args ? req.args : req || {};
        if (engine.busy() || access(launch, 'f') || ctx.locked()) return fail('An update or binary operation is in progress.');
        let cfg = { enabled: a.enabled === true || a.enabled === '1', time: a.time, timezone: a.timezone,
            min_age_hours: int(a.min_age_hours), probe_url: a.probe_url || '', profile_dir: a.profile_dir || '/var/lib/netbird' };
        if (!match(cfg.time || '', /^0[34]:[0-5][0-9]$/)) return fail('Choose a time inside the 03:00–05:00 maintenance window.');
        if (type(cfg.timezone) != 'string' || length(cfg.timezone) > 128 || index(cfg.timezone, '..') >= 0 ||
            !match(cfg.timezone, /^[A-Za-z][A-Za-z0-9_+,:.<>\/-]*$/)) return fail('Use system, a fixed-offset POSIX TZ string, or an installed IANA timezone.');
        let installed_zone = match(cfg.timezone, /^[A-Za-z0-9_+\/-]+$/) && access('/usr/share/zoneinfo/' + cfg.timezone, 'f');
        if (cfg.timezone != 'system' && !installed_zone && !match(cfg.timezone, /^[A-Za-z]{3,12}[+-]?(0?[0-9]|1[0-4])(:[0-5][0-9])?$/))
            return fail('Use a fixed-offset TZ such as UTC-8, system for device DST rules, or an installed IANA timezone.');
        if (!match('' + a.min_age_hours, /^[0-9]+$/) || cfg.min_age_hours < 48 || cfg.min_age_hours > 720)
            return fail('Stable releases must be at least 48–720 hours old.');
        if (cfg.probe_url && !valid_probe(cfg.probe_url)) return fail('Use an HTTP(S) service URL without credentials or whitespace.');
        if (!match(cfg.profile_dir, /^\/[A-Za-z0-9_./-]+$/) || index(cfg.profile_dir, '/..') >= 0 || cfg.profile_dir == '/')
            return fail('Use an absolute identity/profile directory, not a parent path or root directory.');
        if (cfg.enabled) { let r = readiness(cfg); if (!r.ok) return fail(r.reason); }
        let c = uci.cursor();
        if (c.get('netbird_bin', 'auto_update') == null && !c.set('netbird_bin', 'auto_update', 'auto_update')) return fail('Could not create update configuration.');
        for (let key, value in cfg)
            if (!c.set('netbird_bin', 'auto_update', key, key == 'enabled' ? (value ? '1' : '0') : '' + value)) return fail('Could not stage update configuration.');
        if (!c.commit('netbird_bin')) return fail('Could not commit update configuration.');
        return { ok: true, data: { config: cfg } };
    }
    function newer(a, b) {
        let aa = split(a, '.'); let bb = split(b, '.');
        for (let i = 0; i < 3; i++) { if (int(aa[i]) != int(bb[i])) return int(aa[i]) > int(bb[i]); }
        return false;
    }
    function check() {
        let cfg = config();
        let r = ctx.release();
        if (!r.ok) return r;
        let release = r.data;
        if (release.draft !== false || release.prerelease !== false || !match(release.tag_name || '', /^v[0-9]+\.[0-9]+\.[0-9]+$/))
            return fail('The release metadata is not an official stable version.');
        let version = substr(release.tag_name, 1);
        let published = release.published_at || '';
        if (!match(published, /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/)) return fail('The stable release publication timestamp is missing or invalid.');
        let date = replace(replace(published, 'T', ' '), 'Z', '');
        let epoch = run('TZ=UTC0 date -d ' + q(date) + ' +%s');
        if (epoch.code != 0 || !match(trim(epoch.out), /^[0-9]+$/)) return fail('Could not determine release age.');
        let current = ctx.version('/usr/bin/netbird');
        let reason = '';
        if (!match(current || '', /^[0-9]+\.[0-9]+\.[0-9]+$/)) reason = 'The current installed version could not be determined.';
        else if (!newer(version, current)) reason = 'No newer stable version is available.';
        else if (ctx.now() - int(trim(epoch.out)) < cfg.min_age_hours * 3600) reason = 'The release has not passed the configured minimum age.';
        else if (index(engine.status().blocked_versions || [], version) >= 0 || engine.status().blocked_version == version) reason = 'This version failed activation and is blocked on this device.';
        let assets = release.assets || [];
        let arch = ctx.arch();
        let wanted = 'netbird_' + version + '_linux_' + arch + '.tar.gz';
        let bytes = 0;
        for (let asset in assets) if (asset.name == wanted && type(asset.size) == 'int' && asset.size > 0) bytes = asset.size;
        if (!bytes && !reason) reason = 'The stable release has no known-size official asset for this architecture.';
        return { ok: true, data: { version: version, published_at: published, current_version: current,
            eligible: !reason, reason: reason, asset_size: bytes } };
    }
    function start(scheduled) {
        if (engine.busy() || ctx.locked() || access(launch, 'f')) return fail('An update or binary operation is already in progress.');
        if (run('umask 077; mkdir ' + q(launch) + ' && date +%s > ' + q(launch + '/created')).code != 0) return fail('Could not reserve the update worker.');
        if (!engine.clear_cancel()) { run('rmdir ' + q(launch)); return fail('Could not clear the previous cancellation.'); }
        ctx.clear_cancel_download();
        let r = ctx.spawn(scheduled ? 'scheduled' : 'run');
        if (!r.ok) run('rm -rf ' + q(launch));
        return r;
    }
    function execute(scheduled) {
        let result = ctx.lock(function() {
            let cfg = config();
            if (scheduled) {
                if (!cfg.enabled) return fail('Automatic updates are disabled.');
                let t = local_time(cfg);
                if (!t || t.minute < 180 || t.minute >= 300) return fail('Outside the night maintenance window; no daytime catch-up.');
            }
            let gate = admission(cfg);
            if (!gate.ok) return scheduled ? { ok: true, data: { skipped: true, reason: gate.reason } } : fail(gate.reason);
            if (engine.canceled()) return { ok: false, code: 'download_canceled', message: 'Update canceled before download.' };
            let release = check();
            if (!release.ok) return release;
            if (!release.data.eligible) return { ok: true, data: { skipped: true, reason: release.data.reason } };
            if (engine.canceled()) return { ok: false, code: 'download_canceled', message: 'Update canceled before download.' };
            return ctx.update({ strict: true, scheduled: !!scheduled, version: release.data.version,
                asset_size: release.data.asset_size, baseline: gate.baseline, dl_timeout: 300 });
        });
        run('rm -rf ' + q(launch));
        let final = engine.status();
        let outcome = result.ok ? (result.data && result.data.skipped ? 'skipped' : 'success') :
            result.code == 'download_canceled' ? 'canceled' :
            final.phase == 'rolled_back' && result.message == final.message ? final.result : 'failed';
        if (!engine.busy()) engine.record({ result: outcome,
            message: result.message || (result.data ? result.data.reason : '') || final.message });
        return result;
    }
    function tick() {
        let cfg = config();
        if (!cfg.enabled) return { ok: true, data: { skipped: true, reason: 'disabled' } };
        let t = local_time(cfg);
        if (!t || sprintf('%02d:%02d', int(t.minute / 60), t.minute % 60) != cfg.time)
            return { ok: true, data: { skipped: true, reason: 'not-scheduled-minute' } };
        if (ctx.locked() || engine.busy() || access(launch, 'f')) return { ok: true, data: { skipped: true, reason: 'busy' } };
        if (run('umask 077; mkdir -p ' + q(dir) + ' && chmod 0700 ' + q(dir)).code != 0 || !engine.persistent(dir)) return fail('Cannot persist the daily scheduler ledger.');
        let ledger = trim(readfile(dir + '/last-day') || '');
        // High water date: even a clock rollback must never re-run an older day.
        if (ledger && ledger >= t.day) return { ok: true, data: { skipped: true, reason: 'already-claimed-or-clock-rollback' } };
        let claim = ctx.lock(function() {
            ledger = trim(readfile(dir + '/last-day') || '');
            if (ledger && ledger >= t.day) return { ok: true, data: { skipped: true, reason: 'already-claimed' } };
            if (writefile(dir + '/last-day.new', t.day + '\n') != 9 || run('sync').code != 0 ||
                !rename(dir + '/last-day.new', dir + '/last-day') || run('sync').code != 0)
                return fail('Could not persist the daily execution claim.');
            return { ok: true, data: { claimed: true } };
        });
        return claim.ok && claim.data && claim.data.claimed ? start(true) : claim;
    }
    function recover(boot, retry) {
        let result = engine.recover({ boot: !!boot, retry: !!retry });
        // A killed downloader has no destructive transaction yet. Remove only its
        // expired reservation, never a live worker's binary-operation lock.
        if (access(launch, 'f') && !ctx.worker_alive()) {
            let created = int(trim(readfile(launch + '/created') || '0'));
            if (ctx.now() - created > 10) run('rm -rf ' + q(launch));
        }
        return result;
    }
    function status() {
        let cfg = config(); let state = engine.status();
        if (!state.active && access(launch, 'f')) { state.active = true; state.phase = 'preparing'; }
        return { ok: true, data: { config: cfg, status: state, readiness: readiness(cfg), next_run: next_run(cfg) } };
    }
    return { config: config, status: status, set_config: save_config, readiness: readiness, admission: admission,
        check: check, start: function() { return start(false); }, execute: execute, tick: tick, recover: recover,
        cancel: function() { ctx.cancel_download(); return engine.cancel(); }, reset: engine.reset_failure,
        window_open: function() { let t = local_time(config()); return !!t && t.minute >= 180 && t.minute < 300; } };
}
return { create: create };

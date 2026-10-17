#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Destructive fixtures: disposable OpenWrt container ONLY, never a router.
set -eu
[ -f /.dockerenv ] || { echo 'Run only in a disposable container' >&2; exit 1; }
source_root="${1:-/src}"
export NBLIB="$source_root/luci-app-netbird/root/usr/share/rpcd/ucode/lib"
mkdir -p /etc/nb-auto-fixture /etc/init.d /etc/config /etc/rc.d /usr/share/netbird
cat > /etc/init.d/netbird <<'SH'
#!/bin/sh
base=/etc/nb-auto-fixture
mode=$(cat "$base/mode" 2>/dev/null)
version=$(/usr/bin/netbird version 2>/dev/null)
case "$1" in
stop) [ "$mode" = stop-stuck ] || rm -f "$base/running" ;;
start)
    [ "$mode" != start-fail ] || [ "$version" != 0.80.0 ] || exit 1
    : > "$base/running"
    pid=$(cat "$base/pid" 2>/dev/null); echo $((${pid:-100} + 1)) > "$base/pid"
    if [ "$version" = 0.80.0 ]; then
        echo migrated > "$base/profile/new-format.state"
        if [ "$mode" = identity ]; then
            printf '{"PublicKey":"changed","MeshIP":"100.64.0.1/16","DisableDNS":true,"PrivateKey":"private-fixture"}\n' > "$base/profile/default.json"
        elif [ "$mode" = dns ]; then
            printf '{"PublicKey":"peer-original","MeshIP":"100.64.0.1/16","DisableDNS":false,"PrivateKey":"private-fixture"}\n' > "$base/profile/default.json"
        fi
    fi ;;
enable|disable) : ;;
esac
exit 0
SH
chmod 0755 /etc/init.d/netbird
cat > /etc/nb-auto-fixture/test.uc <<'UCODE'
import { readfile, writefile, popen, stat, access } from 'fs';
import * as uci from 'uci';
const lib = getenv('NBLIB');
const q = loadfile(lib + '/shell.uc')().shell_quote;
const factory = loadfile(lib + '/agent_update.uc')().create;
const base = '/etc/nb-auto-fixture';
const state = '/etc/netbird-update';
let clock = 1000;
let mode = '';
let engine;
function check(condition, message) { if (!condition) die(message); }
function run(cmd) {
    if (mode == 'space' && index(cmd, 'df -k ') == 0)
        return { code: 0, out: 'Filesystem 1K-blocks Used Available Use% Mounted on\nfixture 10000 9999 1 99% /\n' };
    if (mode == 'interrupt-copy' && index(cmd, 'cp ' + q(base + '/candidate') + ' ') == 0) {
        let parent = popen('printf "%s" "$PPID"', 'r');
        let victim = trim(parent.read('all')); parent.close();
        cmd = '( sleep 3; printf corrupted > ' + q(base + '/profile/default.json') +
            ' ) </dev/null >/dev/null 2>&1 & kill -KILL ' + victim + '; wait';
    }
    let fd = popen(cmd, 'r');
    if (!fd) return { code: 127, out: '' };
    let text = fd.read('all') || '';
    return { code: fd.close(), out: text };
}
function version(path) { return trim(run(q(path) + ' version 2>/dev/null').out); }
function process_id() { return trim(run('printf "%s" "$PPID"').out); }
function sample() {
    if (!access(base + '/running', 'f')) return { ok: false };
    let v = version('/usr/bin/netbird');
    let p = json(readfile(base + '/profile/default.json'));
    let connected = !(mode == 'connection' && v == '0.80.0') && mode != 'old-unreachable';
    return { ok: true, version: v, pid: trim(readfile(base + '/pid') || '101'),
        public_key: p.PublicKey, mesh_ip: p.MeshIP, management_url: 'https://management.fixture.invalid',
        dns_fingerprint: sprintf('%J', { disable_dns: p.DisableDNS }),
        management_connected: connected, signal_connected: connected };
}
function probe(url) { return !(mode == 'probe' && version('/usr/bin/netbird') == '0.80.0'); }
function sleep(seconds) {
    if (mode == 'interrupt' && engine.status().phase == 'trial') {
        run('kill -KILL ' + process_id());
        die('SIGKILL failed');
    }
    clock += seconds;
    if (engine.status().phase == 'trial') {
        if (mode == 'cancel') engine.cancel();
        if (mode == 'restart') writefile(base + '/pid', '999');
        if (mode == 'deadline') clock += 601;
    }
}
function reset(test_mode) {
    mode = test_mode; clock = 1000;
    check(run('rm -rf ' + q(state) + ' ' + q(base + '/profile') + '; rm -f /tmp/nb-agent-launch.lock/created; rmdir /tmp/nb-agent-launch.lock 2>/dev/null; mkdir -p ' + q(base + '/profile')).code == 0, 'reset failed');
    writefile(base + '/mode', test_mode);
    writefile('/usr/bin/netbird', '#!/bin/sh\necho 0.78.1\n');
    writefile(base + '/candidate', '#!/bin/sh\necho 0.80.0\n');
    run('chmod 0755 /usr/bin/netbird ' + q(base + '/candidate'));
    writefile(base + '/profile/default.json', '{"PublicKey":"peer-original","MeshIP":"100.64.0.1/16","DisableDNS":true,"PrivateKey":"private-fixture"}\n');
    writefile(base + '/running', '1'); writefile(base + '/pid', '101');
    engine = factory({ run: run, quote: q, version: version, sample: sample, probe: probe,
        running: function() { return !!access(base + '/running', 'f'); },
        now: function() { return clock + 1700000000; }, uptime: function() { return clock; },
        sleep: sleep, pid: process_id });
}
function install() {
    return engine.install({ candidate: base + '/candidate', target: '/usr/bin/netbird', version: '0.80.0',
        active: true, was_running: true, strict: true, profile_dir: base + '/profile',
        probe_url: 'http://100.64.0.2/health', baseline: sample() });
}
let action = ARGV[0] || 'matrix';
if (action == 'interrupt' || action == 'interrupt-copy') { reset(action); install(); die('Worker did not get killed.'); }
if (action == 'boot' || action == 'recover' || action == 'recover-copy') {
    mode = ''; clock = 2000;
    engine = factory({ run: run, quote: q, version: version, sample: sample, probe: probe,
        running: function() { return !!access(base + '/running', 'f'); },
        now: function() { return clock + 1700000000; }, uptime: function() { return clock; }, sleep: sleep, pid: process_id });
    let result = engine.recover({ boot: action == 'boot' });
    check(result.ok, sprintf('recovery failed: %J', result));
    check(version('/usr/bin/netbird') == '0.78.1', 'recovery did not restore the old executable');
    check(!access(base + '/profile/new-format.state', 'f'), 'new-format state survived rollback');
    check(json(readfile(base + '/profile/default.json')).PrivateKey == 'private-fixture', 'identity not restored');
    check(engine.status().phase == (action == 'recover-copy' ? 'aborted' : action == 'boot' ? 'restored_waiting_health' : 'rolled_back'), 'incorrect recovery phase');
    if (action == 'boot') check(!access(base + '/running', 'f'), 'early boot recovery started the daemon before normal boot');
    print('PASS: ' + action + ' restores executable and identity with truthful health state\n');
    exit(0);
}
reset('');
let result = install();
check(result.ok && version('/usr/bin/netbird') == '0.80.0' && engine.status().phase == 'committed', sprintf('commit failed: %J', result));
check(clock >= 1300 && !access(state + '/old-binary', 'f') && !access(state + '/profile.tar', 'f'), 'commit skipped observation or leaked private snapshots');
print('PASS: atomic install, five-minute health observation, private snapshot cleanup\n');
for (let failure in ['connection', 'identity', 'dns', 'probe', 'restart', 'cancel', 'deadline', 'start-fail']) {
    reset(failure);
    let before = readfile(base + '/profile/default.json');
    result = install();
    check(!result.ok && version('/usr/bin/netbird') == '0.78.1', failure + ' did not restore old bytes');
    check(engine.status().phase == 'rolled_back' && !engine.status().paused, sprintf('%s rollback not verified: %J', failure, engine.status()));
    check(readfile(base + '/profile/default.json') == before && !access(base + '/profile/new-format.state', 'f'), failure + ' lost the identity snapshot');
    check(index(engine.status().blocked_versions, '0.80.0') >= 0, failure + ' was not version-blocked');
    print('PASS: ' + failure + ' activates rollback and verifies old connectivity\n');
}
reset('space'); result = install();
check(!result.ok && result.code == 'insufficient_space' && access(base + '/running', 'f') && version('/usr/bin/netbird') == '0.78.1', 'space failure stopped or replaced the original agent');
reset('stop-stuck'); result = install();
check(!result.ok && version('/usr/bin/netbird') == '0.78.1' && engine.status().phase == 'aborted', 'stop refusal altered the original binary');
reset('connection');
// Make the new version fail, then also deny management to the restored version.
let initial = sample(); mode = 'old-unreachable';
result = engine.install({ candidate: base + '/candidate', target: '/usr/bin/netbird', version: '0.80.0', active: true,
    was_running: true, strict: false, profile_dir: base + '/profile', baseline: initial, probe_url: '' });
check(!result.ok && version('/usr/bin/netbird') == '0.78.1' && engine.status().phase == 'rollback_failed' && engine.status().paused,
    'unreachable old version was falsely reported as successful rollback');
check(access(state + '/profile.tar', 'f') && (stat(state + '/profile.tar').mode & 511) == 384 && access(state + '/old-binary', 'f') && !engine.reset_failure().ok, 'unresolved rollback evidence was cleared or not private');
mode = ''; result = engine.recover({ retry: true });
check(result.ok && engine.status().phase == 'rolled_back', 'explicit repaired recovery failed');
check(engine.reset_failure().ok && length(engine.status().blocked_versions) == 0, 'explicit failure unblock failed');
print('PASS: no-space/stop refusal keep old agent; failed rollback pauses and retains evidence; repaired recovery\n');

// Scheduler decisions run against real UCI and the same persisted engine state.
reset('');
writefile('/etc/config/netbird', "config netbird 'settings'\n option service_enabled '1'\nconfig runtime 'runtime'\n option desired_connected '1'\n");
writefile('/etc/config/netbird_bin', "config netbird_bin 'binary'\n option binary_source 'release'\nconfig auto_update 'auto_update'\n option enabled '1'\n option time '03:30'\n option timezone 'UTC-8'\n option min_age_hours '48'\n option probe_url 'http://100.64.0.2/health'\n option profile_dir '/etc/nb-auto-fixture/profile'\n");
run('touch /usr/bin/curl; chmod 0755 /usr/bin/curl; ln -sf /etc/init.d/netbird /etc/rc.d/S90netbird; ln -sf /etc/init.d/netbird /etc/rc.d/S04luci-netbird-recover; ln -sf /etc/init.d/netbird /etc/rc.d/S95luci-netbird-updater');
let civil = '20261017 03:30 2026-10-17 +0800';
let published = '2026-10-14T19:30:00Z';
let released_at = int(trim(run("TZ=UTC0 date -d '2026-10-14 19:30:00' +%s").out));
let age = 48 * 3600;
let launches = 0;
let release = { draft: false, prerelease: false, tag_name: 'v0.80.0', published_at: published,
    assets: [{ name: 'netbird_0.80.0_linux_amd64.tar.gz', size: 12000000 }] };
let scheduler = loadfile(lib + '/agent_schedule.uc')().create({
    engine: engine, quote: q, run: function(cmd) { return index(cmd, '+%Y%m%d') >= 0 ? { code: 0, out: civil } : run(cmd); },
    now: function() { return released_at + age; }, active_source: function() { return uci.cursor().get('netbird_bin', 'binary', 'binary_source'); },
    profile_matches: function(path) { return path == base + '/profile'; }, probe: probe, sample: sample,
    monitor_running: function() { return true; }, external_guarded: function() { return false; },
    version: version, arch: function() { return 'amd64'; }, release: function() { return { ok: true, data: release }; },
    locked: function() { return false; }, lock: function(fn) { return fn(); }, worker_alive: function() { return false; },
    spawn: function() { launches++; return { ok: true, data: { started: true } }; },
    cancel_download: function() {}, clear_cancel_download: function() { run('rm -f /tmp/luci-netbird-binary-download.cancel'); },
    update: function() { die('scheduler fixture must not install'); }
});
check(scheduler.check().data.eligible, 'exact 48-hour stable release rejected');
age--; check(!scheduler.check().data.eligible, 'under-age release accepted'); age++;
release.prerelease = true; check(!scheduler.check().ok, 'prerelease accepted'); release.prerelease = false;
release.draft = true; check(!scheduler.check().ok, 'draft accepted'); release.draft = false;
release.tag_name = 'v0.78.0'; check(!scheduler.check().data.eligible, 'downgrade offered'); release.tag_name = 'v0.80.0';
check(scheduler.admission(scheduler.config()).ok, 'healthy baseline was not admitted');
let c = uci.cursor(); c.set('netbird', 'runtime', 'desired_connected', '0'); c.commit('netbird');
check(!scheduler.admission(scheduler.config()).ok, 'manual disconnect ignored');
c = uci.cursor(); c.set('netbird', 'runtime', 'desired_connected', '1'); c.commit('netbird');
c = uci.cursor(); c.set('netbird_bin', 'binary', 'binary_source', 'custom'); c.commit('netbird_bin');
check(!scheduler.admission(scheduler.config()).ok, 'custom source admitted');
c = uci.cursor(); c.set('netbird_bin', 'binary', 'binary_source', 'release'); c.commit('netbird_bin');
check(scheduler.tick().ok && launches == 1, 'scheduled minute not launched');
run('rm -rf /tmp/nb-agent-launch.lock');
check(scheduler.tick().data.skipped && launches == 1, 'same day executed twice');
civil = '20261016 03:30 2026-10-16 +0800';
check(scheduler.tick().data.skipped && launches == 1, 'clock rollback executed an older day');
civil = '20261018 09:30 2026-10-18 +0800';
check(scheduler.tick().data.skipped && launches == 1, 'missed check was caught up during daytime');
let rejected = scheduler.set_config({ enabled: false, time: '05:00', timezone: 'UTC-8', min_age_hours: 48, profile_dir: base + '/profile' });
check(!rejected.ok, 'outside-window schedule saved');
check(scheduler.start().ok, 'explicit safe update could not reserve its worker');
check(engine.cancel().ok, 'queued cancellation could not be persisted');
let canceled_before_download = scheduler.execute(false);
check(!canceled_before_download.ok && canceled_before_download.code == 'download_canceled', 'queued cancellation was lost before download');
check(scheduler.start().ok && !engine.canceled(), 'a completed cancellation poisoned the next update');
run('rm -rf /tmp/nb-agent-launch.lock');
print('PASS: release age boundary, stable-only, no downgrade, manual intent, custom source, day de-duplication, clock rollback, no daytime catch-up\n');
UCODE
setsid ucode /etc/nb-auto-fixture/test.uc matrix
set +e
setsid ucode /etc/nb-auto-fixture/test.uc interrupt
result=$?
set -e
[ "$result" -eq 137 ] || { echo "Expected SIGKILL, got $result" >&2; exit 1; }
setsid ucode /etc/nb-auto-fixture/test.uc boot
setsid ucode /etc/nb-auto-fixture/test.uc recover
printf 'PASS: orphan worker SIGKILL and early-boot recovery phases\n'
set +e
setsid ucode /etc/nb-auto-fixture/test.uc interrupt-copy
result=$?
set -e
[ "$result" -eq 137 ] || exit 1
setsid ucode /etc/nb-auto-fixture/test.uc recover-copy
sleep 4
ucode -e 'import {readfile} from "fs"; if (json(readfile("/etc/nb-auto-fixture/profile/default.json")).PrivateKey != "private-fixture") die("orphan writer corrupted the restored identity");'
printf 'PASS: orphan writer group drained before recovery; no late identity corruption\n'

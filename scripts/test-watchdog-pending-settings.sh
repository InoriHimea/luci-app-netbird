#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Watchdog vs. /etc/netbird-settings.pending and daemon log level. Disposable OpenWrt only:
# docker run --rm --platform linux/amd64 -v "$PWD:/src" openwrt/rootfs:x86-64-25.12.2 \
#   sh /src/scripts/test-watchdog-pending-settings.sh
set -eu
[ -f /.dockerenv ] || { echo 'Disposable container required' >&2; exit 1; }
source_root="${1:-/src}"
sh "$source_root/scripts/test-watchdog-ownership.sh" "$source_root"

wd_pid() {
	/bin/ubus call service list '{"name":"luci-netbird-watchdog"}' |
		jsonfilter -e '@["luci-netbird-watchdog"].instances.instance1.pid'
}

# Freeze the real watchdog so its own 30 s rounds cannot advance the counter under test.
pid="$(wd_pid)"
kill -STOP "$pid"

cat >/tmp/watchdog-pending.uc <<'EOF'
import {readfile,writefile,unlink,lstat,mkdir} from 'fs';
import {connect} from 'ubus';
let bus=connect(null,30), pid=+ARGV[0];
function cfg(desired) {
 writefile('/etc/config/netbird',"config netbird 'settings'\n option service_enabled '1'\nconfig runtime 'runtime'\n option desired_connected '"+desired+"'\n");
}
function step(connected,recover) {
 writefile('/tmp/native-watchdog-status',connected?'{"daemonStatus":"Connected","management":{"connected":true}}':'{"daemonStatus":"Idle","management":{"connected":false}}');
 let r=bus.call('luci.netbird','watchdog_step',{pid,recover});
 if(!r||!r.ok)die(sprintf('watchdog_step failed: %J',r));
 return r.data;
}
const P='/etc/netbird-settings.pending';
cfg('1');
writefile(P,'');
// Regression: the settings marker used to make every round return maintenance.
let d=step(false,false);
if(d.state!='disconnected')die(sprintf('settings marker still gates the watchdog: %J',d));
// Counter restarts after any round that is not connected.
for(let i=1;i<=2;i++){d=step(true,false);if(d.state!='connected'||d.settings_applied)die(sprintf('applied too early (%d): %J',i,d));}
d=step(false,false);
if(d.state!='disconnected')die(sprintf('bad disconnected round: %J',d));
for(let i=1;i<=3;i++){d=step(true,false);if(d.state!='connected'||d.settings_applied||!lstat(P))die(sprintf('applied before 4 consecutive rounds (%d): %J',i,d));}
d=step(true,false);
if(d.state!='connected'||d.settings_applied!==true)die(sprintf('pending settings not applied on round 4: %J',d));
if(lstat(P))die('pending marker not cleared after apply');
// No marker: no counting, no apply.
for(let i=1;i<=5;i++){d=step(true,false);if(d.settings_applied)die('applied without marker');}
// The agent-update deferral marker remains a maintenance gate.
mkdir('/etc/netbird-update',0700);
writefile('/etc/netbird-update/settings.pending','');
d=step(true,false);
if(d.state!='maintenance')die(sprintf('update deferral marker no longer gates: %J',d));
unlink('/etc/netbird-update/settings.pending');
bus.disconnect();
print('settings marker no longer gates; apply after 4 consecutive connected rounds, counter resets; update deferral still gates PASS\n');
EOF
rc=0
ucode /tmp/watchdog-pending.uc "$pid" || rc=$?
kill -CONT "$pid"
[ "$rc" -eq 0 ] || exit "$rc"
# Let the background netbird-settings reload started by the apply finish before the next fixture.
i=0
while [ -d /tmp/nb-binop.lock ] || pgrep -f 'netbird-settings' >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 30 ] || break; sleep 1; done

# Log level: the watchdog re-applies netbird.settings.log_level once per daemon PID+level.
cat >/usr/bin/netbird <<'EOF'
#!/bin/sh
case "$1" in
status) cat /tmp/native-watchdog-status ;;
debug)
	if [ "${4:-}" = "--help" ]; then echo 'Usage:'; echo '  netbird debug log level <level> [flags]'; exit 0; fi
	echo "debug $2 $3 $4" >>/tmp/native-loglevel-effects ;;
*) echo "$1" >>/tmp/native-watchdog-effects ;;
esac
EOF
chmod 0755 /usr/bin/netbird
cat >/etc/config/netbird <<'EOF'
config netbird 'settings'
 option service_enabled '1'
 option log_level 'debug'
config runtime 'runtime'
 option desired_connected '1'
EOF
echo '{"daemonStatus":"Connected","management":{"connected":true}}' >/tmp/native-watchdog-status
rm -f /tmp/native-loglevel-effects /var/run/netbird-loglevel.applied /etc/netbird-settings.pending
/etc/init.d/luci-netbird-watchdog restart
i=0
until [ -s /tmp/native-loglevel-effects ]; do i=$((i+1)); [ "$i" -lt 15 ] || { echo 'FAIL: watchdog did not apply the daemon log level'; logread 2>/dev/null | tail -20; exit 1; }; sleep 1; done
[ "$(cat /tmp/native-loglevel-effects)" = 'debug log level debug' ] || { echo "FAIL: unexpected log level call: $(cat /tmp/native-loglevel-effects)"; exit 1; }
grep -qx 'unknown debug' /var/run/netbird-loglevel.applied || { echo 'FAIL: applied marker missing'; exit 1; }
# Same daemon PID and level: the next round must not call netbird again.
/etc/init.d/luci-netbird-watchdog restart
sleep 4
[ "$(wc -l </tmp/native-loglevel-effects)" -eq 1 ] || { echo 'FAIL: log level re-applied without a PID or level change'; exit 1; }
echo 'watchdog applies daemon log level once per PID+level PASS'
echo PASS

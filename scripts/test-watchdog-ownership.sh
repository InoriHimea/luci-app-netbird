#!/bin/sh
# Run only in a disposable OpenWrt container with native ubusd/rpcd/procd.
set -eu
[ -f /.dockerenv ] || { echo 'Disposable container required' >&2; exit 1; }
source_root="${1:-/src}"
cp -R "$source_root/luci-app-netbird/root/." /
mkdir -p /etc/config /var/run/ubus /var/lock
cat >/etc/config/netbird <<'EOF'
config netbird 'settings'
 option service_enabled '1'
config runtime 'runtime'
 option desired_connected '0'
EOF
cat >/tmp/native-watchdog-status <<'EOF'
{"daemonStatus":"Connected","management":{"connected":true}}
EOF
cat >/usr/bin/netbird <<'EOF'
#!/bin/sh
case "$1" in
status) cat /tmp/native-watchdog-status ;;
*) echo "$1" >>/tmp/native-watchdog-effects ;;
esac
EOF
chmod 0755 /usr/bin/netbird /etc/init.d/luci-netbird-watchdog /usr/share/netbird/netbird-autoreconnect.sh
/sbin/ubusd >/tmp/ubusd.log 2>&1 &
i=0
until /bin/ubus list >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 8 ] || { cat /tmp/ubusd.log; exit 1; }; sleep 1; done
/sbin/rpcd >/tmp/rpcd.log 2>&1 &
i=0
until /bin/ubus -t 1 call luci.netbird get_status '{}' >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 8 ] || { cat /tmp/rpcd.log; exit 1; }; sleep 1; done
/sbin/procd -S -d 0 >/tmp/procd.log 2>&1 &
printf '%s\n' "$!" >/tmp/native-procd.pid
i=0
until /bin/ubus -t 1 call service list '{}' >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 8 ] || { cat /tmp/procd.log; exit 1; }; sleep 1; done
/etc/init.d/luci-netbird-watchdog start
i=0
until [ -f /tmp/netbird-actions/watchdog.json ] && [ ! -d /tmp/nb-binop.lock ]; do i=$((i+1)); [ "$i" -lt 12 ] || { cat /tmp/rpcd.log; /bin/ubus call service list; exit 1; }; sleep 1; done
ucode -e 'import {readfile} from "fs"; import * as uci from "uci"; let c=uci.cursor(); if(c.get("netbird","runtime","desired_connected")!="0")die("connected sampling overwrote explicit disconnect"); let r=json(readfile("/tmp/netbird-actions/watchdog.json")); if(type(r.pid)!="int"||r.pid<=1)die("missing negotiated native PID");print("real procd receipt; explicit disconnect preserved\n");'
cat >/tmp/watchdog-native.uc <<'EOF'
import {readfile,writefile,unlink,chmod} from 'fs';
import * as uci from 'uci';
import {watchdog_coordinated} from '/usr/share/netbird/health/watchdog-coordination.uc';
import {recovery_eligibility} from '/usr/share/netbird/health/recovery-policy.uc';
import {connect} from 'ubus';
let bus=connect(), services=bus.call('service','list',{name:'luci-netbird-watchdog'});
let instance=services['luci-netbird-watchdog'].instances.instance1;
if(!watchdog_coordinated(instance))die(sprintf('negotiated live instance rejected: %J',instance));
let receipt=readfile('/tmp/netbird-actions/watchdog.json');
unlink('/tmp/netbird-actions/watchdog.json');
if(watchdog_coordinated(instance))die('argv flag accepted without runtime receipt');
writefile('/tmp/netbird-actions/watchdog.json',receipt);
if(watchdog_coordinated(instance))die('unsafe receipt permissions accepted');
chmod('/tmp/netbird-actions/watchdog.json',0600);
let forged=json(receipt); forged.started='0';
writefile('/tmp/netbird-actions/watchdog.json',sprintf('%J',forged));
if(watchdog_coordinated(instance))die('receipt from another process start accepted');
writefile('/tmp/netbird-actions/watchdog.json',receipt);
let c=uci.cursor(); c.set('netbird','runtime','desired_connected','1');c.save('netbird');c.commit('netbird');
let eligible=recovery_eligibility(false); if(!eligible.ok)die(sprintf('coordinated watchdog still conflicts: %J',eligible));
function step(desired,enabled,state,expected) {
 writefile('/etc/config/netbird',"config netbird 'settings'\n option service_enabled '"+enabled+"'\nconfig runtime 'runtime'\n option desired_connected '"+desired+"'\n");
 writefile('/tmp/native-watchdog-status',sprintf('%J',state));
 let result=bus.call('luci.netbird','watchdog_step',{pid:instance.pid,recover:true});
 if(!result.ok||result.data.state!=expected)die(sprintf('bad watchdog result: %J',result));
 return uci.cursor().get('netbird','runtime','desired_connected');
}
if(step('0','1',{daemonStatus:'Connected',management:{connected:true}},'stopped')!='0')die('explicit disconnect overwritten');
if(step('1','0',{daemonStatus:'Connected',management:{connected:true}},'stopped')!='1')die('disabled intent overwritten');
if(step('1','1',{daemonStatus:'NeedsLogin',management:{connected:false}},'authentication_required')!='0')die('NeedsLogin did not stop retry intent');
if(readfile('/tmp/native-watchdog-effects')!=null)die('unauthorized agent command occurred');
if(step('1','1',{daemonStatus:'Idle',management:{connected:false,error:'code = PermissionDenied'}},'authentication_required')!='0')die('fatal authentication did not stop retry intent');
if(readfile('/tmp/native-watchdog-effects')!='down\n')die('fatal authentication did not perform exactly one owned down');
if(step('','1',{daemonStatus:'Connected',management:{connected:true}},'connected')!='1')die('missing connection intent was not adopted');
print('live receipt and process-start identity required; coordinated eligibility; stopped/disabled/NeedsLogin/fatal-auth/adoption boundaries pass\n');
bus.disconnect();
EOF
ucode /tmp/watchdog-native.uc

cat >/tmp/global-budget.uc <<'EOF'
import {connect} from 'ubus';
import {readfile,writefile,unlink} from 'fs';
import {create_action_journal} from '/usr/share/netbird/health/action-journal.uc';
import {monotonic_ms} from '/usr/share/netbird/health/runner.uc';
unlink('/etc/netbird-actions/journal.json');
let clock=monotonic_ms()-180000, journal=create_action_journal(null,()=>clock);
for(let i=1;i<=3;i++) {let r=journal.reserve(sprintf('%032x',1000+i),'manual-recovery','root','restart');if(!r.ok)die(sprintf('cannot seed quota: %J',r));clock+=60000;}
unlink('/tmp/native-watchdog-effects');
writefile('/etc/config/netbird',"config netbird 'settings'\n option service_enabled '1'\nconfig runtime 'runtime'\n option desired_connected '1'\n");
writefile('/tmp/native-watchdog-status','{"daemonStatus":"Idle","management":{"connected":false}}');
let bus=connect(null,10),services=bus.call('service','list',{name:'luci-netbird-watchdog'}),pid=services['luci-netbird-watchdog'].instances.instance1.pid;
let r=bus.call('luci.netbird','watchdog_step',{pid,recover:true});
if(r.ok||r.message!='ACTION_BUDGET_EXHAUSTED')die(sprintf('watchdog budget bypass: %J',r));
r=bus.call('luci.netbird','do_reconnect',{});
if(r.ok||r.message!='ACTION_BUDGET_EXHAUSTED')die(sprintf('manual reconnect budget bypass: %J',r));
if(readfile('/tmp/native-watchdog-effects')!=null)die('quota denied after agent effect');
r=bus.call('luci.netbird','do_down',{});
if(!r.ok||readfile('/tmp/native-watchdog-effects')!='down\n')die(sprintf('explicit stop was quota blocked: %J',r));
let events=json(readfile('/etc/netbird-actions/journal.json')).events,stop=events[length(events)-1];
if(stop.kind!='control'||stop.actor!='local-root'||stop.operation.outcome!='handler_ok'||stop.outcome!='UNKNOWN')die('native stop audit incorrect');
let session=bus.call('session','create',{timeout:60}),sid=session.ubus_rpc_session;
bus.call('session','set',{ubus_rpc_session:sid,values:{username:'native-operator'}});
r=bus.call('luci.netbird','do_down',{ubus_rpc_session:sid});
let latest=json(readfile('/etc/netbird-actions/journal.json')).events;
if(!r.ok||latest[length(latest)-1].actor!='native-operator')die('manual stop lost native session actor');
bus.call('session','destroy',{ubus_rpc_session:sid});
bus.disconnect();print('full shared quota: watchdog/manual reconnect zero effects; explicit stop exactly once with honest native audit PASS\n');
EOF
ucode /tmp/global-budget.uc

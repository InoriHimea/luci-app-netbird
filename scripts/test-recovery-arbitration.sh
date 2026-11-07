#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Disposable OpenWrt only: native RPC/procd plus real isolated writer groups.
set -eu
[ -f /.dockerenv ] || { echo 'Disposable container required' >&2; exit 1; }
source_root="${1:-/src}"
sh "$source_root/scripts/test-watchdog-ownership.sh" "$source_root"
/bin/ubus call luci.netbird set_agent_update_config '{"enabled":false,"time":"03:30","timezone":"UTC-8","min_age_hours":48,"profile_dir":"/var/lib/netbird"}' >/tmp/nbh-config-control
ucode -e 'import {readfile} from "fs";let r=json(readfile("/tmp/nbh-config-control"));if(!r.ok||r.data.config.enabled!==false)die(sprintf("disabled update configuration rejected under its own owner: %J",r));'
mkdir -p /etc/netbird-update
chmod 0700 /etc/netbird-update
cat >/tmp/interrupted-first-install.uc <<'EOF'
import {readfile,writefile,open,popen} from 'fs';
let gate=loadfile('/usr/share/rpcd/ucode/lib/action_lock.uc')().create();
if(!gate.acquire('agent-update').ok)die('cannot acquire fixture transaction owner');
let text=readfile('/proc/self/stat'),m=match(text,/^([0-9]+) \(.*\) (.+)$/),fields=split(m[2],' ');
let owner={pid:m[1],start:fields[19],state:fields[0],group:fields[2],session:fields[3],boot:trim(readfile('/proc/sys/kernel/random/boot_id'))};
if(owner.group!=owner.pid||owner.session!=owner.pid)die('fixture writer is not isolated');
let journal={schema:1,transaction_id:trim(readfile('/proc/sys/kernel/random/uuid')),phase:'prepared',target:'/etc/nbh-first-install',staged:'/etc/nbh-first-install.nb-update-new',owner,
 prepare_uptime:0,had_target:false,was_running:false,active:false,stop_requested:false,activation_requested:false,snapshot_ready:false,backup_ready:false};
let file=open('/etc/netbird-update/transaction.json','w',0600);
file.write(sprintf('%J',journal));file.close();
let child=popen('(sleep 5; echo late > /tmp/nbh-first-install-late) >/dev/null 2>&1 & echo armed','r');
if(trim(child.read('all'))!='armed'||child.close()!=0)die('late writer not armed');
writefile('/tmp/nbh-first-install-ready','1');
sleep(60000);
EOF
/bin/busybox setsid /usr/bin/ucode /tmp/interrupted-first-install.uc &
i=0
until [ -f /tmp/nbh-first-install-ready ]; do i=$((i+1)); [ "$i" -lt 10 ] || exit 1; sleep 1; done
owner=$(cat /tmp/nb-binop.lock/owner)
/bin/ubus call luci.netbird cancel_agent_update '{}' >/tmp/nbh-cancel-intent
[ "$(cat /tmp/nb-binop.lock/owner)" = "$owner" ] || { echo 'cancel replaced the live execution owner'; exit 1; }
ucode -e 'import {readfile} from "fs";if(!json(readfile("/tmp/nbh-cancel-intent")).ok||readfile("/etc/netbird-update/cancel")!="1")die("live-owned update cannot be cooperatively canceled");let events=json(readfile("/etc/netbird-actions/journal.json")).events;let e=events[length(events)-1];if(e.owner!="cancel-request"||e.kind!="control"||e.operation.outcome!="handler_ok")die("cooperative cancel lost its native control audit");print("full-quota configuration and live-owner cooperative cancellation PASS\n");'
kill -9 "$owner"
NB_AGENT_WORKER=1 /usr/bin/ucode /usr/share/netbird/agent-update-worker.uc recover
sleep 6
ucode -e 'import {readfile} from "fs"; let s=json(readfile("/etc/netbird-update/transaction.json"));if(s.phase!="aborted")die("first-install recovery did not complete");if(readfile("/tmp/nbh-first-install-late")!=null)die("old writer survived shared-owner takeover");let events=json(readfile("/etc/netbird-actions/journal.json")).events;let found=false;for(let e in events)if(e.owner=="update-recovery"&&e.kind=="control"&&e.phase=="operation_finished")found=true;if(!found)die("rollback did not use quota-free shared audit");let gate=loadfile("/usr/share/rpcd/ucode/lib/action_lock.uc")().create();if(!gate.available())die("completed recovery left another orphan quarantine");print("real owner SIGKILL: first-install writers drained, full-quota rollback owned/audited, no late write or extra 600-second fence PASS\n");'

# Separate admitted action: no previous quota from the crash scenario is reset
# during this concurrent run or its immediate manual retry.
rm -f /etc/netbird-actions/journal.json /tmp/native-watchdog-effects
uci set netbird.runtime.desired_connected=1
uci commit netbird
cat >/usr/bin/netbird <<'EOF'
#!/bin/sh
case "$1" in
version) echo 0.78.1 ;;
status) cat /tmp/native-watchdog-status ;;
down)
 echo down >>/tmp/native-watchdog-effects
 echo '{"daemonStatus":"Idle","management":{"connected":false}}' >/tmp/native-watchdog-status
 touch /tmp/nbh-manual-entered
 sleep 2 ;;
up)
 [ "$2" = --help ] && { echo ' --no-browser '; exit 0; }
 echo up >>/tmp/native-watchdog-effects
 echo '{"daemonStatus":"Connected","management":{"connected":true}}' >/tmp/native-watchdog-status ;;
*) echo "$1" >>/tmp/native-watchdog-effects ;;
esac
EOF
chmod 0755 /usr/bin/netbird
/bin/ubus -t 60 call luci.netbird do_reconnect '{}' >/tmp/nbh-manual-result &
manual=$!
i=0
until [ -f /tmp/nbh-manual-entered ]; do i=$((i+1)); [ "$i" -lt 10 ] || exit 1; sleep 1; done
set +e
NB_ACTION_WORKER=1 ucode /usr/share/netbird/action-worker.uc settings >/tmp/nbh-settings-contender
settings_rc=$?
NB_AGENT_WORKER=1 ucode /usr/share/netbird/agent-update-worker.uc run fixture-scheduler >/tmp/nbh-scheduler-contender
scheduler_rc=$?
set -e
[ "$settings_rc" = 75 ] && [ "$scheduler_rc" = 1 ] || { cat /tmp/nbh-settings-contender /tmp/nbh-scheduler-contender; exit 1; }
pid=$(ucode -e 'import {readfile} from "fs"; print(json(readfile("/tmp/netbird-actions/watchdog.json")).pid);')
/bin/ubus -t 60 call luci.netbird watchdog_step "{\"pid\":$pid,\"recover\":true}" >/tmp/nbh-watchdog-contender &
watchdog=$!
wait "$manual"
wait "$watchdog"
ucode -e 'import {readfile} from "fs"; import {connect} from "ubus";let result=json(readfile("/tmp/nbh-manual-result"));if(!result.ok)die(sprintf("manual action failed: %J",result));if(readfile("/tmp/native-watchdog-effects")!="down\nup\n")die(sprintf("unexpected concurrent agent effects: %J",readfile("/tmp/native-watchdog-effects")));let events=json(readfile("/etc/netbird-actions/journal.json")).events;let charges=filter(events,e=>e.kind!="control");if(length(charges)!=1||charges[0].owner!="manual-reconnect")die("one effective action did not have exactly one reservation");let bus=connect();let again=bus.call("luci.netbird","do_reconnect",{});if(again.ok||again.message!="ACTION_COOLDOWN"||readfile("/tmp/native-watchdog-effects")!="down\nup\n")die("immediate retry bypassed shared cooldown");bus.disconnect();print("native manual/watchdog/settings/updater competition: one down/up, one charge, immediate retry has zero effects PASS\n");'

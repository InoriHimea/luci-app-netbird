#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Disposable OpenWrt only: native sessions and real background binary operations.
set -eu
[ -f /.dockerenv ] || { echo "Disposable container required" >&2; exit 1; }
source_root="${1:-/src}"
sh "$source_root/scripts/test-binary-and-app-update.sh" "$source_root"
cp "$source_root/luci-app-netbird/root/usr/share/rpcd/ucode/netbird.uc" /usr/share/rpcd/ucode/netbird.uc
export PATH=/tmp/nb-regression-bin:/usr/sbin:/usr/bin:/sbin:/bin
rm -f /etc/netbird-actions/journal.json
mkdir -p /var/run/ubus
cd /
/sbin/ubusd >/tmp/bus.log 2>&1 &
i=0; until /bin/ubus list >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 10 ] || exit 1; sleep 1; done
/sbin/rpcd >/tmp/rpcd.log 2>&1 &
i=0; until /bin/ubus -t 1 call luci.netbird get_status '{}' >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 10 ] || { cat /tmp/rpcd.log; exit 1; }; sleep 1; done
cat >/tmp/worker-actor.uc <<'EOF'
import {connect} from 'ubus';
import {readfile,writefile,chmod} from 'fs';
let bus=connect(null,10),session=bus.call('session','create',{timeout:90}),sid=session.ubus_rpc_session;
bus.call('session','set',{ubus_rpc_session:sid,values:{username:'operator-worker'}});
function await_done(){for(let i=0;i<150;i++){let p=bus.call('luci.netbird','get_binary_update_progress',{});if(p.data.phase=='failed')die(sprintf('worker failed: %J',p));if(p.data.phase=='done')return;sleep(100);}die('worker did not complete');}
let started=bus.call('luci.netbird','start_binary_source_switch',{source:'custom',version:'0.79.0',ubus_rpc_session:sid});
if(!started.ok)die(sprintf('source did not start: %J',started));await_done();
let events=json(readfile('/etc/netbird-actions/journal.json')).events,source=events[length(events)-1];
if(source.owner!='source-switch'||source.actor!='operator-worker'||source.operation.outcome!='handler_ok')die(sprintf('source actor lost: %J',source));
let active=readfile('/usr/bin/netbird');
writefile('/usr/share/netbird/bin/netbird-release','#!/bin/sh\necho 0.78.1\n');chmod('/usr/share/netbird/bin/netbird-release',0755);
started=bus.call('luci.netbird','start_binary_update',{ubus_rpc_session:sid});
if(!started.ok)die(sprintf('cache update did not start: %J',started));await_done();
events=json(readfile('/etc/netbird-actions/journal.json')).events;let cached=events[length(events)-1];
if(cached.owner!='binary-cache'||cached.kind!='control'||cached.actor!='operator-worker'||cached.operation.outcome!='handler_ok')die(sprintf('cache actor lost: %J',cached));
if(readfile('/usr/bin/netbird')!=active)die('inactive update changed active custom binary');
bus.call('session','destroy',{ubus_rpc_session:sid});bus.disconnect();
print('native authenticated source switch and background inactive-binary update preserve operator-worker audit and active custom bytes PASS\n');
EOF
ucode /tmp/worker-actor.uc

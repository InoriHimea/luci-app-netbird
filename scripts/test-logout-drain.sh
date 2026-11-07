#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Destructive service/identity fixtures: disposable OpenWrt only.
set -eu
[ -f /.dockerenv ] || { echo 'Disposable container required' >&2; exit 1; }
source_root="${1:-/src}"
sh "$source_root/scripts/test-watchdog-ownership.sh" "$source_root"
native_procd=$(cat /tmp/native-procd.pid)
/etc/init.d/luci-netbird-watchdog stop
i=0
while [ -d /tmp/nb-binop.lock ]; do i=$((i+1)); [ "$i" -lt 12 ] || exit 1; sleep 1; done
cat >/etc/init.d/netbird <<'EOF'
#!/bin/sh
echo "$1" >>/tmp/logout-init-effects
case "$1" in stop) exit "$(cat /tmp/logout-stop-code)" ;; esac
exit 0
EOF
chmod 0755 /etc/init.d/netbird
mkdir -p /etc/netbird
cat >/tmp/logout-drain.uc <<'EOF'
import {connect} from 'ubus';
import {readfile,writefile,unlink} from 'fs';
import * as uci from 'uci';
let bus=connect(null,30);
for(let stop_code in ARGV[0]=='unknown'?[-1]:[9,0]) {
    if(stop_code==0) {
        bus.call('service','set',{name:'netbird',instances:{fixture:{command:['/bin/sleep','300']}}});
        let running=false;
        for(let i=0;i<50;i++) {
            let service=bus.call('service','list',{name:'netbird'});
            if(service?.netbird?.instances?.fixture?.running) {running=true;break;}
            sleep(100);
        }
        if(!running)die('native live-daemon fixture did not start');
    }
    writefile('/etc/netbird/config.json','owned-identity-fixture');
    writefile('/tmp/logout-stop-code',''+(stop_code<0?0:stop_code));
    unlink('/tmp/logout-init-effects');
    let r=bus.call('luci.netbird','do_logout',{local_only:'1'});
    if(r?.ok || readfile('/etc/netbird/config.json')!='owned-identity-fixture')
        die(sprintf('logout erased identity despite stop/drain failure: stop=%d result=%J',stop_code,r));
    let stops=0;
    for(let action in split(readfile('/tmp/logout-init-effects')||'','\n')) {
        if(action=='stop')stops++;
        else if(action=='start'||action=='restart'||action=='reload'||action=='enable')
            die(sprintf('failed logout executed lifecycle action %s',action));
    }
    if(stops!=1)die(sprintf('logout did not execute exactly one stop: %J',r));
    let c=uci.cursor();
    if(c.get('netbird','runtime','desired_connected')!='0')die('failed logout lost explicit disconnected intent');
    let events=json(readfile('/etc/netbird-actions/journal.json')).events,latest=events[length(events)-1];
    if(latest.operation.outcome!='handler_failed'||latest.outcome!='UNKNOWN')die('logout failure audit claimed success');
    print(sprintf('PASS: logout stop=%d preserves identity, disconnected intent and truthful failure audit\n',stop_code));
}
if(ARGV[0]!='unknown')bus.call('service','delete',{name:'netbird'});
bus.disconnect();
EOF
ucode /tmp/logout-drain.uc
kill "$native_procd"
i=0
while /bin/ubus -t 1 call service list '{}' >/dev/null 2>&1; do
    i=$((i+1)); [ "$i" -lt 12 ] || exit 1; sleep 1
done
ucode /tmp/logout-drain.uc unknown

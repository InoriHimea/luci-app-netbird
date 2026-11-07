#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Disposable no-NIC guest only. Never reads host identity or joins a Peer.
set -eu
[ "${NBH_DISPOSABLE_GUEST:-}" = YES ] &&
    [ "$(cat /etc/nbh-disposable-guest 2>/dev/null)" = NBH-E05-QEMU-NO-NIC ] || exit 2
[ "$(cat /proc/1/comm)" = procd ] || exit 2
BINARY=/usr/local/libexec/nbh-e05-netbird
PRIVATE=/etc/nbh-e05-agent-private
EVIDENCE=/etc/nbh-e05-agent-evidence
[ -x "$BINARY" ] && [ ! -e "$EVIDENCE" ] || { echo 'Missing public binary or existing evidence: do not replay' >&2; exit 2; }
mkdir -p "$PRIVATE" "$EVIDENCE"
chmod 700 "$PRIVATE" "$EVIDENCE"
# No generated profile, credential or log is ever copied to EVIDENCE.
cat >/usr/local/libexec/nbh-e05-real-agent <<'AGENT'
#!/bin/sh
umask 077
echo $$ >/var/run/e05-real-agent.pid
exec /usr/local/libexec/nbh-e05-netbird --config /etc/nbh-e05-agent-private/profile.json --daemon-addr unix:///var/run/e05-real-agent.sock --management-url https://127.0.0.1:9 --admin-url https://127.0.0.1:9 --log-file /etc/nbh-e05-agent-private/daemon.log --log-level error service run >/etc/nbh-e05-agent-private/console.log 2>&1
AGENT
chmod 755 /usr/local/libexec/nbh-e05-real-agent
cat >/etc/init.d/e05-real-agent <<'INIT'
#!/bin/sh /etc/rc.common
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /usr/local/libexec/nbh-e05-real-agent
    procd_set_param term_timeout 10
    procd_close_instance
}
INIT
chmod 755 /etc/init.d/e05-real-agent
cat >"$EVIDENCE/capture.uc" <<'UCODE'
import { readfile, readlink } from 'fs';
import { run_command } from '/usr/share/netbird/health/runner.uc';
import { atomic_json } from '/usr/share/netbird/health/storage.uc';
let phase=ARGV[0],root='/etc/nbh-e05-agent-evidence';
let pid=trim(readfile('/var/run/e05-real-agent.pid')||'');
let stat=readfile('/proc/'+pid+'/stat');
if(!match(pid,/^[0-9]+$/)||stat==null||readlink('/proc/'+pid+'/exe')!='/usr/local/libexec/nbh-e05-netbird')die('actual NetBird process not observed');
let identity={pid,start_ticks:split(stat,/\s+/)[21],boot_id:trim(readfile('/proc/sys/kernel/random/boot_id'))};
let status=run_command(['/usr/local/libexec/nbh-e05-netbird','--daemon-addr','unix:///var/run/e05-real-agent.sock','status','--json'],15000);
let parsed=null;try{if(status.ok)parsed=json(status.stdout);}catch(e){}
if(parsed==null||type(parsed.daemonStatus)!='string')die('actual daemon status unavailable');
// Only these non-secret state fields leave the private guest process.
let safe_status={daemon_status:parsed.daemonStatus,management_connected:parsed.management?.connected??null,signal_connected:parsed.signal?.connected??null};
if(safe_status.daemon_status=='Connected'||safe_status.management_connected===true)die('offline fixture unexpectedly connected');
let rules=run_command(['/sbin/ip','-j','-4','rule','show'],3000),routes=run_command(['/sbin/ip','-j','-4','route','show','table','all'],3000);
if(!rules.ok||!routes.ok)die('native forwarding snapshot unavailable');
let evidence={phase,identity,status:safe_status,rules:json(rules.stdout),routes:json(routes.stdout),engine:'UNKNOWN',
 limits:['real offline NetBird daemon; NOT a joined Peer','no engine lifecycle API','no real LAN traffic','private profile and all daemon/CLI logs excluded']};
if(phase=='after'){
 let before=json(readfile(root+'/before.json'));
 if(before.identity.boot_id!=identity.boot_id||before.identity.pid==identity.pid)die('daemon-only restart did not change PID within the same boot');
 if(sprintf('%J',[before.rules,before.routes])!=sprintf('%J',[evidence.rules,evidence.routes]))die('offline daemon restart changed forwarding state');
}
if(!atomic_json(root,phase+'.json',evidence))die('evidence publication failed');
printf('%J\n',evidence);
UCODE
ready() {
    i=0
    until [ -S /var/run/e05-real-agent.sock ]; do i=$((i+1)); [ "$i" -lt 25 ] || { echo 'Offline daemon socket unavailable; private logs not exported' >&2; exit 1; }; sleep 1; done
}
"$BINARY" version >"$EVIDENCE/version.txt"
sha256sum "$BINARY" >"$EVIDENCE/binary.sha256"
/etc/init.d/e05-real-agent start
ready
ucode "$EVIDENCE/capture.uc" before >"$EVIDENCE/before.stdout.json"
/etc/init.d/e05-real-agent restart
ready
ucode "$EVIDENCE/capture.uc" after >"$EVIDENCE/after.stdout.json"
/etc/init.d/e05-real-agent stop
ucode -e 'import {readfile} from "fs";let before=json(readfile("/etc/nbh-e05-agent-evidence/after.json"));for(let i=0;i<25;i++){if(readfile("/proc/"+before.identity.pid+"/stat")==null){print("REAL_OFFLINE_NETBIRD_RESTART_SAME_BOOT_NEW_PID_RULES_ROUTES_UNCHANGED=PASS\n");exit(0);}sleep(1000);}die("offline agent exit still unobserved after bounded procd stop wait");'

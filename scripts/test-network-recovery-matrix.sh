#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# DESTRUCTIVE: disposable OpenWrt QEMU guest only. Never run on an appliance.
# The external controller records serial output, reboots the entire guest, then
# invokes after-reboot; a container restart is deliberately insufficient.
set -eu
[ "${NBH_DISPOSABLE_GUEST:-}" = YES ] &&
    [ "$(cat /etc/nbh-disposable-guest 2>/dev/null)" = NBH-E05-QEMU-NO-NIC ] || {
    echo 'Disposable no-NIC guest marker and explicit opt-in required' >&2; exit 2;
}
[ "$(cat /proc/1/comm)" = procd ] || { echo 'Native OpenWrt procd required' >&2; exit 2; }
ROOT=/etc/nbh-e05-matrix
DRIVER=/usr/local/libexec/nbh-e05-network-recovery.uc
phase=${1:-}
case "$phase" in before-reboot|after-reboot) ;; *) echo 'before-reboot|after-reboot required' >&2; exit 2 ;; esac
snapshot() { ucode "$DRIVER" "$1" "$2" > "$ROOT/$1.stdout.json"; }
record() { printf '%s boot=%s uptime=%s %s\n' "$(date -u +%s)" "$(cat /proc/sys/kernel/random/boot_id)" "$(cut -d' ' -f1 /proc/uptime)" "$*" >> "$ROOT/controller.log"; }
links() {
    for dev in e05-lan e05-mesh e05-wan; do
        ip link show dev "$dev" >/dev/null 2>&1 || ip link add "$dev" type bridge
        ip link set "$dev" up
    done
    ip route replace default dev e05-wan
}
rules() {
    ip rule add priority 105 iif e05-lan lookup 9911
    ip rule add priority 110 to 10.40.0.0/16 lookup 9911
}
route() { ip route replace table 9911 10.40.0.0/16 dev e05-mesh; }
if [ "$phase" = before-reboot ]; then
    [ ! -e "$ROOT" ] || { echo 'Existing evidence: do not replay successful matrix' >&2; exit 2; }
    SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    mkdir -p "$ROOT" /usr/local/libexec /usr/share/netbird
    chmod 700 "$ROOT"
    cp -a "$SOURCE/luci-app-netbird/root/usr/share/netbird/." /usr/share/netbird/
    cp "$SOURCE/tests/health/network-recovery.uc" "$DRIVER"
    cp "$0" /usr/local/libexec/nbh-e05-network-recovery.sh
    cat > /usr/local/libexec/nbh-e05-agent <<'AGENT'
#!/bin/sh
# Explicit inert daemon fixture: engine identity remains UNKNOWN.
echo $$ > /var/run/e05-agent.pid
exec sleep 86400
AGENT
    chmod 755 /usr/local/libexec/nbh-e05-agent
    cat > /etc/init.d/e05-agent <<'INIT'
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /usr/local/libexec/nbh-e05-agent
    procd_set_param respawn
    procd_close_instance
}
INIT
    chmod 755 /etc/init.d/e05-agent
    /etc/init.d/e05-agent enable
    /etc/init.d/e05-agent start
    sleep 1
    ip -ts monitor rule route link >> "$ROOT/kernel-events-before.log" 2>&1 &
    echo $! > "$ROOT/event-monitor.pid"
    links
    rules
    route
    ip rule add priority 12100 to 198.51.100.0/24 lookup 9911
    record 'initial temporary rules installed; control-plane Connected is fixture only'
    snapshot baseline green
    record 'begin actual netifd network restart; no claim that it deletes unowned rules'
    /etc/init.d/network restart
    sleep 2
    snapshot network_restart unknown
    record 'completed actual network restart'
    # netifd may remove temporary rules. Restore a known baseline before the
    # independent daemon-only scenario; do not misattribute the earlier loss.
    ip rule del priority 105 2>/dev/null || true
    ip rule del priority 110 2>/dev/null || true
    ip rule del priority 12100 2>/dev/null || true
    rules
    route
    ip rule add priority 12100 to 198.51.100.0/24 lookup 9911
    record 'controller restored owned temporary rules after network-only scenario'
    snapshot network_restored green
    /etc/init.d/e05-agent restart
    sleep 1
    snapshot agent_restart green
    record 'completed inert procd daemon restart; NOT NetBird engine restart'
    ip rule del priority 105
    ip rule del priority 110
    record 'controller deliberately deleted owned rules105/110 while guest/daemon remained running'
    snapshot rules_deleted red
    ip route del table 9911 10.40.0.0/16
    rules
    record 'Connected fixture and query rules restored before table route'
    snapshot control_connected_structure_missing red
    route
    snapshot structure_restored green
    record 'source/iif lookup GREEN; actual business/user LAN remains unverified'
    snapshot before_boot green
    sync
    echo 'BEFORE_REBOOT_COMPLETE: externally reboot the whole guest; do not rerun this phase'
else
    [ -f "$ROOT/before_boot.json" ] && [ ! -f "$ROOT/after_boot.json" ] || {
        echo 'Missing prerequisite or already completed: do not replay' >&2; exit 2;
    }
    ip -ts monitor rule route link >> "$ROOT/kernel-events-after.log" 2>&1 &
    echo $! > "$ROOT/event-monitor.pid"
    # Recreate only the isolated links/default route, NOT any query/user rule.
    links
    record 'new kernel started; observation gap spans reboot; temporary rules were not persisted'
    snapshot after_boot red
    rules
    route
    snapshot reboot_structure_restored green
    record 'controller reinstalled owned query rules/route; engine lifecycle and real LAN UNKNOWN'
    sync
    echo 'AFTER_REBOOT_COMPLETE'
fi

#!/bin/sh
# Disposable install -> upgrade -> rollback -> re-upgrade -> remove check inside an
# official openwrt/rootfs container. Usage: sh test-package-upgrade.sh opkg|apk
# Expects /pkgs/{old,new}/ packages and /src (package source tree for SHA comparison).
# Exits non-zero when one of the FAIL checks below trips (count of failures).
set -u
PM=$1
say() { echo "== $*"; }
fail=0
bad() { echo "FAIL: $*"; fail=$((fail+1)); }
# Stub /etc/init.d/rpcd so the post-install restart can be observed in a container
# without procd: records when it ran and in which session.
RPCD_MARK=/tmp/nbtest-rpcd-restart
stub_rpcd() {
  [ -e /tmp/nbtest-rpcd.init.orig ] || cp -p /etc/init.d/rpcd /tmp/nbtest-rpcd.init.orig 2>/dev/null || :
  cat > /etc/init.d/rpcd <<'EOF'
#!/bin/sh
[ "$1" = restart ] || exit 0
read -r _ _ _ _ _ sid _ < /proc/self/stat
echo "$(date +%s) $sid" >> /tmp/nbtest-rpcd-restart
EOF
  chmod 0755 /etc/init.d/rpcd
  rm -f "$RPCD_MARK"
}
restore_rpcd() { [ -e /tmp/nbtest-rpcd.init.orig ] && cp -p /tmp/nbtest-rpcd.init.orig /etc/init.d/rpcd || rm -f /etc/init.d/rpcd; }
postinst_text() {
  if [ "$PM" = opkg ]; then cat /usr/lib/opkg/info/luci-app-netbird.postinst /usr/lib/opkg/info/luci-app-netbird.postinst-pkg 2>/dev/null; return; fi
  for s in /lib/apk/db/scripts.tar*; do [ -e "$s" ] || continue; tar -xOf "$s" 2>/dev/null || tar -xzOf "$s" 2>/dev/null; done
}
read -r _ _ _ _ _ MYSID _ < /proc/$$/stat
h() { sha256sum "$1" 2>/dev/null | cut -c1-16; }
KEY="usr/share/rpcd/ucode/netbird.uc usr/share/netbird/netbird-autoreconnect.sh usr/share/netbird/health/collect.uc usr/share/netbird/health/maintenance.uc usr/share/netbird/health/boundary.uc etc/uci-defaults/99-luci-app-netbird"
ver() { if [ "$PM" = opkg ]; then opkg list-installed | grep -E '^luci-(app|i18n)-netbird'; else apk list -I 2>/dev/null | grep -E '^luci-(app|i18n)-netbird'; fi; }
mkdir -p /var/lock /var/run /tmp/lock
if [ "$PM" = opkg ]; then
  say update; opkg update >/tmp/u.log 2>&1; echo "update rc=$? failed_feeds=$(grep -c -i -E 'failed|error' /tmp/u.log)"; grep -i -E 'failed|error' /tmp/u.log | head -3
  say install-old; opkg install /pkgs/old/*.ipk >/tmp/i1.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|collected|configuring luci' /tmp/i1.log | head -8
else
  say update; apk update >/tmp/u.log 2>&1; echo "update rc=$? $(tail -1 /tmp/u.log)"
  say install-old; apk add --allow-untrusted /pkgs/old/*.apk >/tmp/i1.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|warn|luci-app-netbird|luci-i18n' /tmp/i1.log | head -8
fi
ver
uci -q set netbird.settings.nbtest_marker=keep-me && uci -q commit netbird; echo "marker_set=$(uci -q get netbird.settings.nbtest_marker)"
for f in $KEY; do echo "old $f $(h /$f)"; done
say upgrade-new
stub_rpcd
t0=$(date +%s)
if [ "$PM" = opkg ]; then opkg install /pkgs/new/*.ipk >/tmp/i2.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|upgrading|collected' /tmp/i2.log | head -8
else apk add --allow-untrusted /pkgs/new/*.apk >/tmp/i2.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|warn|upgrad|luci-app-netbird|luci-i18n' /tmp/i2.log | head -8; fi
t1=$(date +%s)
early=no; [ -s "$RPCD_MARK" ] && early=yes
ver
say postinst-rpcd-restart
# The restart must run after the installer (and update_luci_app) has returned, in
# its own session, and replace rpcd instead of re-executing it with SIGHUP.
sleep 8
restarts=$(grep -c . "$RPCD_MARK" 2>/dev/null); restarts=${restarts:-0}
read -r rt rsid < "$RPCD_MARK" 2>/dev/null || { rt=; rsid=; }
echo "install took $((t1-t0))s restarts=$restarts before_return=$early delay=${rt:+$((rt-t1))}s sid=$rsid installer_sid=$MYSID"
[ "$restarts" = 1 ] || bad "expected exactly one delayed rpcd restart, got $restarts"
[ "$early" = no ] || bad 'rpcd restart ran before the installer returned'
[ -n "$rt" ] && [ $((rt-t0)) -ge 4 ] || bad 'rpcd restart was not delayed by ~5s'
[ -n "$rsid" ] && [ "$rsid" != "$MYSID" ] || bad 'rpcd restart did not leave the installer session'
postinst_text | grep -q 'killall -HUP rpcd' && bad 'postinst still sends HUP to rpcd'
postinst_text | grep -q '/etc/init.d/rpcd restart' || bad 'postinst has no rpcd restart'
say lib-load-once
# Each compiled source keeps one fd open on ucode builds without upstream 1dd1f88c81
# (24.10, 25.12); the rpcd object must compile every lib file at most once.
cat > /tmp/nbtest-fds.uc <<'EOF'
import { lsdir, readlink } from 'fs';
let api = loadfile('/usr/share/rpcd/ucode/netbird.uc')();
let n = {}, worst = 0;
for (let f in lsdir('/proc/self/fd')) {
    let t = readlink('/proc/self/fd/' + f);
    if (t && match(t, /\/usr\/share\/rpcd\/ucode\/lib\//)) { n[t] = (n[t] || 0) + 1; worst = max(worst, n[t]); }
}
let st = api['luci.netbird'] ? 'object ok' : 'object missing';
print(sprintf('%s worst=%d %J\n', st, worst, n));
exit(st == 'object ok' && worst <= 1 ? 0 : 1);
EOF
ucode /tmp/nbtest-fds.uc || bad 'netbird.uc loads a lib file more than once (or did not load)'
for f in $KEY; do echo "new $f $(h /$f) src $(h /src/luci-app-netbird/root/$f)"; done
echo "marker_after=$(uci -q get netbird.settings.nbtest_marker)"
echo "binary_source=$(uci -q get netbird_bin.binary.binary_source)"
echo "sysupgrade.conf:"; grep -E 'netbird' /etc/sysupgrade.conf | sed 's/^/  /'
echo "uci-defaults left: $(ls /etc/uci-defaults 2>/dev/null | grep -c netbird)"
for i in /etc/init.d/luci-netbird-watchdog /etc/init.d/netbird-settings /etc/init.d/luci-netbird-health /etc/init.d/luci-netbird-recover /etc/init.d/luci-netbird-updater; do [ -e $i ] && echo "init $i mode=$(ls -l $i | cut -c1-10)"; done
echo "watchdog mode=$(ls -l /usr/share/netbird/netbird-autoreconnect.sh 2>/dev/null | cut -c1-10)"
ucode -c -o /dev/null /usr/share/rpcd/ucode/netbird.uc 2>/dev/null; echo "netbird.uc compile rc=$? (rc!=0 may mean -c unsupported)"
ls /usr/share/rpcd/ucode/ | grep -c -E '\.bak' | sed 's/^/rpcd bak files: /'
say rollback-old
if [ "$PM" = opkg ]; then opkg install --force-downgrade /pkgs/old/*.ipk >/tmp/i3.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|downgrad' /tmp/i3.log | head -6
else apk add --allow-untrusted /pkgs/old/*.apk >/tmp/i3.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|warn|downgrad|luci-app-netbird|luci-i18n' /tmp/i3.log | head -6; fi
ver
for f in $KEY; do echo "rb $f $(h /$f)"; done
echo "marker_rb=$(uci -q get netbird.settings.nbtest_marker) binary_source=$(uci -q get netbird_bin.binary.binary_source)"
echo "uci-defaults left: $(ls /etc/uci-defaults 2>/dev/null | grep -c netbird)"
ucode -c -o /dev/null /usr/share/rpcd/ucode/netbird.uc 2>/dev/null; echo "netbird.uc compile rc=$?"
ls /usr/share/rpcd/ucode/ | grep -c -E '\.bak' | sed 's/^/rpcd bak files: /'
say re-upgrade-new
if [ "$PM" = opkg ]; then opkg install /pkgs/new/*.ipk >/tmp/i4.log 2>&1; echo "rc=$?"
else apk add --allow-untrusted /pkgs/new/*.apk >/tmp/i4.log 2>&1; echo "rc=$?"; fi
ver
echo "netbird.uc $(h /usr/share/rpcd/ucode/netbird.uc) marker=$(uci -q get netbird.settings.nbtest_marker)"
restore_rpcd
say remove
if [ "$PM" = opkg ]; then opkg remove luci-i18n-netbird-zh-cn luci-app-netbird >/tmp/r.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail' /tmp/r.log | head -5
else apk del luci-i18n-netbird-zh-cn luci-app-netbird >/tmp/r.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail' /tmp/r.log | head -5; fi
ver | sed 's/^/still: /'
left=0; for f in $KEY; do [ -e /$f ] && { echo "left /$f"; left=$((left+1)); }; done; echo "key files left=$left"
echo "config kept: $( [ -f /etc/config/netbird ] && echo yes || echo no) marker=$(uci -q get netbird.settings.nbtest_marker)"
echo "failures=$fail"
exit "$fail"

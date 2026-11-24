#!/bin/sh
# Disposable install -> upgrade -> rollback -> re-upgrade -> remove check inside an
# official openwrt/rootfs container. Usage: sh test-package-upgrade.sh opkg|apk
# Expects /pkgs/{old,new}/ packages and /src (package source tree for SHA comparison).
set -u
PM=$1
say() { echo "== $*"; }
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
if [ "$PM" = opkg ]; then opkg install /pkgs/new/*.ipk >/tmp/i2.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|upgrading|collected' /tmp/i2.log | head -8
else apk add --allow-untrusted /pkgs/new/*.apk >/tmp/i2.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail|warn|upgrad|luci-app-netbird|luci-i18n' /tmp/i2.log | head -8; fi
ver
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
say remove
if [ "$PM" = opkg ]; then opkg remove luci-i18n-netbird-zh-cn luci-app-netbird >/tmp/r.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail' /tmp/r.log | head -5
else apk del luci-i18n-netbird-zh-cn luci-app-netbird >/tmp/r.log 2>&1; echo "rc=$?"; grep -i -E 'error|fail' /tmp/r.log | head -5; fi
ver | sed 's/^/still: /'
left=0; for f in $KEY; do [ -e /$f ] && { echo "left /$f"; left=$((left+1)); }; done; echo "key files left=$left"
echo "config kept: $( [ -f /etc/config/netbird ] && echo yes || echo no) marker=$(uci -q get netbird.settings.nbtest_marker)"

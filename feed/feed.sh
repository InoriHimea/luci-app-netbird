#!/bin/sh
# luci-app-netbird — add the signed package feed (opkg or apk).
# Usage:  wget -O - https://luci-app-netbird.okk.sh/feed.sh | sh
set -e

REPO="https://luci-app-netbird.okk.sh"
NAME="netbird"

if [ ! -x /bin/opkg ] && [ ! -x /usr/bin/apk ]; then
	echo "This needs OpenWrt/ImmortalWrt with opkg or apk." >&2
	exit 1
fi

# branch by release; the package is arch-independent (PKGARCH:=all)
. /etc/openwrt_release
case "$DISTRIB_RELEASE" in
	*24.10*) BRANCH="openwrt-24.10" ;;
	*25.12*) BRANCH="openwrt-25.12" ;;
	*) echo "Unsupported release: $DISTRIB_RELEASE (supported: 24.10, 25.12)." >&2; exit 1 ;;
esac
FEED="$REPO/$BRANCH/all/$NAME"

if [ -x /bin/opkg ]; then
	echo "Adding opkg feed..."
	wget -O /tmp/netbird-key.pub "$REPO/key-build.pub"
	opkg-key add /tmp/netbird-key.pub
	rm -f /tmp/netbird-key.pub
	sed -i "\\#$REPO#d" /etc/opkg/customfeeds.conf
	echo "src/gz $NAME $FEED" >> /etc/opkg/customfeeds.conf
	opkg update
else
	echo "Adding apk feed..."
	wget -O /etc/apk/keys/luci-app-netbird.pem "$REPO/public-key.pem"
	mkdir -p /etc/apk/repositories.d
	LIST=/etc/apk/repositories.d/customfeeds.list
	[ -f "$LIST" ] && sed -i "\\#$REPO#d" "$LIST"
	echo "$FEED/packages.adb" >> "$LIST"
	apk update
fi

echo "Feed added: $FEED"
echo "Install:  opkg install luci-app-netbird luci-i18n-netbird-zh-cn"
echo "    (apk: apk add luci-app-netbird luci-i18n-netbird-zh-cn)"

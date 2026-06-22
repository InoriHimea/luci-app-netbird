#!/bin/sh
# luci-app-netbird — remove the packages, the feed entry, and the signing key.
# NetBird itself (the `netbird` package) and its config/identity are left untouched.
# Usage:  wget -O - https://luci-app-netbird.okk.sh/uninstall.sh | sh

REPO="https://luci-app-netbird.okk.sh"

if [ -x /bin/opkg ]; then
	opkg remove luci-i18n-netbird-zh-cn luci-app-netbird 2>/dev/null
	sed -i "\\#$REPO#d" /etc/opkg/customfeeds.conf 2>/dev/null
	opkg update 2>/dev/null
elif [ -x /usr/bin/apk ]; then
	apk del luci-i18n-netbird-zh-cn luci-app-netbird 2>/dev/null
	sed -i "\\#$REPO#d" /etc/apk/repositories.d/customfeeds.list 2>/dev/null
	rm -f /etc/apk/keys/luci-app-netbird.pem
fi

echo "Removed luci-app-netbird and its feed. NetBird and your settings are untouched."
echo "To use NetBird in the LuCI Network/Firewall, remove its zone from the Network tab first."

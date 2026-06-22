#!/bin/sh
# luci-app-netbird — one-click install (adds the feed, then installs the app + zh i18n).
# Usage:  sh -c "$(curl -fsSL https://luci-app-netbird.okk.sh/install.sh)"
#    or:  wget -O - https://luci-app-netbird.okk.sh/install.sh | sh
set -e

REPO="https://luci-app-netbird.okk.sh"

# add the feed
wget -O - "$REPO/feed.sh" | sh

# install app + Simplified Chinese language pack
if [ -x /bin/opkg ]; then
	opkg install luci-app-netbird luci-i18n-netbird-zh-cn
else
	apk add luci-app-netbird luci-i18n-netbird-zh-cn
fi

echo ""
echo "Done. Open LuCI -> Services -> NetBird."

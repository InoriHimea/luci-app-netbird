#!/bin/sh
# luci-app-netbird — one-click install (adds the feed, then installs the app).
# Usage:  sh -c "$(curl -fsSL https://luci-app-netbird.okk.sh/install.sh)"
#    or:  wget -O - https://luci-app-netbird.okk.sh/install.sh | sh
set -e

REPO="https://luci-app-netbird.okk.sh"

# add the feed
wget -O - "$REPO/feed.sh" | sh

# install the app
if [ -x /bin/opkg ]; then
	opkg install luci-app-netbird
else
	apk add luci-app-netbird
fi

echo ""
echo "Done. Open LuCI -> Services -> NetBird."

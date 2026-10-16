#!/bin/sh
# luci-app-netbird — one-click install (adds the feed, then installs the app).
# Usage:  sh -c "$(curl -fsSL https://luci-app-netbird.okk.sh/install.sh)"
#    or:  wget -O - https://luci-app-netbird.okk.sh/install.sh | sh
set -e

REPO="https://luci-app-netbird.okk.sh"

# add the feed. Download feed.sh to a file first: with `wget | sh` a failed download
# feeds sh empty input, which exits 0, and installation would continue without the feed.
FEED_SH="$(mktemp)"
trap 'rm -f "$FEED_SH"' EXIT
if command -v wget >/dev/null 2>&1; then
	wget -O "$FEED_SH" "$REPO/feed.sh"
else
	curl -fsSL -o "$FEED_SH" "$REPO/feed.sh"
fi
[ -s "$FEED_SH" ] || { echo "Could not download $REPO/feed.sh" >&2; exit 1; }
sh "$FEED_SH"

# install the app
if [ -x /bin/opkg ]; then
	opkg install luci-app-netbird
else
	apk add luci-app-netbird
fi

echo ""
echo "Done. Open LuCI -> Services -> NetBird."

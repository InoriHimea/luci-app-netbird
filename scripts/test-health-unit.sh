#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Run tests/health/run.sh --unit in a disposable, isolated OpenWrt container.
#
# Usage (on a Linux Docker host, from the repository root or with SRC set):
#   IMAGE=<openwrt image with ucode fs/uci/socket modules> sh scripts/test-health-unit.sh
#
# The image must provide ucode with fs, uci and socket modules (the bare
# openwrt/rootfs image lacks socket, so probe.uc cannot run there).
# settings.uc validates against the shipped schema at its installed path, so the
# schema is staged at /usr/share/netbird/health/config.schema.json inside the
# container only. Nothing is installed on the host; the container has no
# network, no capabilities and is removed afterwards.
set -eu
IMAGE=${IMAGE:?set IMAGE to an OpenWrt image with ucode fs/uci/socket}
SRC=${SRC:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
NAME=nbh-unit-$$-$(date +%s)
STAGE=$(mktemp -d)
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$STAGE"; }
trap cleanup EXIT INT TERM
tar -C "$SRC" -cf - luci-app-netbird tests | tar -C "$STAGE" -xf -
# Windows checkouts may carry CRLF; the OpenWrt shell and ucode need LF.
grep -rlI "$(printf '\r')" "$STAGE" | xargs -r sed -i 's/\r$//'
docker create --name "$NAME" --network none --cap-drop ALL --security-opt no-new-privileges \
    --memory 128m --cpus 0.5 --pids-limit 64 --entrypoint sh "$IMAGE" -c '
        mkdir -p /usr/share/netbird/health &&
        cp /tmp/src/luci-app-netbird/root/usr/share/netbird/health/config.schema.json /usr/share/netbird/health/ &&
        sh /tmp/src/tests/health/run.sh --unit' >/dev/null
docker cp "$STAGE/." "$NAME:/tmp/src" >/dev/null
docker start -a "$NAME"

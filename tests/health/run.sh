#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
case "${1:---unit}" in
    --unit) ;;
    *) echo 'Usage: sh tests/health/run.sh --unit' >&2; exit 2 ;;
esac
command -v ucode >/dev/null 2>&1 || { echo 'ucode is required; run in an isolated OpenWrt environment.' >&2; exit 1; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ucode "$ROOT/tests/health/model.uc"
ucode "$ROOT/tests/health/fixtures.uc" "$ROOT"/tests/health/fixtures/A*.json
ucode "$ROOT/tests/health/runner.uc"
ucode "$ROOT/tests/health/parsers.uc" "$ROOT/tests/health/fixtures"
ucode "$ROOT/tests/health/collector.uc" "$ROOT/tests/health/fixtures"
ucode -L "$ROOT/luci-app-netbird/root/usr/share/*.uc" "$ROOT/tests/health/evaluate.uc"
ucode "$ROOT/tests/health/lookup.uc"

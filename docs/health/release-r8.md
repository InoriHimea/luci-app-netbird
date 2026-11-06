# T08 local package delivery: 0.2.0-r8

Local-only delivery. No push, tag, remote CI, public release or production deployment is authorized or performed by this record. Code/API compatibility does not open the node56/DC rollout gate.

## Reproducible build provenance

Both standard OpenWrt SDK builds completed with exit0 as unprivileged `nobody` on the existing development host. The package Makefile was `PKG_VERSION=0.2.0`, `PKG_RELEASE=8`; health source followed T07 commit `4b3ee2b`. The final T08 source commit and exact-range bundle are recorded in the delivered asset manifest after that commit, avoiding a self-referential commit hash in this document.

| Input | Verified identity |
|---|---|
| OpenWrt25.12.2 x86_64 SDK | SHA256 `4abb32a6dd05f80c24fc1a487a94b1f5f0a5d4cd560ff3dd8c1bf77793a2d5dc` |
| OpenWrt24.10.5 x86_64 SDK | SHA256 `d3e8ea62fc1c12f93a9c808c2ef4c01b6e149ee240bcd5a74d15bebcbc385bdd` |
| 25.12 LuCI feed | `067535eaf51a59582b775a8b588a9b05810f8030` |
| 24.10 LuCI feed | `d88390be4ec9722cb427fee03368fc8c8582627d` |
| 25.12 base feed | `d266501ad6188cce279a487b1ce61f4f327cd496` |
| 24.10 base feed | SDK-pinned tag `v24.10.5` |

Official SDK archives were fetched through mirrors only after matching official SHA256. Complete feed archives came from the official GitHub API at the SDK pins; partial server-side downloads were never extracted. Local pinned feeds were indexed with `scripts/feeds update -i base luci netbird`; normal feed installation selected Lua host support, LuCI host support and this package. Builds used `make defconfig CONFIG_PACKAGE_luci-app-netbird=m CONFIG_LUCI_LANG_zh_Hans=y` and `make -j2 package/luci-app-netbird/compile V=s CONFIG_PACKAGE_luci-app-netbird=m CONFIG_LUCI_LANG_zh_Hans=y`.

The CentOS9 build host lacked ncurses development headers. A matching `ncurses-devel-6.2-12.20210508.el9.x86_64.rpm` was signature/digest checked with the host's existing RPM trust, then extracted only inside the private SDK workspace; no host RPM was installed. RPM SHA256: `b8cadf3cfef76ce367666cf45303f648a1780c8ef381176fd1365fe74026dc35`. SDK prerequisites intentionally unexport `C_INCLUDE_PATH`; the successful build used private `CPATH` and `LIBRARY_PATH`, not `FORCE=1` or a bypass of the required host tools. The initial root-owned new feeds parent was corrected to the build user's ownership. Existing compiler warnings in Lua/csstidy were not represented as package failures or silently patched.

## New package hashes

| Asset | Bytes | SHA256 |
|---|---:|---|
| luci-app-netbird-0.2.0-r8.apk | 184652 | `a91a0d895df7a3da7d157c03c8d48122e92f12e4a7e126f7c22b2543229db36b` |
| luci-i18n-netbird-zh-cn-0.2.0-r8.apk | 12692 | `066abf95ca9c4d68d92e34799bdb16f446f15e617798bfdde3fd4326a113f84c` |
| luci-app-netbird_0.2.0-r8_all.ipk | 183868 | `7bc18679994937ed3e9873ebe45ec1cbb7a9b3256f3b9ea2cfc4cec001ef5e84` |
| luci-i18n-netbird-zh-cn_0.2.0-r8_all.ipk | 12816 | `b18e9603d75f51e9a6638630937d31f694dab9a19e17830a6c62496c7f81126e` |

The architecture-independent package was built by the actual SDK for each package format; these are not the earlier source-assembled fixture APKs. The APK's 28 installed health files were verified both package-owned and byte-equal to LF-normalized source. Its actual installed run passed the strict result schema in AJV.

**Signing gate remains closed.** Actual native verification of the new main APK against this repository's public key returned exit1, `UNTRUSTED signature`. The isolated acceptance used `--allow-untrusted`; this is not a production installation recommendation. SDK-local signing material is neither delivered nor installed as a new trust root. No inherited repository/feed key was rotated. SHA256 and a successful SDK build do not establish a trusted signed feed.

## Actual isolated lifecycle and migration

Dedicated OpenWrt25.12.2 container: network none, all capabilities dropped except NET_ADMIN solely for an owned priority12100 test rule, 128MiB/0.5CPU/64PID, init reaper and real ubusd/procd/rpcd. Six explicitly synthetic identity/init/watchdog/user-configuration sentinels plus the original firewall file were protected. No real NetBird key, engine, Mesh or LAN session was used.

- The new fixture initially lacked conntrack dependencies and `/var/lock`; these were environment prerequisites, not successful installs. Official offline dependencies were staged. Their kernel-module packages were installed **with `--no-scripts`**, solely as files/metadata; no attempt was made to load modules into the host kernel. Application-package lifecycle scripts ran normally. This does not verify the target OpenWrt kernel or conntrack enforcement.
- Actual r8 fresh install succeeded. New health config had monitor=false, no paths/endpoints, owner=central, no sink and no reminders. Central ownership alone did not enable notification delivery.
- Native independent settings enabled only the isolated monitor, empty targets and owner=none. The actual packaged supervisor ran under procd and produced a schema-valid UNKNOWN run.
- Actual r8→published-r7 rollback succeeded; health registration/workers retired, seven preservation comparisons passed and actual12100 remained. No synthetic daemon-init action was recorded.
- Actual r7→SDK-r8 upgrade succeeded and retained the existing approved health config revision1, enabled state and owner=none. Native apk kept incoming defaults in `.apk-new`; it did not silently reset a configured monitor to defaults.
- Direct current-r8 removal succeeded; no health registration/worker remained and all seven comparisons plus12100 preservation passed.
- Actual main+Chinese r8 paired installation produced the package-owned `netbird.zh-cn.lmo`. A Python control-kernel timeout interrupted paired cleanup; read-only reconciliation found both packages still installed and no APK process. The confirmed-unfinished paired removal then completed exit0; final native service/process/rule evidence was captured. No successful package operation was blindly replayed.

`lifecycle-receipts.json` in the delivered directory contains final original receipts and explicitly distinguishes pre-timeout verified assertions from unavailable raw buffers. Complete compiler stdout and the initial raw digest buffer were lost with that control-kernel exit; no fabricated reconstruction is supplied. Canonical tool history records the successful SDK exit0 receipts and preservation assertions.

Five current-source legacy regressions also completed exit0 in separate fresh network-none/cap-drop-ALL disposable containers: `test-agent-update.sh`, `test-binary-and-app-update.sh`, `test-timeout.sh`, `test-autoreconnect-signal.sh` and `test-rpcd-backup-migration.sh`. Their original output is delivered as `legacy-regression.txt`; injected SIGKILL cases account for the two expected `Killed` stderr lines. All five containers were removed. These deterministic client/package-manager fixtures are not production updater or VPN acceptance.

## Rollback selection and evidence bundle

The delivery directory includes published r7 main and Chinese packages for both APK/IPK, with their hashes in the manifest. Select the existing platform's package format and preserve the set of installed languages; do not introduce/remove a language just to perform a rollback. Published r7 main APK SHA256 is `4cd1a64456ae6ac4b1e51e89b82c5da46b6095838a6f0ec7ed6b6612370c3cf7`; r7 main IPK SHA256 is `3edaa759b2f446523cb797d33ac15fe6e20a9b003104a3717941c2512575bfd2`. Downloaded rollback assets were checked against the public GitHub release digest where fetched during T08. APK signing trust remains a separate unresolved gate for rollback as well.

Before any authorized appliance upgrade/rollback, retain a root-private backup of independent health UCI, existing NetBird identity/configuration/custom init/watchdog and network/firewall/user routing. A package rollback is not a daemon upgrade or a VPN recovery procedure. Preserve emergency12100; removing it requires a separate approved change and business regression. r7 has no health feature, so missing health UI/service after rollback is expected, not proof that networking is healthy. Health config was retained in the exercised APK rollback/re-upgrade; platform-specific conffile behavior must still be verified before relying on that behavior elsewhere.

The explicit Git bundle range is the recorded pre-development base `953e4b2e760fe436b80330f600dd29a9e3bfc8d9` through the final T08 commit, not all branches or unrelated history. Asset manifests record the exact base, tip, file SHA256 and package-source commit. Credentials, signing private keys, SDK workspaces and unrelated/user README modifications do not belong in that bundle.

See [acceptance.md](acceptance.md), [performance.md](performance.md), [contracts.md](contracts.md), [result.schema.json](result.schema.json) and [baseline.md](baseline.md) for complete case denominators, permissions/schema/error/migration boundaries and prior actual UI/HTTP evidence. OpenWrt24.10 runtime/IPK installation, minimum target hardware, physical reboot, real engine reconnect, real LAN/security-policy traffic and production notification receipt remain NOT_RUN. No public release or production rollout is implied.

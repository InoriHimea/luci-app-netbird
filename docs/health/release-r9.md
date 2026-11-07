# E05 local package delivery: 0.2.0-r9

Local-only delivery of the E01–E05 recovery work and A25–A32 evidence. No push, tag, remote CI, public release, production fault or automatic rollout is authorized or performed. Frozen [r8 delivery](release-r8.md) assets and its A01–A24 denominator are unchanged.

## Build provenance

The retained official OpenWrt24.10.5 and25.12.2 x86_64 SDKs both build as `nobody`, exit0, with the same pinned LuCI/base feeds and signature-checked private ncurses prerequisites documented for r8. No host RPM is installed and no prerequisite check is bypassed. Existing r8 feed source directories are retained separately before staging current package inputs; no SDK private signing material is read or delivered.

Runtime source is local commit `412befd` plus the package release increment to9; E05 adds regression/evidence documentation without changing those runtime files. The LF-normalized package input tar SHA256 is `6a11ff103dfd4dc3f97047b700f3ee8ee1f6336858cfd8492c03037ac32912ba`. Build command for each SDK:

```sh
CPATH=<private-ncurses>/usr/include \
LIBRARY_PATH=<private-ncurses>/usr/lib64 \
make -j2 package/luci-app-netbird/compile V=s \
  CONFIG_PACKAGE_luci-app-netbird=m CONFIG_LUCI_LANG_zh_Hans=y
```

`PKG_VERSION=0.2.0`, `PKG_RELEASE=9`, and the Chinese subpackage follows `0.2.0-r9`. Final source commit, exact bundle range and delivery-archive hashes are recorded in the generated delivery manifest after the documentation commit; this avoids a self-referential source hash.

## New asset hashes

| Asset | Bytes | SHA256 |
|---|---:|---|
| luci-app-netbird-0.2.0-r9.apk | 210028 | `67237b34a560cce053b53828ebb28f0874fad8fa6b1b5f42f5d09438969813a9` |
| luci-i18n-netbird-zh-cn-0.2.0-r9.apk | 12693 | `cd5e5af906b0990801e4d51706f775374a2b50f15215a75a52bafe23fbd5a12b` |
| luci-app-netbird_0.2.0-r9_all.ipk | 208669 | `67f676121c252b0bff12968830fb5fcff56bd13ef4c4b672eb90844b4c0dca26` |
| luci-i18n-netbird-zh-cn_0.2.0-r9_all.ipk | 12817 | `ff5367bc1ed969e3c943099cf4f33d8eea2cc6c66a09b6ea4fa5441c33668803` |

The separate local delivery directory also contains copies of all four frozen r8 rollback packages. Originals remain untouched; their hashes are included in the manifest. The bundle range starts at the recorded pre-development base `953e4b2e760fe436b80330f600dd29a9e3bfc8d9`, not every branch or unrelated history. Uncommitted user README changes, SDKs, credentials, generated agent identity and signing private keys are excluded.

**Signing gate stays closed.** Native verification of the new r9 APK returns exit1, `UNTRUSTED signature`, using the isolated system's existing trusted keys. Isolated lifecycle tests explicitly use `--allow-untrusted`; no new trust root is installed. File hashes, a successful SDK build and the signed Alpine QEMU dependencies do not establish trusted signing for these application APKs.

## Actual OpenWrt25.12 package lifecycle

An owned network-none namespace uses the retained native OpenWrt image, real apk/ubusd/rpcd/procd and native package scripts. Its initial filesystem has old unregistered fixture files/cache; this is fresh **package registration**, not a claim of a pristine factory filesystem. Kernel dependencies are staged with `--no-scripts`, without loading modules into the host. Own namespace NET_ADMIN permits only its test12100 rule; there is no host-network attachment.

Observed operations:

- Paired main/Chinese r9 installation exits0. All43 health files are both package-owned and equal to the normalized current source.
- Native `get_automatic` returns OFF. The independent approved health configuration is saved to revision1, monitor enabled only inside the fixture, owner none and no active probe destinations.
- Paired r9→r8 downgrade exits0; the approved health configuration SHA256 is unchanged. Existing `service_enabled=0` and `desired_connected=0` are retained.
- Paired r8→r9 upgrade exits0. The approved health configuration, all seven post-migration protected-file SHA256 values and automatic OFF are retained; source equality is rechecked.
- Paired r9 removal exits0. Health registration/owned workers drain, actual12100 and protected files are unchanged, and the custom NetBird init recorder has zero actions. Removal of the Chinese `.lmo` is native package management, not a runtime language mock.
- A separate installed-r9 publication smoke retires the old fixture cache before starting the actual packaged supervisor. It creates a new schema1 result bound to node `e05-packaged-smoke`, overall UNKNOWN. Current strict AJV validation returns true with no errors. Publication-smoke paired removal also exits0; the final native service registry is empty.

Negative observations are retained, not hidden:

- The minimal pre-install `netbird` fixture lacks legacy default options. Normal default migration appends those options, so its original whole-file SHA does change; six other original hashes pass and both existing values stay0. Seven-file byte preservation is asserted only after this migration, across the subsequent upgrade/removal. This is not a claim that the initially incomplete file was byte-identical.
- Manually launched rpcd needs an explicit native HUP to load the installed object, as opposed to a managed production init service. An initial getter used the wrong envelope level; the observed contract is `data.automatic.enabled` and no consent/configuration write occurred before correction.
- An initial existing `latest.json` was old fixture data and is **not** accepted as a current-package publication. Only the fresh node/schema-bound run and AJV result count.
- The detached APK world-normalization helper attempted unavailable offline repositories. Network-none prevented external access; only its identified unfinished offline helper was terminated, and repository directories were retired inside the fixture. Online repository/world-normalization behavior is not claimed as tested.

## A25–A32 and restoration

[acceptance.md](acceptance.md) retains A01–A24 and names each supplemental verified layer. [baseline.md](baseline.md) records native convergence, manual/automatic guards and concurrency, plus the new full-system reboot, live rule deletion, network restart and actual offline NetBird daemon restart.

Whole-guest reboot really changes the kernel boot ID and removes unpersisted105/110/12100. Running deletion does not change boot/daemon identity. The controller's explicit delete/reboot actions are known interventions; ordinary kernel event text and a network-restart window do not identify a deleting process. Engine identity stays UNKNOWN. Restored source/iif forwarding leaves router/LAN/business obligations UNKNOWN rather than declaring real-user LAN recovery.

The actual NetBird0.77.0 process test uses only a public static executable with SHA256 `c9422437519047db0c122030abb5ebc0a26b2774d6bcc599e739cbfc6e5d2406`. It is unregistered, uses a private profile/log directory and loopback-only management inside the no-NIC guest, and has management/signal false. Its changed PID within the same boot and unchanged rules/routes are real process observations, not a connected VPN/engine reconstruction proof. The corrected permanent entrypoint waits for native asynchronous stop and exits0. No generated profile or daemon/CLI log leaves the guest; its identity-bearing disk is removed after poweroff.

## Remaining gates

OpenWrt24.10 **IPK runtime installation**, physical appliance power loss, connected NetBird engine reconstruction, real Wuhan LAN/receiver ACL, production notification receipt and minimum-hardware sizing remain NOT_RUN. E05 does not close the separate T09 real-topology task. Node56's first actual scheduled update plus functional acceptance still gates every later production rollout; DC stays NOT_RUN. No package install/restart is implied on any production node.

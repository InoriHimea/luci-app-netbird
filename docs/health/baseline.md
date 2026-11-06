# Health development baseline

Recorded 2026-11-06 for NBH-11. This inventory does not authorize deployment or pass the node56 scheduled-upgrade rollout gate.

## Source

- Repository: https://github.com/InoriHimea/luci-app-netbird ; upstream https://github.com/looong-cat/luci-app-netbird .
- Starting commit: `953e4b2e760fe436b80330f600dd29a9e3bfc8d9`, branch `main`, package `0.2.0-r7`.
- Package definition: `luci-app-netbird/Makefile`; existing ucode/fs/uci/rpcd dependencies; no mandatory netbird package dependency.
- Translation entry points: `luci-app-netbird/po/templates/netbird.pot`, `luci-app-netbird/po/zh_Hans/netbird.po`.
- Release workflow: `.github/workflows/release.yml`. Existing router-mutating fixture scripts under `scripts/` require disposable environments.
- Bitbucket: all three pages of repositories visible to the signed-in user were checked; no netbird/luci matching repository was found. No Bitbucket commit association is asserted (Jira comment 11201).

## Observed platform inventory

| Node | Observation | Scope |
|---|---|---|
| node56 / 10.156.56.100 | iStoreOS 24.10.5 revision 2025123110, x86/64, kernel 6.6.119, plugin 0.2.0-r7, daemon 0.82.0; ip JSON supported; wt0 UP/LOWER_UP, MTU1280, operstate UNKNOWN; ucode/nft/timeout available | Strict host-key SSH, read-only commands; not an end-to-end acceptance |
| node55 / 10.155.55.100 | iStoreOS24.10.8 revision2026073111, x86/64, kernel6.6.144, plugin0.2.0-r7, daemon0.78.1; ip JSON and ucode/nft available; timeout executable absent | Read-only strict SSH; Mesh address lacked an entry in the dedicated trust file, so used the already-trusted LAN address without changing trust |
| Shanghai / 10.110.120.1 | iStoreOS24.10.2 revision2025090517, x86/64, kernel6.6.93, plugin0.2.0-r7, daemon0.80.0; ip JSON and ucode/nft available; timeout executable absent | Read-only strict SSH |
| Wuhan / 192.168.3.1 | iStoreOS24.10.8 revision2026073111, x86/64, kernel6.6.144, plugin0.2.0-r7, daemon0.80.0; ip JSON and ucode/nft available; timeout executable absent | Read-only strict SSH |
| DC | NOT_RUN: existing rollout gate defers readiness inspection | Existing SSH trust verification is not deployment readiness |

The node56 daemon version changed since the historical 0.78.1 record. Version alone does not establish which upgrade path executed, reconnection latency, identity preservation or business health. The existing rollout gate remains closed.

The inventory command ends with `command -v timeout`: node55/Shanghai/Wuhan exited127 after successfully returning the preceding board/package/version/JSON and ucode/nft paths. Missing timeout is a real capability gap, not permission to run unbounded probes. Collection must provide an independently bounded execution mechanism or report UNKNOWN. No package installation or configuration write was performed.

All four observed `wt0` interfaces have `link_type=none`, `UP/LOWER_UP`, MTU1280 and `operstate=UNKNOWN`; node55/Shanghai/Wuhan also report `br-lan` UP/LOWER_UP, MTU1500. These are discovered names, not normative interface names. Link flags alone do not identify kernel WireGuard versus userspace backend or establish end-to-end health; backend mode remains UNKNOWN until a supported capability field identifies it.

## Native isolated model verification

On the existing development host `192.168.58.34`, container `nbh-health-20261106` uses official `openwrt/rootfs` image digest `sha256:b4fa13109cd5e8e8075c01fa7def985de559fd3a5bfc7e59a866d509ab986b0b` (OpenWrt25.12.2 amd64). Isolation: network none, no host mounts, all capabilities dropped, no-new-privileges, 128MiB RAM, 0.5CPU, 64 PID limit. Host services and router configuration are untouched.

Actual command inside the container: `sh /tmp/tests/health/run.sh --unit` against the copied source tree. Native ucode reports `PASS health model: 22 assertions`, then A01 unhealthy (3/3 executed), A02 degraded (3/3), A04 healthy (3/3), A10 unknown (2/3), A24 unhealthy (2/2). The first model execution failed on export syntax; separate declaration/export fixed it. No initial pre-implementation failing behavioral run was captured; review-discovered regressions below have recorded RED/GREEN. These are synthetic model tests, not completed collector/evaluator/UI or production acceptance.

Run in any equivalent isolated environment from the repository root:

```sh
sh tests/health/run.sh --unit
```

Model coverage: missing rules despite Connected, fallback degradation, distinct five perspectives, absent LAN proof, retained expected denominator, missing and stale observations, disabled intent, separate maintenance flag, optional observer gap, empty/not-applicable runs, duplicate observation rejection. No active business probe is issued by these model tests.

JSON Schema 2020-12 verification used development-only jsonschema4.26.0 from an isolated temporary dependency directory (no router/runtime dependency). Both schemas passed schema validation; legal disabled config passed; shell-interface, excessive deadline, secret field and path-traversal sink examples were rejected. Actual native aggregate outputs for all five fixtures were assembled with run metadata by a temporary isolated smoke script and validated against result.schema.json, including fixed denominator sums. The temporary native script was removed after execution.

Independent stateless model/schema reviews identified observation-overridden severity/exclusions and two unbounded nullable timestamps. Added behavioral regressions first: native execution failed with `observation cannot downgrade approved critical failure` (exit254). Reconcile now retains approved severity and exclusions; observation-invented exclusions become UNKNOWN. Native re-execution passed all22 assertions and five fixtures. Nullable timestamps now have finite bounds; overlarge last-success evidence is rejected. Documentation clarifies non-secret approval references, credential-free HTTP paths and sanitized evidence. The original delegated reviewer provider was unavailable (503); these reviews used the working independent completion route, not a claimed successful subagent run.

## Native collection adapter verification

NBH-12 uses the same isolated runtime and unified `tests/health/run.sh --unit`: 12 runner, 26 parser and 12 collector assertions pass alongside the 22 model assertions and five model fixtures. Real read-only samples are `status-0.82.0.json` (node56), `status-0.78.1.json` (node55), and `real-{rules,routes,links}.json` (node56). Status samples retain only version/status, connection booleans, backend capability and peer address/status; peer addresses are replaced with documentation fixtures, and keys/FQDNs/endpoints are removed. Network samples retain non-secret forwarding semantics, not MAC addresses or arbitrary link metadata.

Actual isolated `collect()` without the production tools returned `complete=false`, `GENERATION_UNAVAILABLE`, agent `CAPABILITY_MISSING`, `consistency=endpoint_comparison`, duration30ms and no stderr. This proves the real failure path, not live-router collection or business health. Synthetic A01 collection retains Connected plus a target route without its lookup rule; A04 retains alternate interface/table/priority semantics. Later evaluator/forwarding/UI acceptance remains separate.

Independent review findings were addressed with recorded native RED/GREEN regressions: discarded nexthop semantics, ambiguous duplicate fields, invalid CIDR/null selectors, malformed backend, general command failures falling back, stderr budget accounting, process incarnation evidence, firewall inventory changes and malformed metadata. A second review found the iproute2 unknown-option exit is255; [upstream ip/ip.c](https://github.com/iproute2/iproute2/blob/main/ip/ip.c) confirms `exit(-1)`. Correcting the fixture first failed, then the diagnostic-specific fix passed the unified suite. Runtime inspection disproved a review claim about `clock(true)`: deployed ucode actually returns `[seconds,nanoseconds]`.

No agent configuration/private key was read, no network write command ran, no production deployment or schedule changed, and no A01/A04 production fault was injected. The adapter does not claim an atomic network generation or firewall-rule enforcement from table inventory.

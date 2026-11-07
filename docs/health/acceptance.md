# T08 acceptance matrix

Scope: NBH-18, 2026-11-07. This document separates verified **behavior at the named layer** from unexecuted real-topology acceptance. `PASS` is never a claim that a production site's LAN is healthy. All A01–A24 remain in the denominator; no absent LAN observer, unsupported capability or missing platform is dropped.

Evidence keys:

- **B**: [baseline.md](baseline.md), recorded native model/collector/evaluator/procd/RPC/HTTP/LuCI/HTTPS executions through T07 (`4b3ee2b`). Individual assertion counts and limits are recorded there.
- **K**: `local://nbh-t08-kernel-evidence.json` and reproducible `local://nbh-t08-kernel.uc`; actual isolated Linux rules/tables/from-iif lookups, not a mocked route command.
- **P**: [performance.md](performance.md), original `local://nbh-t08-performance.json`; current-source maximum-load cycle, concurrency, output/deadline and descendant-cleanup executions.
- Native unit source is under `tests/health/`; UI synthetic-response behavior executes inside the actual isolated LuCI surface, as explicitly labelled in B.

## Complete P0 case denominator

| Case | Verified-layer verdict | Evidence and observed boundary | Real topology / additional acceptance |
|---|---|---|---|
| A01 | PASS | K: missing105/110 + table9911 route yields `RULE_MISSING`, actual from/iif lookup exits WAN, unhealthy. B: corresponding actual-page synthetic UI cannot show green. | NOT_RUN: real Connected agent and production LAN fault injection. |
| A02 | PASS | K: scoped12100 changes actual lookup to mesh-alt; native rule drift remains warning/degraded, not fully healthy. B: UI counterpart. | NOT_RUN: real LAN business success through an emergency rule. |
| A03 | NOT_RUN | K proves rules105/110 recovery with unchanged inert process PID/start ticks and retained12100; boundary reports rules changed and engine UNKNOWN. This is not an agent engine reconnect. | NOT_RUN: actual NetBird engine reconnection with stable daemon PID. |
| A04 | PASS | K and native evaluator: explicitly approved priority77/table9911/interface mesh-alt succeeds; no105/110 or wt0 name requirement. | NOT_RUN: production equivalent topology. |
| A05 | PASS | K: actual more-specific /32 WAN route produces `ROUTE_SHADOWED` and WAN lookup; only the owned /32 is removed afterward. B/native evaluator covers missing route and exact approved exceptions. | NOT_RUN: production route changes. |
| A06 | PASS | B native evaluator and actual-page synthetic UI: verified backup route selection is redundancy degradation; peer presence alone stays UNKNOWN. | NOT_RUN: real backup-peer takeover and LAN traffic. |
| A07 | PASS | B parser preserves Idle and exact peer selection without diagnosis; bounded probes cannot derive root cause from the peer label. | NOT_RUN: actual sleeping/on-demand peer lifecycle. |
| A08 | NOT_RUN | B records actual successful local protocol probes and closed-listener `CONNECT_UNDETERMINED`/UNKNOWN; no unsupported attribution to NetBird. This does not prove the complete multi-endpoint, known-good-routing fault scenario. | NOT_RUN: one closed business port with independently verified routing and other targets. |
| A09 | PASS | B native evaluator and actual-page synthetic UI keep router PASS and LAN FAIL separately; aggregate remains unhealthy. | NOT_RUN: deployed LAN client observer versus router vantage. |
| A10 | PASS | B actual native publication, evaluator and UI retain unconfigured LAN as UNKNOWN/NOT_CONFIGURED; P retains every obligation. | NOT_RUN: real unreachable LAN observer. |
| A11 | PASS | B native runner/parser/collector: timeout, malformed status, unsupported ip JSON and truncated output fail closed; P measures output cap and actual20-second deadline. | NOT_RUN: every old firmware/tool variant. |
| A12 | PASS | B actual procd/HTTP coalescing and native scheduler assertions; P concurrent cycle exits0/3 with one published run. | NOT_RUN: production event/manual contention. |
| A13 | PASS | B actual independent UCI/CAS reload and LuCI save/pause/resume; seven identity/init/watchdog/network/firewall hashes remain unchanged. | NOT_RUN: production configuration changes. |
| A14 | PASS | B native maintenance/generation boundaries and worker cancellation; mixed-generation lookups remain UNKNOWN, no maintenance takeover. | NOT_RUN: actual agent upgrade or physical interface reconstruction. |
| A15 | PASS | B native alerts/runtime thresholds, deduplication, bounded reminders, recovery and new incident; first-anomaly publication failure was exercised RED→GREEN. | NOT_RUN: production incident notification or human receipt. |
| A16 | PASS | B actual isolated verified HTTPS503/200/timeout/certificate mismatch/refused connection, durable independent delivery and unknown non-replay; receipt remains false. | NOT_RUN: production Gotify/central availability and user receipt. |
| A17 | PASS | B actual abnormal native observer plus independent actual-page normal/abnormal/recovered/expiry cases; recovered current state clears old failure. | NOT_RUN: production observer recovery. |
| A18 | PASS | B actual procd supervisor SIGKILL/respawn; native boot/clock/freshness/history boundaries. P proves no delayed child after deadline. | NOT_RUN: physical reboot/power loss and real hardware clock change. |
| A19 | PASS | B native input/target/export validation and actual-page hostile-description RED→GREEN; redirects rejected by actual TLS transport. | NOT_RUN: penetration testing of every external firmware component. |
| A20 | PASS | B actual authenticated HTTP/LuCI role separation; read identity denied run/config/export/notify/legacy reconnect and arbitrary UCI/file access. | NOT_RUN: production user login/IAM verification. |
| A21 | PASS | Actual SDK r8 fresh install, active r8→published-r7 rollback, r7→r8 upgrade, direct r8 removal and main+Chinese paired install/removal; 28 health files package-owned/source-equal, seven preservation comparisons and actual12100 retained, no health service/worker afterward. See [release-r8.md](release-r8.md) for original-receipt limits and kernel-dependency staging. | NOT_RUN: production lifecycle, physical target kernel and OpenWrt24.10 IPK runtime. |
| A22 | PASS | B actual rtnl listener exposes missing overrun capability as `event_gap=true`; native flood/debounce/periodic fallback assertions. | NOT_RUN: production event flood. |
| A23 | NOT_RUN | B native unapproved-path/SSRF/protocol validation fails closed; P actual namespace rules/routes/config remain byte-equal. No packet-level multi-zone ACL challenge was run. | NOT_RUN: negative destination/protocol traffic through the original security policy. |
| A24 | PASS | B native model/evaluator/boundary and K actual rules-change evidence retain cause-undetermined/engine-UNKNOWN; correlation never identifies a deleter or requests mutation. | NOT_RUN: causal audit collection in a real incident. |

No P0 case is declared NOT_APPLICABLE merely because its runtime/platform/probe is absent. Real-topology NOT_RUN items above remain limitations, not hidden passes. P1 A25–A32 belongs to E01–E05 and is not included in this P0 denominator.

## E01 supplemental denominator (outside the frozen T08 delivery)

| Case | Verified-layer verdict | Observed evidence | Remaining boundary |
|---|---|---|---|
| A25 | PASS, isolated kernel and bounded state | Connected fixture plus actual approved prefix but missing query rule selects WAN with source/iif; required failure survives wait and remains failed after the actual deadline. | Actual NetBird/production LAN fault NOT_RUN; Connected/process/firewall are explicit fixtures. |
| A26 | PASS, isolated kernel and bounded state | Query rule restored before route still falls through to WAN; finite wait expires to failure. Route restoration selects the approved table/egress but cannot complete READY without representative business evidence. | Production network restart and real business convergence NOT_RUN. |

Native RTNL callbacks, persistent failed/no-start workers, generation-publication fencing, current-schema publication and real LuCI rendering supplement these two cases; [baseline.md](baseline.md) distinguishes each layer. The actual shared-module browser regression covers all five phases and monotonic wait expiry during wall-clock rollback. These additions do not alter the archived r8 package/manifest evidence, close T09 site acceptance or stand in for E02–E05/A27–A32.

## E02/E03 supplemental denominator (outside frozen T08 delivery)

| Case | Verified-layer verdict | Observed evidence | Remaining boundary |
|---|---|---|---|
| A27 | PASS, isolated native RPC/HTTP/LuCI | Explicit cancel has zero restarts; confirmation, duplicate requests, connection loss and saved-ID reload retain one job/one restart. Read-only and missing/invalid SID requests cannot recover. Native actor propagation, private durable jobs and independent claim-relative deadline are exercised. | Actual production transport loss, VPN reconnection and physical power loss NOT_RUN. |
| A28 | PASS, isolated real kernel with inert agent | Restart exit0 does not hide missing query rule/WAN source-iif selection: FAILED/POST_CHECK_FAILED with LAN UNKNOWN. Required structure, forwarding and business evidence are independent of command success. Pending settings prevent a success verdict. | Real NetBird/production LAN fault and recovery NOT_RUN. |
| A29 | PASS, isolated native arbitration and process boundaries | Manual/watchdog/settings/updater competition has one down/up pair and one charge; immediate retry has zero effects. Real owner/helper SIGKILL, delayed first-install writers, stale recovery after backup cleanup, monotonic reversal, active-group fences and explicit stop/auth/intent boundaries are exercised. | Uncoordinated user scripts remain conflicts for new recovery; production script migration, live fault/physical D-state/power-cycle NOT_RUN. |

These cases do not close T09 site acceptance, authorize deployment/automatic recovery or satisfy E04/E05/A30–A32. See [baseline.md](baseline.md) for executed native/browser layers and explicit limits.

## E04 supplemental denominator (outside frozen T08 delivery)

| Case | Verified-layer verdict | Observed evidence | Remaining boundary |
|---|---|---|---|
| A30 | PASS, isolated native workers/supervisor and actual LuCI/HTTP | Default OFF and separately authenticated explicit consent; Cancel and health Save do not enable. Seven automatic worker guard cases have zero effects. Three native source cycles spanning over60s submit one fixed restart recorder via the real host/worker. Read-only HTTP cannot authorize it. | Pre-action structure/Connected is synthetic; restart is an inert recorder. Actual VPN/LAN/production enablement NOT_RUN. |
| A31 | PASS, isolated policy/persistence and native failed attempt | One charged incident remains sealed through continued fault, off/on and supervisor recreation; at least30min cross-incident budget and boot/clock boundaries are exercised. Real native post-check UNKNOWN is not restored. One persistent failure event retains central/local/none ownership and survives runtime-state loss without duplication. | Physical power loss, production notification receipt and real NetBird recovery NOT_RUN. E05 dependency still pending. |

Independent reviews have no remaining blockers after a reproduced source-time voting fix. These rows do not close E05/A32 or T09 production/site acceptance and do not authorize automatic rollout.


## Seven deliverable groups

1. Code and executed unit/integration/UI/native evidence: T01–T07 commits and B; K and P contain new T08 original observations. Actual current SDK native lifecycle/publication and paired-language receipts are described in [release-r8.md](release-r8.md).
2. [contracts.md](contracts.md): result/config schemas, permission groups, independent settings/CAS, validation/error responses, capability and compatibility boundaries. [result.schema.json](result.schema.json) and `luci-app-netbird/root/usr/share/netbird/health/config.schema.json` are authoritative schemas. B contains the actual read-only platform inventory; inventory is not runtime acceptance on every firmware.
3. Actual versioned SDK APK/IPK and Chinese packages, SHA256, published r7 rollback pairs and exact-range source bundle: [release-r8.md](release-r8.md) and its delivered asset manifest. Final T08 commit/bundle metadata is generated after the documentation commit; signing trust remains unresolved, not inferred from hashes.
4. Wuhan-shaped RED→GREEN fixture: K records actual A01/A02/rules-recovery sequence and preserved12100. Real engine/LAN parts remain NOT_RUN.
5. Alert delivery failure/deduplication/recovery, observer and maintenance coexistence: B native T04–T07 executions; acceptance and receipt are distinct.
6. Measured resource, duration, process and namespace preservation: P; B contains actual supervisor deadline/recovery, settings preservation and permission rejection.
7. Missing evidence is explicit in every row: no production deployment, true LAN observer, physical reboot, lowest-hardware capacity or real notification receipt is claimed.

## Deployment and rollback gates

This task does not authorize deployment, deletion of emergency12100, network/firewall changes, agent reconnection/restart, real notifications or production user login. Node56's first **real scheduled update plus functional acceptance** gate remains closed; readiness, a skipped update window or a version change does not open it. DC remains NOT_RUN. No rollout to node55/Shanghai/Wuhan/DC follows automatically from an isolated pass.

Installation must retain existing NetBird identity/configuration, external watchdog and user routing; active probe targets stay empty/disabled by default, and disabled monitoring must not send notifications even though new alert ownership defaults to central. Reverting to r7 removes health support, so its self-retiring supervisor must drain owned workers and unregister only its own service. [release-r8.md](release-r8.md) records actual SDK lifecycle and hashes; production authorization and signing trust remain separate gates.

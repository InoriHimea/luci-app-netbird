# Health contracts — schema version 1

NBH-11 freezes the model and JSON contracts, not the later collector, evaluator, RPC or UI implementation. The canonical configuration schema is installed from `luci-app-netbird/root/usr/share/netbird/health/config.schema.json`; `result.schema.json` remains here. Both use JSON Schema 2020-12; neither changes existing NetBird configuration. T05 installs the configuration schema alongside its validator, avoiding a second runtime copy or a build dependency outside the package directory.

## Identity and administrator intent

`schema_version` identifies this wire contract. `revision` / `config_revision` change only with approved configuration; `baseline_revision` identifies approved expectations. Stable node/check IDs are not derived from currently visible routes. A run gets a distinct `run_id`, `boot_id` and collection `generation`; clock timestamps are epoch seconds, durations use monotonic milliseconds. Epoch order alone cannot prove elapsed time or causation.

Configuration preserves raw CIDR separately from confirmed normalized CIDR, approval identity/time/revision and expiring exceptions. Missing observed routes cannot remove a configured path. Newly discovered objects are candidates, not automatically approved probe targets. Disabled configuration stays disabled; reading or migrating data cannot enable active probes or notifications. The valid example is explicitly disabled.

Schemas enforce shape and bounded strings/arrays, not all network semantics. Saving configuration must also validate CIDR address/prefix width and host bits, exact approved normalization, literal address/FQDN syntax, unique IDs and referenced path IDs, protocol-specific ports, HTTP path restrictions, approval/baseline coherence and expired exceptions. Regex acceptance is not approval to execute. A sink reference is an opaque configured identifier, never a file path or credential. Tokens and arbitrary unknown fields are rejected.

`authorization` contains non-secret approval metadata or a ticket reference, never an authorization token. HTTP paths must not contain credentials, secret query parameters or userinfo; save-time validation rejects them. Producers must sanitize all expected/observed text and evidence references before publication or export. Length limits alone cannot prove absence of secrets.

## Results and aggregation

Each check carries its approved expected state and a bounded observed fragment, evidence reference, perspective, timing, parser status and execution status. `expected`/`observed` are nullable bounded strings, not unbounded nested documents. Raw evidence is separately bounded and sanitized by its producer; a reference never grants arbitrary-file access.

Five independent perspectives: `local_structure`, `forward_lookup`, `router_probe`, `lan_probe`, `external_observer`. Router-originated success is not LAN end-to-end proof; route lookup is not a packet test. Overall cannot be healthy without healthy actual LAN coverage. An unsupported backend or unexecuted check is UNKNOWN, not empty success.

- PASS: executed, fresh positive evidence for this check.
- FAIL: executed, fresh negative evidence. Critical required failure means unhealthy; warning/info required failure means degraded.
- UNKNOWN: missing, expired, unsupported, timed out, malformed, unexecuted or otherwise inconclusive evidence.
- NOT_APPLICABLE: approved intent explicitly makes this check inapplicable; not equivalent to PASS.
- DISABLED: explicit disabled intent; not equivalent to PASS.

Aggregation interprets unexecuted/stale PASS or FAIL as UNKNOWN, including an entirely stale run. It does not mutate supplied observations. Counts use these effective statuses; consumers must not compare counts against raw status without applying freshness/execution. `expected_count` includes every configured check, including UNKNOWN, NOT_APPLICABLE and DISABLED; the five status counters sum to it. `executed_count` counts actual execution independently. These cross-field invariants require programmatic checks in addition to schema validation.

Required critical failures take precedence over required warning failures, then required unknowns, then healthy. Optional evidence remains visible in its perspective but does not by itself change required health. Empty or entirely inapplicable runs are unknown. Explicit monitor disable overrides overall with disabled. Checking, maintenance and stale flags remain separate, not fabricated success. Notification `delivery_state` never substitutes for business health.

`reconcile(expected, observed)` rejects duplicate/empty IDs, retains missing expected checks as unexecuted UNKNOWN, ignores unapproved extra observations and restores intent-owned required/vantage/expected/severity fields. Only administrator intent can mark a check DISABLED or NOT_APPLICABLE; an observation trying to introduce either becomes UNKNOWN/INTENT_MISMATCH. Observations cannot re-enable an intent-disabled check. `aggregate(checks, options)` returns the health/count/coverage fragment, not a complete run envelope. Callers supply run metadata and bounded check/evidence records.

## Reason codes

| Code | Meaning / classification |
|---|---|
| OK | Positive evidence for the specific check only |
| NOT_EXECUTED | Expected check not executed; UNKNOWN |
| INTENT_MISMATCH | Observation attempted an unapproved exclusion; UNKNOWN |
| NOT_CONFIGURED | Required perspective, notably LAN, has no configured probe; UNKNOWN |
| CAPABILITY_MISSING | Required tool/backend capability absent; UNKNOWN |
| COMMAND_TIMEOUT | Bounded collection deadline exceeded; UNKNOWN |
| OUTPUT_LIMIT | Output budget exceeded; UNKNOWN |
| PARSE_ERROR | Malformed/unrecognized output; UNKNOWN |
| GENERATION_CHANGED | Boot/process/network generation changed during collection; UNKNOWN |
| STALE | Evidence freshness expired; UNKNOWN |
| NATIVE_RULE_DRIFT | Approved native rule absent; FAIL, at least degraded even with fallback |
| WRONG_EGRESS | Actual forwarding differs from approved intent; FAIL |
| ROUTE_MISSING | Approved route missing; FAIL |
| EXCEPTION_EXPIRED | Approved exception expired; configuration drift, no network mutation |
| CAUSE_UNDETERMINED | Correlated events without deleting-actor audit; no definite root-cause claim |

The reason-code list is extensible within the schema's bounded uppercase syntax. Codes do not confer permission for recovery or network mutation.

## Executable fixtures and evidence limits

`tests/health/fixtures/A01.json` through A24 (A01/A02/A04/A10/A24) are explicitly synthetic. Raw route/rule/from/iif observations and approved intent accompany expected aggregate checks. They exercise this model's result semantics, not real-fault or end-to-end evaluator acceptance. Separate collector tests preserve A01's Connected/orphaned-table evidence and A04's equivalent layout without requiring wt0/7120/105/110. A24 does not identify a deleting actor from timestamps.

Native driver: `sh tests/health/run.sh --unit`. Schema examples: `config-valid.json` and `config-invalid.json`. Source/platform observations and actual execution evidence are in `baseline.md`. Production fault injection, deployment and real notification delivery remain outside this task's authorization.

## Read-only collection boundary

`health/collect.uc` collects IPv4 rules and all IPv4 routing tables, interface metadata, sanitized agent status, and nft table inventory. `complete` describes available, endpoint-consistent observations, never healthy business connectivity. `consistency=endpoint_comparison` compares boot ID, process PID/start ticks, parsed network evidence and firewall table handles before/after. It cannot exclude an intervening change-and-return (ABA), establish an atomic snapshot, prove firewall enforcement, or prove LAN forwarding. IPv6 and unsupported selectors/nexthops remain capability gaps, not inferred success.

`health/runner.uc` accepts only internally chosen fixed system-tool argv. Its constant shell wrapper uses positional arguments, private temporary files, file-size limits and process-group cleanup; it is not an arbitrary-command API or sandbox for daemonizing tools. The collector admits at most 20 seconds of work, caps each command at 2 seconds including reserved cleanup time, rejects deadline overruns, and charges stdout plus stderr against 256KiB. Per-stream 64KiB limits fail closed. Filesystem scheduling and parsing are not an independent hard watchdog; the worker must enforce its own whole-cycle deadline.

JSON syntax errors, truncation and general command failures do not trigger text fallback. Only recognized legacy ip JSON-option diagnostics permit it; unsupported link-text parsing stays UNKNOWN. Raw agent secrets and raw stderr never leave the adapter. Peer selection is exact by approved IPv4 address; absent or ambiguous peers remain unknown, and Idle remains an observation rather than a diagnosis.

## Path evaluator evidence

`evaluate_path` does not accept peer presence as selected-peer proof. Internal peer evidence must have `kind=route_selection`; router and LAN probes require distinct `router_probe` and `lan_probe` kinds. Each record binds `path_id`, `path_source`, `iif`, `destination`, `baseline_revision` and a nonempty matching snapshot `generation`. Epoch `sampled_at` must not be in the future; `expires_at` is exclusive and must be within 300 seconds of sampling. A producer's `fresh` flag cannot override these checks. These fields are an internal provenance contract, not authentication: the eventual probe ingestion boundary must authenticate the origin before constructing them.

Missing, cross-path, wrong-generation or expired evidence remains UNKNOWN. The evaluator never promotes router success to LAN success or attributes endpoint failure to the agent. Duplicate rule priorities remain ambiguous rather than being resolved by an incidental sort order. Approved prefixes containing host bits are rejected, not silently normalized.

`evaluate_path(path, snapshot, lookup, now, exceptions)` evaluates approved IPv4 intent only. Destination must belong to the canonical expected prefix. Ordered rules honor source/destination, ingress/output selectors, mark/mask, inversion, terminal actions and prefix suppression; terminal route errors cannot be suppressed. Longest-prefix and metric selection retain ambiguous ties as UNKNOWN. Native-rule drift remains a warning failure even when a permitted fallback forwards successfully.

`collect(execute, paths)` queries each approved path inside its endpoint comparison window and attaches a generation-bound `forward_lookup` evidence record valid for 30 seconds. `lookup_path` uses fixed `ip -d -j -4 route get ... from ... iif ...` argv: details mode requests an explicit main table rather than guessing from static routes. Unsupported detail/JSON capabilities or absent tables remain UNKNOWN. Optional marks require a unique observed rule matching the approved priority/table/mark/mask reference; this does not prove real packets receive that mark. DNAT, TPROXY and other configured query limitations prevent full-path PASS.

An exception may include `route={baseline_revision,prefix,table,egress}`. Its non-secret authorization, exact path object ID, current baseline and unexpired integer deadline must match. It authorizes only the exact selected route prefix/table/egress; a broad prefix, another path, or generic exemption cannot permit forwarding. It does not erase a missing expected route, native-rule drift, interface failure or missing LAN evidence. Configuration validation remains responsible for authenticating administrator approval.

Path IDs allow 96 characters; derived check IDs append a category and therefore allow 128 characters. Collection tokens describe one endpoint-compared run, not an atomic network-generation guarantee.

## Background service and probe boundary

`luci-netbird-health` is a separate, default-off procd service. Its only approved configuration source is `netbird_health.main.approved_config` in `/etc/config/netbird_health`; the installed schema and cross-field validator reject invalid configuration before starting a supervisor or cycle. There is no legacy JSON-file fallback. Absence or disabled configuration starts no monitor. The supervisor uses uloop rather than running collection on rpcd's event loop. Its default period is 60 seconds, configurable 30–3600; each independently guarded cycle is capped at 20 seconds. Active manual requests share the running job; clicks within two seconds of a short job share its recent result. Network events wait for two quiet seconds, with a five-second flood cap. Unsupported listeners and unobservable netlink overruns are explicit event gaps; periodic work does not depend on receiving events.

Every nested command inherits an absolute monotonic execution deadline. A separately armed guard must publish readiness before command execution. Shared command leases begin before temporary directory allocation; a nonblocking exclusive janitor reclaims only recognized root-owned private remnants when no owner/guard is active. It runs on startup and every five idle seconds, covering crashes before arming and after group draining. Procd restarts only this service after 21 seconds; orderly stop waits for the bounded worker, with a 22-second native stop timeout. No reconnect/recovery/update/settings worker is called.

Router TCP and RDP use actual socket addresses. RDP performs only TPKT/X.224 confirmation, never authentication. IPv4 ICMP uses a Linux ping datagram socket, validates the echo identifier/sequence/payload and records that socket's local address and the reply's sender; unsupported or denied ping sockets stay UNKNOWN. HTTP(S) disables curl configuration/proxies/globbing, restricts the scheme, does not follow redirects or retain bodies, and records curl's local/remote addresses and status. HTTPS keeps certificate verification enabled. curl and rtnl are optional capabilities; absent support is not success. Unclassified connection failures remain UNKNOWN rather than diagnosing a remote endpoint or NetBird fault. No router probe is promoted to a LAN client or external-observer observation.

Only `/tmp/netbird-health` and private command temporary directories receive periodic writes. Published files are 0600 in 0700 directories, with atomic rename and a 512KiB per-state limit. History is bounded by configured count and 4MiB retained bytes; one fixed recoverable history stage prevents interrupted sequences accumulating temporary files. Latest/recent-success/first-abnormal publications retain boot/process/interface and before/after rule/route boundaries. The internal latest envelope contains raw bounded snapshot/probe evidence plus `run`, which follows `result.schema.json` and the existing aggregation model. Disabled and unavailable required checks remain in its denominator. Generation/engine/watchdog uncertainties and temporal correlation are not deletion-actor attribution.

APK downgrade to a release predating this service may omit its stop hook. A running supervisor therefore checks only its own installed init/script entrypoints, unregisters only the fixed `luci-netbird-health` procd service when they disappear, and drains its existing bounded worker. This is self-retirement, not an agent/network/settings/watchdog action; the actual older-package downgrade and package-removal paths are covered by isolated native APK evidence.

## Independent RPC and permissions

`luci.netbird.health` uses the existing `{ok,data}` / `{ok:false,code,message}` envelope. It registers `get_summary`, `get_checks`, `get_events`, `get_config`, `start_check`, `get_job`, `set_config`, `prepare_export` and `test_notification`. HTTP clients authenticate through native uhttpd/rpcd sessions. Local root ubus callers remain privileged. Separate `luci-app-netbird-health-{read,run,config,export,notify}` ACL groups grant exact methods; they grant no generic file execution, raw UCI write or legacy NetBird reconnect permission. A read-only identity needs only the read group. Configuration approval labels are administrator-supplied metadata, not authenticated actor attribution.

Summary/check reads use cached observations only. Boot changes, clock reversal, age beyond twice the interval plus cycle timeout, or changed configuration/baseline revision invalidate sampled PASS/FAIL in the effective view without rewriting original evidence. Old-revision views explicitly identify `previous_approved_baseline`; their counts are not claimed to describe the new baseline. Missing required LAN evidence remains UNKNOWN. Events are retained `snapshot_difference` records, not a lossless RTNL journal or proof of the deleting actor.

Checks/events accept `limit` 1–100 and an optional backend-issued `cursor`. Each continuation freezes its dataset, run/revision metadata, total and page size. A cursor cannot cross dataset kinds. At most four 512KiB snapshots are retained for ten monotonic minutes; expiration, eviction/unknown IDs and malformed cursors are explicit errors. A single-page result creates no cursor snapshot. Opaque job IDs expire after ten monotonic minutes. `start_check` accepts only an enabled, approved configured `path_id`; it executes the complete approved baseline, including that path, rather than silently shrinking the denominator. The returned scope is `full_approved_baseline`. In-flight jobs and rapid repeats coalesce.

Continuation freezes sampled rows/order/counts, not their present validity. Every checks page rechecks boot, wall-clock age and approved configuration/baseline scope; invalidated sampled PASS/FAIL becomes effective UNKNOWN without rewriting the snapshot. Running baseline jobs have a 30-second execution lease (20-second independent cycle deadline plus draining/publication margin), distinct from ten-minute retention. Expired execution leases become terminal before new work is admitted; a potentially live old-revision worker is not displaced, and late completion cannot overwrite its replacement.

`set_config` takes a complete schema-valid configuration and `expected_revision`. A private lock and revision CAS prevent stale overwrite; success increments only the independent health revision and publishes only the `netbird_health` configuration-change event. It does not apply agent, network or firewall configuration. Endpoint configuration requires explicit safe IPv4 `allowed_addresses` inside the approved path prefix. Resolution rejects any unapproved/mixed/forbidden answer; connections use numeric pins, HTTPS retains its original verified TLS name and redirects are not followed. Configuration rejects unsafe or ambiguous address forms, shell/path injection and control characters; percent-encoded HTTP paths are conservatively unsupported.

## Evidence export and explicit notification tests

Export-authorized callers invoke `prepare_export` without arguments to create evidence, then invoke it with the returned opaque `id` and byte `offset` to retrieve base64 chunks of at most 16KiB. Creation returns exact byte size and native SHA-256. Up to four private 512KiB export records are retained for ten monotonic minutes. There is no arbitrary pathname or unauthenticated download endpoint. The payload labels sampled evidence rather than current proof, preserves original bounded reason/exit/check text and public run identity, and allowlists fields instead of copying raw snapshots/configuration. It includes at most 64 checks with explicit included/total/truncated fields; original aggregate counts retain their full denominator. Credential-shaped diagnostic text is redacted. Raw CLI stderr was deliberately never retained by the collector and is not reconstructed or falsely claimed as available.

Notification tests require the notify group, `notification.owner=local` and a configured `sink_ref`. None/central ownership or a missing sink returns explicit not-configured status. References select only root-owned 0600 regular JSON files under the root-owned 0700 `/etc/netbird-health/sinks` directory. The exact Gotify sink schema is `{schema:1,kind:"gotify",host,port,address,token}`: host is a validated DNS name, port 1–65535, address one explicitly approved safe IPv4 pin, token a nonempty bounded ASCII credential. Sink credentials never appear in UCI/RPC responses, command arguments or environment; the worker stages only a private backend curl configuration and removes it after execution. Do not place credentials in chat or source control; production credential provisioning remains a separate authorized operation.

Each explicit test issues a separate notification-namespace job and launches a fixed asynchronous worker even when periodic monitoring is disabled. Concurrent requests coalesce; a 30-second cooldown reuses the recent result. The fixed HTTPS POST verifies TLS, pins the destination, disables proxies and follows no redirects. Guarded transport is bounded to five seconds. HTTP 2xx means provider `accepted`, never receiver-confirmed delivery (`receipt_verified=false`); rejection and indeterminate/timeout outcomes remain distinct. An indeterminate job is never automatically replayed. Unknown/expired IDs are explicit. Backend metadata retains only bounded transport reason, exit code, duration, output byte count and HTTP status, never raw credential-bearing output.

Worker completion rechecks the queued notification namespace, covering a newly approved request arriving between the prior terminal publication and process exit. Only unsubmitted queued work is dispatched; indeterminate submitted work is not retried. Worker-launch failure publishes terminal `WORKER_START_FAILED` / `not_submitted` rather than claiming delivery.


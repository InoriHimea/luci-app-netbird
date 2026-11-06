# Health contracts — schema version 1

NBH-11 freezes the model and JSON contracts, not the later collector, evaluator, RPC or UI implementation. `config.schema.json` and `result.schema.json` use JSON Schema 2020-12; neither changes existing NetBird configuration.

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

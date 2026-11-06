# Independent observer and LAN probe (NBH-19)

## Status and boundary

The `observer` package is a separate Linux/Python 3 standard-library program. It does not replace gateway2 monitoring, install a listener, control NetBird, change routes/ACLs, or elect a replacement notification owner. The LuCI package supplies the cache-only publisher at `/usr/share/netbird/health/observer-read.uc`.

The implementation is under acceptance, not a claim of completed site monitoring. Real Wuhan LAN-to-two-RDP paths, other production directions, production ACL isolation, and user notification receipt remain **NOT_RUN**. Existing node56/DC rollout gates are unchanged. Synthetic P0 cache data used in isolated integration is not evidence of an active P0 engine or a real VPN path.

## Commands and private files

Run from a source checkout containing `observer/`:

```sh
python3 -m observer.central once --config /etc/netbird-observer/config.json --state /var/lib/netbird-observer/state.json
python3 -m observer.central read --config /etc/netbird-observer/config.json --state /var/lib/netbird-observer/state.json
python3 -m observer.lan_probe --help
```

`once` performs one bounded collection; scheduling is an explicit operator responsibility. `read` only reads configuration/state and reevaluates freshness; it never opens an SSH session, schedules a probe, or sends a message. A nonblocking private lock prevents overlapping collection. Early repeated `once` calls do not advance incident thresholds or rewrite state.

Configuration/state directories must be owned by the executing user with mode 0700; JSON files must be regular, owned files with mode 0600. Symlinks, duplicate JSON members, nonfinite numbers, and oversized input are rejected. State writes are atomic and fsynced. Do not share the state between independent collectors: ownership and deduplication are local to this single coordinator.

Central configuration has exactly these fields:

- `schema_version`: integer 1; `enabled`: boolean, keep false until deployment approval.
- `collector_id`: stable identifier.
- `interval_seconds`: 10–3600; `poll_budget_ms`: 500–60000 and strictly below the interval.
- `max_age`: 10–86400 and at least two intervals; the node's shorter source TTL also applies.
- `nodes`: up to 32 stable node IDs mapped to SSH specifications.
- `lan`: up to 32 expected LAN observations, including missing/unavailable probes in the denominator.
- `notifications`: exactly `owner` (`none` or `central`) and `sink_file` (null or an absolute private-file path). Keep owner `none` for isolated acceptance and until real notification authorization.

An SSH specification has exactly `host`, `port`, `user`, `identity_file`, and `known_hosts_file`. Use a dedicated restricted identity and an explicitly verified dedicated trust file. Password fallback, trust bypass, global SSH configuration, agent forwarding and arbitrary remote commands are not supported.

Executables are pinned to `/usr/bin/ssh` and `/usr/sbin/ip`; their absence is a capability failure, not a reason to search an inherited PATH. Bounded children receive only a fixed system PATH and C locale. Deployment must provide those trusted system paths. Process-group termination covers the trusted supplied SSH/ip/Python command tree; it is not a sandbox against a malicious executable that deliberately calls `setsid()` or moves process groups. Such untrusted execution requires externally controlled cgroup containment and is outside this interface; this work does not modify host cgroups.

A LAN entry has exactly `ssh`, `node_id`, and `expected`. `node_id` must identify a configured node. `expected` has exactly `probe_id`, `target_id`, `source`, `interface`, `gateway`, `baseline_revision`, `address`, `port`, `protocol`, and `timeout_ms`; it must match the independently configured probe. Approved source, destination and gateway are numeric IPv4 addresses, not arbitrary hostnames or shell expressions.

## Restricted receiving commands

Use an existing approved authenticated channel; do not open a public monitoring port. Receiver-side forced-command restrictions are mandatory, not merely client conventions:

- Node key: execute `ucode /usr/share/netbird/health/observer-read.uc`; only `SSH_ORIGINAL_COMMAND=netbird-health snapshot-v1` is accepted.
- LAN key: execute a fixed local `python3 -m observer.lan_probe` invocation with its approved private configuration and attestation file. Only `netbird-health probe-v1 TARGET_ID` is accepted; the ID must already exist in the local configuration.
- Central read-only key: execute the fixed `observer.central read` command with approved paths. Only `netbird-health central-v1` is accepted; the same key cannot execute `once` or `deliver`.

Disable port/agent/X11 forwarding, PTY and tunnels for each identity. The isolated wire verification uses a separate loopback OpenSSH daemon, distinct forced node/LAN identities, and existing synthetic keys; it does not prove production Dropbear/OpenSSH configuration. Validate the actual receiver's key-option semantics before deployment. Do not authorize a generic shell, sudo interface, arbitrary config path or remote target address.

The publisher reads the current config, cached result and bounded private event state. It never imports the RPC API or starts jobs. It exports only approved event fields, current configuration revision and eligible central-owned events; private notification credentials are not part of this schema.

## LAN identity and path evidence

The LAN executor requires Linux, root privileges for device binding, and `ip` JSON route lookup. It binds both the approved source and LAN interface, then checks the **natural** route to the target from that source without forcing an output-interface lookup. Source, device and gateway must all match.

Supported protocols are TCP connect, HTTP/HTTPS HEAD without redirects, and credential-free RDP negotiation. HTTPS verifies the certificate, including the numeric destination's IP identity. RDP validates the first complete 19-byte TPKT/X.224 confirmation and accepted TLS/HYBRID negotiation; an open socket, plain confirmation, refusal, wrong declared frame length or truncated frame is not PASS. Later stream bytes and EOF are not examined: this is first-frame negotiation evidence, not authentication, TLS establishment or whole-session validation. No RDP password is stored or sent. Each target has a 100–5000ms total budget.

Binding is not initial path proof. A private operator-approved attestation, keyed by target ID, must include the complete expected tuple, current probe boot ID, `verified_at`, `expires_at`, and the SHA-256 of actual authorized bounded packet-header evidence. The validity span is at most 30 days. A changed boot, baseline, source/interface/gateway, target/protocol/budget, expiry or missing evidence invalidates it. The attestation is an operator trust decision, not automatic cryptographic proof that every subsequent packet follows the old path. Reattest only from new authorized evidence; never extend an expired fixture receipt to manufacture green state.

Daily results record boot/run/time, source/interface/gateway and route evidence. Reused run IDs with altered time/boot and same-boot sample rollback are rejected, including across a failed collection. Invalid or missing probe evidence is UNKNOWN; it is not silently removed from counts. Independent LAN FAIL wins over healthy node/router observations.

## Freshness, incidents and delivery

The collector distinguishes node unreachability, collection failure, and stale source results. Boot/run identity, wall-clock reversal, monotonic reversal and both source/collector TTLs invalidate cached green state. A cached read does not refresh the observation. Current approved LAN UNKNOWN causes remain visible; expired observations become `PROBE_STALE`.

Each distinct accepted boot/run/sample gets a collector-boot-local monotonic deadline based on its remaining wall TTL. The same cached sample cannot extend that deadline, including after failed polls; changing collector boot requires a new source sample. Both node and LAN caches retain up to 32 retired source boots and reject their return. A further source boot fails closed rather than forgetting replay protection; an operator must resolve identity/state history explicitly before further acceptance. LAN observations also reject collector wall or same-boot monotonic reversal. JSON rejects duplicate keys, literal nonfinite constants and exponent overflow.

Visibility incidents require three separated bad polls; two separated good polls recover the same episode once. Repeated failure is not a new incident, and a later episode receives a new identity. Event IDs correlate node, path, category and episode. Durable seen IDs are retained for a bounded day-long window; live dedup entries are not evicted to hide a capacity error or clock rollback.

Node and LAN visibility use separate `node:` and `lan:` namespaces even when approved IDs contain colons. Every transition first has one durable pending event per incident; while admission is blocked, only that incident's votes pause, not observed health. The original failure/recovery survives both restart and a reversal of health, and clears only after durable admission. Queue and day-long admission retention remain bounded; an expired unadmitted event stays fail-closed pending for operator resolution rather than silently disappearing.

Disabled monitoring is non-voting: it breaks success/failure streaks without closing an active incident or emitting recovery. Two new enabled fresh observations are required afterward.

The private outbox is bounded to 32 display records. Submission is persisted **before** network I/O. A lost result or coordinator death after submission becomes UNKNOWN, never automatic replay. Explicit non-2xx rejection permits at most three attempts with bounded backoff and a shared minimum 60-second send spacing. Exhausted rejected records count as `failed`, not `queued`; terminal display records may leave the outbox while their live dedup identities remain. A full nonterminal queue fails closed without marking a new event as already admitted.

The only optional backend is a private JSON file containing exactly `endpoint`, `token`, and `ca_file`; the endpoint must be HTTPS `/message` without URL credentials, query or fragment. This is an input contract, not permission to obtain production secrets. Use the approved credentials workflow; no production backend is configured by this work. Never put credentials in arguments, environment, logs, exports or Jira.

The sender is a separate bounded process with an independent hard deadline. Provider 2xx means `accepted`; it **never** sets `receipt_verified=true`. Rejection, timeout, owner absence, queue capacity and unknown submission are delivery states independent of health. There is no automatic owner failover.

## Exercised evidence

- Linux 48 behavioral regressions pass, including actual combined-output limits, closed-pipe hangs, delayed-child cleanup, hostile PATH substitution, node/LAN clock and retired-boot replay, incident namespace collision, persistent queue backpressure across health reversals, and incomplete HTTP response rejection. Real socket smoke accepts complete 204 and rejects both EOF-truncated and over-limit unterminated status lines.
- Owned isolated LAN→gateway→target namespaces provide actual source/ingress/egress packet headers for two synthetic RDP destinations and HTTP. Removing one owned target address makes LAN FAIL dominate a synthetic healthy node; restoration returns the isolated path to PASS.
- Actual restricted SSH cache collection, forbidden command/role/key/trust cases, loss threshold and same-episode recovery are exercised. An initial smoke assertion incorrectly combined a 20-second TTL with two delayed good polls and counted an unrelated source event; its failure is retained, and the continuation uses a 30-second TTL and the correct incident category.
- Actual private-loopback TLS cases exercise 200 acceptance, 503 rejection, lost response and coordinator SIGKILL after submission. Each case produces one request; unknown/accepted events are not replayed from a new process, and the independent sender exits after coordinator death. All receipts remain unverified.

Raw working receipts are retained in `local://nbh-t09-native-progress.json`; this is progress evidence, not a completed release asset or production acceptance certificate.

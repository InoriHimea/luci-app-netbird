# Architecture — luci-app-netbird

LuCI app to manage the [NetBird](https://netbird.io) mesh-VPN client on OpenWRT.
It has no VPN daemon of its own — it drives the upstream `netbird` binary and its procd
service through UCI and a ucode RPC backend. A small LuCI-owned watchdog only records
the user's desired connection state and asks the same RPC backend to reconnect after
transient management-server/network outages.

## Components

| Layer | Path | Role |
|---|---|---|
| Frontend (views) | `htdocs/luci-static/resources/view/netbird/*.js` | 6 tabs: overview / versions / settings / status / setup(network) / logs. All DOM via `E()` (no innerHTML). |
| Frontend helpers | `.../netbird/dom-helpers.js`, `netbird.css` | `pair / code / statusPill` builders. |
| Backend entry | `root/usr/share/rpcd/ucode/netbird.uc` | The `luci.netbird` rpcd object — 31 methods (13 read + 18 write). |
| Backend lib | `root/usr/share/rpcd/ucode/lib/*.uc` | `shell`(quote + timeout probe) · `paths`(binary probe) · `envelope`({ok,err,CODE}) · `netbird_cli`(CLI wrap) · `state`(5-state) · `sanitize`(validation). |
| ACL | `root/usr/share/rpcd/acl.d/luci-app-netbird.json` | read/write method whitelist + UCI scopes. Kept strictly 1:1 with the method table. |
| Settings pipeline | `root/etc/init.d/netbird-settings` | config-only procd service: renders UCI → `netbird up --flags`. |
| Reconnect watchdog | `root/etc/init.d/luci-netbird-watchdog`, `root/usr/share/netbird/netbird-autoreconnect.sh` | procd loop that retries only when `netbird.runtime.desired_connected=1`, with exponential backoff on repeated failures (the status poll stays fixed-interval, so recovery and error-clearing remain prompt); fatal auth errors stop the loop. |
| Config | `root/etc/config/netbird`, `root/etc/config/netbird_bin` | settings, and binary-source (kept separate so changing the download URL does not trigger a netbird reconnect). |
| First-install | `root/etc/uci-defaults/99-luci-app-netbird` | idempotent: seed config, chmod init.d 0755, append identity paths to `sysupgrade.conf`. |

## Single source of truth

**UCI is the only input source; `config.json` is read-only.** The apply chain:

```
write UCI  →  init.d reads UCI  →  netbird up --flag …  →  daemon persists config.json
```

The app never syncs or dual-writes `config.json`. Reads of `config.json` (e.g. to display
the management URL) are display-only.

## Settings application (`init.d/netbird-settings`)

- **Trigger**: LuCI "Save & Apply" commits `/etc/config/netbird`; procd fires a `config.change`
  reload trigger → `reload_service()` renders and applies. (No custom apply button; this also
  gives OpenWRT rollback semantics.)
- **Forward semantics + inversion are centralized here**: the UI is always positive ("Enable X");
  when off, the init.d emits the negative flag (`--disable-X` / `--block-X`). The frontend never
  inverts.
- **Capability gating**: at apply time the script reads `netbird up --help` and only emits flags
  the *running* binary supports; unsupported flags are silently skipped. So switching to an older
  binary never errors out on flags it lacks.
- **Injection-safe**: values are accumulated as `set -- "$@" --flag "$val"` positional parameters
  (no `eval`), equivalent to shell-quoting.
- **Interface-name sync**: renaming the WireGuard interface re-syncs the netbird fw4 zone's
  `list device` *before* netbird re-establishes (firewall reload must precede `netbird up`, or
  forwarding breaks). Only the firewall is reloaded — **never the network** — so even a rename
  never flushes the live device.
- **Pre-shared key is never logged**: it is not placed in `$@`; it is appended only at exec time,
  and logs/dry-run show a static `--preshared-key ***`.

## Versions tab

The tab manages two different update planes and keeps them separate:

1. **NetBird client binary source** — an official file or a versioned custom symlink at
   `/usr/bin/netbird`, the path the upstream procd service hard-codes.
2. **The LuCI app package itself** — checked and upgraded from this fork's GitHub Releases.

### NetBird binary source management

Two sources:

| Source | Active form | Provenance & validation |
|---|---|---|
| **release** | real `/usr/bin/netbird` | Official GitHub tarball, or an existing manually installed binary. Downloads validate checksums when available, ELF architecture and executable version. While custom runs, the official file is parked at `/usr/share/netbird/bin/netbird-release`. |
| **custom** | symlink to `/usr/share/netbird/bin/netbird-v<ver>` | User-selected URL, kept by version for rollback. ELF identity and executable version are checked; optional supplied checksums are enforced. |

The same release-path resolver is used for local metadata and source selection. A manually
installed canonical binary is recognized without package-manager ownership. Selecting the
already-active source does not stop the daemon. Explicit switches stop the daemon and wait
until it exits, then move the official file to/from its parked slot or atomically replace the
custom symlink. Selection is committed only after the target is verified; failed transitions
or failed starts restore and verify the prior file/link and configuration. Existing legacy
release symlinks remain usable and become canonical files on a custom/release round trip.

An official download targets `/usr/bin/netbird` only when release is active; while custom runs
it targets the parked slot and does not stop or overwrite custom. Package installation itself
never adopts, copies or moves a NetBird binary, and does not replace its daemon init script.
The retired distro-binary source is not offered. `opkg`/`apk` still manage this LuCI package and
its runtime dependencies, but are never used to reinstall the separate NetBird daemon package.

Downloads use `_dl_cmd` (curl → uclient-fetch → BusyBox wget), so minimal images need no curl.

**Download durability and cleanup.** Binary downloads that create a new persistent file first run a
best-effort overlay free-space preflight; low space fails early with `insufficient_space` instead of
starting a doomed write. ENOSPC is still handled at write time, and failed first-time writes remove
the half-written target instead of leaving a `netbird-v*` ghost version. Download artifacts must pass
size sanity checks, archive integrity checks (`tar -tzf` for tarballs), checksum checks when
available, ELF e_machine validation, and `netbird version` before they enter the version list. Each
binary operation sweeps old `/tmp/nb-update*` workdirs and stale non-working custom binaries; custom
versions are listed only when the file is executable and can report a version.

**Multi-arch.** This LuCI package is architecture-independent (`PKGARCH:=all`). Official NetBird
auto-selection supports amd64/arm64/386/armv6; other architectures require a matching manually
installed binary or custom URL. Custom downloads are checked against the host's ELF machine,
word size and byte order rather than the four official auto-download choices.

### luci-app-netbird package self-update

The `luci-app-netbird` row has separate user-triggered check/update actions. There is no
scheduled application or binary upgrade; the reconnect watchdog only restores connectivity.
First connection can acquire a missing official binary, not upgrade an already usable one.

- `check_luci_app_update` reads `/InoriHimea/luci-app-netbird/releases/latest/download/manifest.json`
  from GitHub or the configured `cdn_base`, compares package revisions, and selects the
  compatible branch's assets. It does not query the upstream hosted package index.
- `update_luci_app` re-checks and pins downloads to `/releases/download/v<manifest.version>/`.
  Manifest `files[].url` entries are hosted-feed paths and are not used for GitHub downloads.
  Missing required packages or incorrect downloaded sizes fail before the native installer.
- The native transaction installs the complete LuCI package and dependencies, and updates
  `luci-i18n-netbird-zh-cn` only when it is already installed. UI, RPC code, settings/watchdog
  scripts and migration hooks are therefore included; the NetBird binary and identity are not
  replaced by application updates. The installed app version must match the requested one.
- Before the native post-install RPC reload, r5 archives legacy `netbird.uc.bak*`
  files into unique, root-only `/root/netbird-rpcd-backup.*` directories. rpcd scans
  every regular file in its script directory, regardless of suffix; an old backup
  can register the same object first. Native SIGHUP reload re-executes rpcd, so no
  extra management-service restart or NetBird daemon restart is needed.

| OpenWrt series | Package manager | Manifest branch | Package filename |
|---|---|---|---|
| 22.03 / 23.05 / 24.10 | `opkg` | `openwrt-24.10` | `luci-app-netbird_<ver>_all.ipk` |
| 25.12 / current APK snapshots | `apk` | `openwrt-25.12` | `luci-app-netbird-<ver>.apk` |

Older/same revisions are not installed. r3 and older still contain the upstream-feed updater,
so a one-time manual/bootstrap upgrade to r4 is required before the corrected fork updater
can discover subsequent revisions. APK trust still depends on configured signing keys; the
existing `--allow-untrusted` policy is unchanged and does not establish repository-key trust.

On apk systems, installing a package from a file records it in `/etc/apk/world` pinned to that file
(`luci-app-netbird><Q1…`), which makes later `apk upgrade` runs skip it. The package therefore ships
`root/etc/uci-defaults/98-luci-app-netbird-apk-world`: it runs inside the install transaction (where
apk still holds its lock and rewrites `world` at commit), so it only spawns a detached job that waits
for the installing apk process (its parent) to exit and then runs `apk add <name>` for any pinned
`luci-app-netbird` / `luci-i18n-netbird-*` entries. That changes only the constraint, not the
installed version, and also covers updates performed by older in-app updaters and manual file installs.

## State machine

Five runtime-first states (trust the daemon when reachable):
`not_installed` / `service_disabled` / `service_stopped` / `needs_login` / `running`.

## Authentication and failure reporting

The Authentication tab drives upstream NetBird directly through `do_up` / `do_login` /
`do_down` / `do_reconnect` / `do_logout`.

- Setup keys are write-only RPC parameters. A successful login stores only a masked
  `setup_key_hint`; the raw key is never written to UCI or returned to LuCI.
- `do_up` and `do_login` execute `netbird up/login --no-browser` with a bounded
  wall-clock wrapper (25s for the CLI attempt, then a short connected-state poll). This is
  necessary because current NetBird clients can keep retrying when the management server
  rejects an invalid setup key, and LuCI should return a specific reason instead of a generic
  browser timeout.
- After each auth attempt, the backend polls `status --json` for
  `management.connected=true`; it never trusts the CLI exit code alone.
- If the CLI output or newly-added daemon log lines report `setup key is invalid`,
  `PermissionDenied`, `NotFound`, `no peer auth method provided`, or peer removal/login
  expiry, the backend returns `connect_failed` with an actionable message and hint,
  persists the sanitized reason in `netbird.runtime.last_error`, and runs `netbird down`
  to stop the upstream retry loop. It also clears `netbird.runtime.desired_connected` so the
  watchdog will not keep retrying a fatal auth state. It does **not** auto-deregister the local
  identity; that destructive action remains behind the explicit Deregister button.
- `desired_connected` records **user intent** only. Manual `Disconnect` / `Deregister` clear it; a
  user-initiated connect (or existing-identity reconnect) sets it. The watchdog's own reconnect calls
  `do_up` with `caller=watchdog` and does **not** write `desired_connected`, so a deliberate stop is
  never re-asserted by it; it still adopts `desired_connected=1` when it observes an already connected
  daemon, so upgraded routers keep recovering from transient outages without user action.
- `Reconnect` is a single `do_reconnect` RPC that runs `netbird down` and then the `do_up`
  existing-identity path inside the backend. It must not be two browser-side calls: when LuCI is
  reached over the NetBird tunnel, `down` removes the path the second request needs, and `do_down`
  would also clear `desired_connected`, leaving the router disconnected with nothing to bring it
  back. rpcd finishes the method even if the browser connection drops or uhttpd cuts the request,
  and `desired_connected=1` is written before `down`, so the watchdog recovers the connection if
  the call is interrupted.
- The watchdog never stores setup keys. It retries only with the existing local identity, so a
  first-time setup-key registration that fails before success still requires the user to click
  Connect again.
- Transient management/network errors (`Unavailable`, `DeadlineExceeded`, connection refused,
  DNS/timeout-like failures) remain retryable while `desired_connected=1`; fatal auth and
  `NeedsLogin` states are surfaced in `last_error` and stop automatic reconnect.
- A setup-key first-connect that times out without a clear fatal reason also runs `netbird down` and
  clears `desired_connected` (the daemon would otherwise keep retrying that key in the background);
  the empty-key (existing-identity) reconnect path instead leaves `desired_connected=1` for the
  watchdog. The reported reason is the specific transient message when one is classified, not a
  generic timeout.
- The frontend temporarily raises LuCI's global RPC timeout for auth actions and shows
  `last_error` on the Authentication form after a failed attempt, so users see the
  management-server reason instead of a generic XHR timeout.

## Network automation (network tab) — device-bound zone, no netifd interface

The netbird device (`wt0`/etc.) is daemon-managed (overlay IP + peer-subnet routes). The app
**never creates an OpenWRT `network.netbird` interface** for it. An earlier design did, and the
required `reload network` made netifd flush the device's IP/routes — and netbird does **not**
self-heal, so a router managed over the mesh could hard-lock. Instead:

- `setup_firewall_zone` — a dedicated `netbird` fw4 zone bound **directly to the device** via
  `list device '<iface>'` (iface from settings). fw4 matches `iifname/oifname` by name (works even
  before the device exists). **Only `reload firewall` ever runs — never `reload network`** → the
  device's data plane is never flushed (zero remote-lockdown risk).
- `setup_forwarding` — `lan ↔ netbird` forwarding rules, **opt-in, off by default, each direction
  independent**. Disabling a direction flushes the matching conntrack — by **every netbird-routed
  destination** (overlay + peer subnets, IPv4 + IPv6; prefix ≥ /8 excludes near-default/exit-node
  routes so it can never become a full-table flush) — so it takes effect on already-established flows
  **without a reconnect** (best-effort; needs the `conntrack` tool).
- `get_automation_status` — reports `zone_exists` + `zone_device` + both forwarding booleans (no
  interface concept).
- `teardown_automation` — removes only the named zone + forwarding sections (plus, defensively, a
  legacy `network.netbird` interface if an upgraded box still has one — UCI-only, **no
  `reload network`**); **never** touches `lan`/`wan`; reloads only the firewall.
- **Upgrade migration** (uci-defaults, one-time): a box upgraded from the old design has its zone
  converted to device-binding and the legacy `network.netbird` interface removed (UCI-only, no
  `reload network`).
- **Reconnect self-heal**: after `do_up` reconnects and netbird restores its routes, conntrack for
  netbird-routed destinations is flushed (both directions) so in-flight forwarded flows re-establish
  on the restored routes instead of staying pinned to a now-stale route.

### Exit node selection

- `list_exit_nodes` (read) — runs `netbird networks list` (plain text; there is no `--json`), parses
  `ID / Network / Status` entries and returns routes whose range contains `0.0.0.0/0` or `::/0` with
  their selected state. Running-but-disconnected returns `ok` with `connected:false` instead of the
  CLI's "not connected" error. Oversized output (>64 KB) is rejected explicitly — a truncated list
  could mis-report selected states or drop nodes.
- `select_exit_node` (write, `id`; empty = off) — the target must be present in a fresh
  `networks list` (whitelist; arbitrary strings never reach the CLI). Switch = deselect every other
  exit node, then `networks select -a <id>`: `-a` is append semantics — without it the CLI replaces
  the *entire* route selection; the explicit deselect-then-select keeps exit nodes mutually
  exclusive on every netbird version (the daemon-side reconciliation only exists on newer ones).
  Positional ids are passed after `--` (cobra's flag terminator) so leading-dash names work; the
  literal name `all` is excluded on both paths because the CLI treats a sole `all` argument as
  select-all/deselect-all. The daemon keeps its selection in `state.json`, which sits under
  `/var/lib` — tmpfs on OpenWrt, so it does not survive a reboot. Selections made through LuCI are
  therefore also persisted to UCI (`netbird.settings.exit_node`; cleared when switched off).
- `restore_exit_node` (write; watchdog-only, not exposed in the session ACL — the
  automatic-reconnect watchdog calls it as root over local ubus once per boot, gated by a tmpfs
  flag file) — re-applies the persisted selection after the connection is up. Idempotent, and the
  target must be present in a fresh `networks list` (same whitelist as `select_exit_node`), so a
  route deleted in the management console is skipped with a log line instead of retried forever;
  management-console changes always win. Selections made outside LuCI are not persisted.

## Conventions (gotchas worth knowing)

- **ucode modules** load via `loadfile()` IIFE (the runtime build does not support `export`), and
  **do not hoist function declarations** — a helper must be defined textually before its callers.
- **`timeout` is probed by running it**, never by checking that the path exists: a `timeout` symlink can point
  at a BusyBox built without that applet (exits 127, `applet not found`) — and stock OpenWrt BusyBox has no
  `timeout` at all. The backend wraps short commands via `shell.with_timeout(cmd, secs)`, which runs
  `timeout 1 true` once at load; without a working `timeout` it falls back to a portable bound: the command
  runs as `( exec cmd )` in the background with its output in a temp file, and a timer subshell `kill -9`s it
  when time is up (exit 124). The watchdog and `netbird-settings` source the same logic from
  `/usr/share/netbird/nb-run-bounded.sh`. Durations are plain seconds (no `s` suffix).
- **Settings apply never blocks procd.** procd runs config-change triggers one at a time, so a hung
  `netbird-settings` reload stalls every other config apply on the router. When the daemon reports
  `NeedsLogin`, the reload only writes `/etc/netbird-settings.pending` (no `netbird up`, which would wait for an
  SSO login forever); `do_up`/`do_login` re-run the reload in the background after a successful login.
  `down`/`up` are bounded (10 s / 45 s).
- **Unchanged settings do not reconnect.** Runtime fields (connection state, exit node, setup-key hint,
  management URL) live in `/etc/config/netbird`, so `reload_config` from any unrelated LuCI apply fires
  `config.change` for it. `netbird-settings` stores an md5 of the rendered `up` arguments in
  `/var/run/netbird-settings.applied` and skips `down`/`up` when it matches; logout, the post-login pending apply
  and disabling the service delete it.
- **Helper services self-heal.** Some preinstalled firmware images are built without running package scripts, so
  `netbird-settings` and `luci-netbird-watchdog` are never enabled. `do_enable_and_start` and `do_up` enable and
  start them when `/etc/init.d/<svc> enabled` fails.
- **Binary-operation lock and download worker are recoverable.** `/tmp/nb-binop.lock/owner` records the holder
  (`$PPID` of the popen shell: rpcd or the `ucode` worker); a lock whose holder is gone is reclaimed. The async
  download worker's PID is in `/tmp/luci-netbird-binary-download.pid`; `get_binary_update_progress` turns a
  stuck in-progress phase into `failed`/`canceled` when that process is gone.
- **ACL ↔ method table** must stay strictly 1:1 for UI-callable methods (13 read + 17 write = 30
  of the 31 registered methods; the one exception is `restore_exit_node`, which is watchdog-only
  and deliberately kept out of the session ACL).
- **DOM** is built with `E()` only (XSS).
- **Binary/state paths** are probed at runtime, never hard-coded.
- Identity is protected on two axes: `conffiles` (opkg upgrades) and `sysupgrade.conf`
  (firmware flashes).

## Maintenance

`scripts/check-flags.sh` diffs `netbird up --help` against the flags the init.d actually maps,
so upstream additions surface as a reviewable list when bumping the supported NetBird release.

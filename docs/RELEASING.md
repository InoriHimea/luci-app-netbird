# Releasing

The release workflow builds OpenWrt package-feed artifacts and publishes the installable packages and `manifest.json` to GitHub Releases. This fork does not deploy Cloudflare Pages. Signatures are trusted by the checked-in public keys only when the matching `KEY_BUILD` / `PRIVATE_KEY` secrets are configured; a successful build alone does not prove that trust.

## Automatic trigger

Pushes to `main` or `master` run the release workflow only when package code or the
release workflow changes:

- `luci-app-netbird/**`
- `.github/workflows/release.yml`

Changes limited to non-code public material such as `feed/**`, `site/**`, `docs/**`,
`README.md`, or `CHANGELOG.md` do not automatically rebuild or republish packages.
Use the manual `workflow_dispatch` trigger if a rebuild is still desired. The
install/uninstall scripts and landing pages are staged by the workflow but are not
published to a hosted site by this fork.

A `workflow_dispatch` run on any branch other than `main`/`master` only builds and
signs the packages (kept as workflow artifacts); it never creates a Release or
deploys. Use it to test workflow changes before merging.

A running release is never cancelled: a newer push to the same branch waits until
the current run finishes.

## Changelog

Every release must update `CHANGELOG.md` in the same change set: one entry per
shipped version, titled with the full package version and date
(`## x.y.z-rN — YYYY-MM-DD`), followed by notable changes. The `0.2.2` entry keeps
its original title; it shipped as `0.2.2-r1`. The automated GitHub Release notes only list build provenance and assets —
they are not a substitute for the changelog.

## Versions

This is a fork of an open-source project. The package version is `x.y.z-rN`:

- `PKG_VERSION` (`x.y.z`) is always the upstream release this fork is based on. It
  changes only when an upstream release is merged, so the version shows at a glance
  which upstream code a package contains.
- `PKG_RELEASE` (`N`) counts this fork's own releases on top of that upstream
  version. Fork-only fixes and features increase it; merging a new upstream release
  resets it to 1.

| Where | Shows |
| --- | --- |
| Package file names, the feed's `index.json`, what opkg/apk report, `manifest.json` `version`, GitHub Release tag and title, changelog titles | `0.2.2-r2` (tag `v0.2.2-r2`) |
| The app's Versions page | `0.2.2` for `-r1`, otherwise the full version (`0.2.2-r2`) |

The `-rN` suffix is kept on purpose, including `-r1`. Installed copies of this app check for updates
by reading the feed's `index.json`, and they only accept a version in the `x.y.z-rN`
form there. Copies already on routers cannot be changed, so without the suffix their
update check would fail and they would never be offered a new version from the app.
The app compares the full `x.y.z-rN` versions; only the display drops an exact `-r1`.
Any other suffix, such as `0.1.0-r27`, is shown unchanged so two different versions
never look the same.

For a code change that should ship:

- A fork-only change (fix, feature, translation): increase `PKG_RELEASE` in
  `luci-app-netbird/Makefile` and keep `PKG_VERSION`.
- Merging an upstream release: set `PKG_VERSION` to that upstream version and reset
  `PKG_RELEASE` to 1.

## What the workflow does

The workflow reads the package version from the built file names, for example:

- `luci-app-netbird_0.2.2-r1_all.ipk`
- `luci-app-netbird-0.2.2-r1.apk`

It verifies that the ipk and apk builds report the same full version, and then:

- writes the full version to `manifest.json`
- creates the GitHub Release `v<full version>` (for example `v0.2.2-r2`), or updates it
  and replaces its assets if that Release already exists. Installed copies only accept
  a `vX.Y.Z-rN` tag from `releases/latest`, so the suffix is never dropped
- uploads the ipk/apk packages and `manifest.json` as release assets

Application self-update uses this fork's versioned Release assets starting at 0.2.0-r4.
Devices on r3 or older need one manual/bootstrap upgrade because their updater still queries
the upstream hosted feed. Application updates include all package-owned UI, backend and
scripts plus dependencies and already-installed translations, but not the separate NetBird
binary. Since r7, a separate opt-in agent scheduler is installed but disabled by default;
publishing/installing a LuCI package does not enable schedules or upgrade a live agent.

Since r5, the native install hooks archive legacy `netbird.uc.bak*` files outside
`/usr/share/rpcd/ucode/` before the package manager reloads rpcd. The loader does not
filter by extension, so backups in that directory can register an older object first.
Use a directory outside the auto-loaded tree for manual backups. `rpcd reload` uses
SIGHUP to re-execute the management process; do not add a NetBird daemon restart.

Since r6, version discovery uses this fork's Release API through `api_base`. Both the
manifest and package downloads use that version's immutable tag through `cdn_base`;
the manifest must declare the same version. An r4/r5 device affected by a mirror's
cached `latest` manifest needs one version-pinned/bootstrap upgrade to r6.

## Local SDK input from Windows

Use `python scripts/package-input.py <new-output.tar>` to stage the current package, then extract that archive into the SDK feed source directory. The archive includes explicit0755 directory entries,0644 regular files and0755 shebang scripts; UTF-8 text is LF-normalized, including scripts without a filename extension. Binary content is preserved and unexpected symlinks are rejected. Input metadata is deterministic and does not inherit a private staging directory's umask.

Before installing a local candidate, inspect the actual package payload: shared directories must retain0755 and shell scripts must have LF shebangs. Perform a native package install with procd/rpcd and a non-root ubus client before touching a router. `opkg` exit0 alone does not prove that post-install scripts or RPC registration succeeded. The r10/r11 Wuhan trials exposed these staging failures and were not release successes; permissions were repaired from verifiedr7 metadata without restarting the agent.

## r7 deployment gate

Build both OpenWrt branches and verify the version-pinned Release manifest/packages before
installation. Back up package-owned files, UCI, identity, custom init and watchdog privately.
Canary node56 first, then node55 and Shanghai, with Wuhan last. Compare the running agent PID,
binary/profile/init/resolver/watchdog hashes, connection/management/DNS state and existing UCI
values before and after each installation. Verify the real LuCI versions page and the new
RPC/monitor services. Keep agent automation disabled; do not run an agent update, connect,
disconnect, deregister or external-watchdog integration as part of this plugin rollout.
DC is excluded while its presented SSH identity conflicts with pinned keys. Never bypass host
key checking. Failed canary or identity/DNS/process drift stops the rollout and triggers repair
from the retained backup/previous r6 packages.

Releases up to `v0.2.1-r1` keep their existing tags. Because an existing Release is
updated in place, a push to `main` that ships code without bumping the version
overwrites the assets of the current Release.

## Checks before releasing

The workflow does not run these. Run them locally (needs `node` and `ucode`) whenever
login, connection or settings code changes:

```sh
node scripts/test-login-errors.cjs
node scripts/test-config-paths.cjs
```

Whenever the binary download or checksum code changes:

```sh
node scripts/test-update-checksum.cjs
```

Whenever backend code that writes UCI changes, run this in a disposable OpenWrt 22.03
container and in one newer release, because the 22.03 `ucode` cannot commit a single
named config (needs Docker):

```sh
docker run --rm --platform linux/amd64 -v "$PWD:/src:ro" \
  openwrt/rootfs:x86-64-22.03.6 sh /src/scripts/test-uci-commit.sh
docker run --rm --platform linux/amd64 -v "$PWD:/src:ro" \
  openwrt/rootfs:x86-64-25.12.2 sh /src/scripts/test-uci-commit.sh
```

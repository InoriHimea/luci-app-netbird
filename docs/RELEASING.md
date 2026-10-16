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

## Changelog

Every release must update `CHANGELOG.md` in the same change set: one entry per
shipped `PKG_RELEASE` (version, date, notable changes). The automated GitHub
Release notes only list build provenance and assets — they are not a substitute
for the changelog.

## Version source

The release version is extracted from the built package filenames, for example:

- `luci-app-netbird_0.1.0-r2_all.ipk`
- `luci-app-netbird-0.1.0-r2.apk`

The workflow verifies that the ipk and apk builds report the same version. It then:

- writes that version to `manifest.json`
- creates or updates the GitHub Release tag `v<version>`
- uploads the ipk/apk packages and `manifest.json` as release assets

Always bump `PKG_RELEASE` in `luci-app-netbird/Makefile` for a code change that
should ship as a new package revision.

Application self-update uses this fork's versioned Release assets starting at 0.2.0-r4.
Devices on r3 or older need one manual/bootstrap upgrade because their updater still queries
the upstream hosted feed. Application updates include all package-owned UI, backend and
scripts plus dependencies and already-installed translations, but not the separate NetBird
binary. No scheduled unattended upgrade is installed.

Since r5, the native install hooks archive legacy `netbird.uc.bak*` files outside
`/usr/share/rpcd/ucode/` before the package manager reloads rpcd. The loader does not
filter by extension, so backups in that directory can register an older object first.
Use a directory outside the auto-loaded tree for manual backups. `rpcd reload` uses
SIGHUP to re-execute the management process; do not add a NetBird daemon restart.

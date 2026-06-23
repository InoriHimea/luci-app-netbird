# Releasing

The public package feed is built by GitHub Actions and deployed to Cloudflare Pages.

## Automatic trigger

Pushes to `main` or `master` run the release workflow only when package code or the
release workflow changes:

- `luci-app-netbird/**`
- `.github/workflows/release.yml`

Changes limited to non-code public material such as `site/**`, `docs/**`,
`README.md`, or `CHANGELOG.md` do not automatically rebuild or redeploy the feed.
Use the manual `workflow_dispatch` trigger if a rebuild is still desired.

## Version source

The release version is extracted from the built package filenames, for example:

- `luci-app-netbird_0.1.0-r2_all.ipk`
- `luci-app-netbird-0.1.0-r2.apk`

The workflow verifies that the ipk and apk builds report the same version. It then:

- writes that version to `manifest.json`
- creates or updates the GitHub Release tag `v<version>`
- uploads the ipk/apk packages and `manifest.json` as release assets
- deploys the signed feed and landing page to Cloudflare Pages

Always bump `PKG_RELEASE` in `luci-app-netbird/Makefile` for a code change that
should ship as a new package revision.

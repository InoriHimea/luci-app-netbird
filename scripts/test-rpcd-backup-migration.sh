#!/bin/sh
# Only in a disposable container: creates fixtures in system directories.
set -eu
[ -f /.dockerenv ] || { echo 'Run only in a disposable container' >&2; exit 1; }
source_root="${1:-/src}"
hook="$source_root/luci-app-netbird/root/etc/uci-defaults/97-luci-app-netbird-rpcd-backups"
modules=/usr/share/rpcd/ucode
mkdir -p "$modules/lib" /root
printf 'current module\n' > "$modules/netbird.uc"
printf 'unrelated module\n' > "$modules/other.uc.bak"
printf 'first legacy module\n' > /tmp/nb-first-backup
cp /tmp/nb-first-backup "$modules/netbird.uc.bak-20260917"
ln -s netbird.uc "$modules/netbird.uc.bak-link"

IPKG_INSTROOT=/tmp/offline-root sh "$hook"
[ -f "$modules/netbird.uc.bak-20260917" ]
[ -L "$modules/netbird.uc.bak-link" ]

sh "$hook"
set -- /root/netbird-rpcd-backup.*
[ "$#" -eq 1 ]
first_archive="$1"
[ "$(stat -c '%a' "$first_archive")" = 700 ]
cmp /tmp/nb-first-backup "$first_archive/netbird.uc.bak-20260917"
cmp "$modules/netbird.uc" "$first_archive/netbird.uc.bak-link"
[ ! -L "$first_archive/netbird.uc.bak-link" ]
[ ! -e "$modules/netbird.uc.bak-20260917" ]
[ ! -L "$modules/netbird.uc.bak-link" ]
[ "$(cat "$modules/netbird.uc")" = 'current module' ]
[ "$(cat "$modules/other.uc.bak")" = 'unrelated module' ]

sh "$hook"
set -- /root/netbird-rpcd-backup.*
[ "$#" -eq 1 ]

printf 'second legacy module\n' > /tmp/nb-second-backup
cp /tmp/nb-second-backup "$modules/netbird.uc.bak-20260917"
sh "$hook"
set -- /root/netbird-rpcd-backup.*
[ "$#" -eq 2 ]
for archive do
	[ "$archive" = "$first_archive" ] && continue
	cmp /tmp/nb-second-backup "$archive/netbird.uc.bak-20260917"
done
cmp /tmp/nb-first-backup "$first_archive/netbird.uc.bak-20260917"
echo 'PASS: legacy RPC backups archived without shadowing, overwrite or unrelated-file changes'

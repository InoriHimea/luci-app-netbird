#!/bin/sh
# Only in a disposable OpenWrt container: replaces binaries and package-manager fixtures.
set -eu
[ -f /.dockerenv ] || { echo 'Run only in a disposable container' >&2; exit 1; }
source_root="${1:-/src}"
export NBLIB="$source_root/luci-app-netbird/root/usr/share/rpcd/ucode/lib"
export NB_LIBDIR="$source_root/luci-app-netbird/root/usr/share/netbird"
export NB_TEST_ROOT="$source_root"
mkdir -p /tmp/nb-regression-bin /tmp/nb-fixture /usr/share/netbird/bin /etc/config /etc/init.d
export PATH="/tmp/nb-regression-bin:/usr/sbin:/usr/bin:/sbin:/bin"
rm -f /usr/bin/netbird /usr/bin/apk /usr/bin/curl
printf 'config netbird_bin binary\n option binary_source release\n option api_base https://api.fixture.invalid\n option cdn_base https://cdn.fixture.invalid\n' > /etc/config/netbird_bin
printf 'config netbird settings\n option enable_dns 0\n' > /etc/config/netbird
printf "DISTRIB_RELEASE='24.10.5'\n" > /etc/openwrt_release
printf '0.2.0-r3' > /tmp/nb-app-version
: > /tmp/nb-has-i18n
: > /tmp/nb-daemon-running
: > /tmp/nb-service-actions
printf '#!/bin/sh\necho 0.78.1\n' > /usr/bin/netbird
printf '#!/bin/sh\necho 0.70.0\n' > /usr/share/netbird/bin/netbird-release
printf '#!/bin/sh\necho 0.79.0\n' > /usr/share/netbird/bin/netbird-v0.79.0
printf '#!/bin/sh\necho 0.79.1\n' > /usr/share/netbird/bin/netbird-v0.79.1
chmod +x /usr/bin/netbird /usr/share/netbird/bin/netbird-*
cat > /etc/init.d/netbird <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> /tmp/nb-service-actions
case "$1" in
stop) [ -f /tmp/nb-stop-stuck ] || rm -f /tmp/nb-daemon-running ;;
start) : > /tmp/nb-daemon-running; if [ -f /tmp/nb-fail-start ]; then rm -f /tmp/nb-fail-start; exit 1; fi ;;
esac
exit 0
SH
cat > /tmp/nb-regression-bin/ubus <<'SH'
#!/bin/sh
running=false
[ ! -f /tmp/nb-daemon-running ] || running=true
printf '{"netbird":{"instances":{"main":{"running":%s}}}}\n' "$running"
SH
cat > /tmp/nb-regression-bin/ln <<'SH'
#!/bin/sh
if [ -f /tmp/nb-fail-link ]; then rm -f /tmp/nb-fail-link; exit 1; fi
exec /bin/busybox ln "$@"
SH
cat > /tmp/nb-regression-bin/opkg <<'SH'
#!/bin/sh
case "$1:$2" in
list-installed:) printf 'luci-app-netbird - %s\n' "$(cat /tmp/nb-app-version)"; [ ! -f /tmp/nb-has-i18n ] || echo 'luci-i18n-netbird-zh-cn - 0.2.0-r3' ;;
list-installed:luci-app-netbird) printf 'luci-app-netbird - %s\n' "$(cat /tmp/nb-app-version)" ;;
list-installed:luci-i18n-netbird-zh-cn) [ ! -f /tmp/nb-has-i18n ] || echo 'luci-i18n-netbird-zh-cn - 0.2.0-r3' ;;
install:*) : > /tmp/nb-unexpected-install; exit 1 ;;
esac
exit 0
SH
cat > /tmp/nb-fixture/apk <<'SH'
#!/bin/sh
case "$1:$3" in
list:luci-app-netbird) printf 'luci-app-netbird-%s noarch [installed]\n' "$(cat /tmp/nb-app-version)" ;;
list:luci-i18n-netbird-zh-cn) [ ! -f /tmp/nb-has-i18n ] || echo 'luci-i18n-netbird-zh-cn-0.2.0-r3 noarch [installed]' ;;
add:*) : > /tmp/nb-unexpected-install; exit 1 ;;
esac
exit 0
SH
cat > /usr/bin/curl <<'SH'
#!/bin/sh
out=; url=; header=0
while [ "$#" -gt 0 ]; do
 case "$1" in
 -o) out="$2"; shift 2 ;;
 --max-time|--connect-timeout|-H|--header) shift 2 ;;
 -*I*) header=1; shift ;;
 http*) url="$1"; shift ;;
 *) shift ;;
 esac
done
[ "$header" = 0 ] || { printf 'Content-Length: %s\r\n' "$(wc -c < /tmp/nb-fixture.tar.gz)"; exit 0; }
case "$url" in
 */InoriHimea/luci-app-netbird/releases/latest/download/manifest.json) file=/tmp/nb-stale-manifest ;;
 */InoriHimea/luci-app-netbird/releases/download/*/manifest.json) file=/tmp/nb-app-manifest ;;
 */InoriHimea/luci-app-netbird/releases/download/*) file=/tmp/nb-app-body ;;
 */repos/InoriHimea/luci-app-netbird/releases/latest)
  if [ -f /tmp/nb-app-release ]; then cat /tmp/nb-app-release; else
   ucode -e 'import { readfile } from "fs"; print(sprintf("%J", { tag_name: "v" + json(readfile("/tmp/nb-app-manifest")).version }));'
  fi
  exit 0 ;;
 */repos/netbirdio/netbird/releases/latest) printf '{"tag_name":"v0.80.0"}'; exit 0 ;;
 */netbird_0.80.0_linux_amd64.tar.gz) file=/tmp/nb-fixture.tar.gz ;;
 */netbird_0.80.0_checksums.txt) file=/tmp/nb-checksums ;;
 *) exit 22 ;;
esac
if [ -n "$out" ]; then cp "$file" "$out"; else cat "$file"; fi
SH
chmod +x /etc/init.d/netbird /tmp/nb-regression-bin/* /tmp/nb-fixture/apk /usr/bin/curl
# A real native ELF with an inert version script; no VPN connection is started.
cp /usr/bin/ucode /tmp/nb-fixture/netbird
dd if=/dev/urandom bs=1024 count=1200 >> /tmp/nb-fixture/netbird 2>/dev/null
printf '0.80.0' >> /tmp/nb-fixture/netbird
chmod +x /tmp/nb-fixture/netbird
cat > /version <<'UCODE'
import { readfile } from 'fs';
let data = readfile('/proc/self/exe');
print(substr(data, length(data) - 6) + '\n');
UCODE
tar -czf /tmp/nb-fixture.tar.gz -C /tmp/nb-fixture netbird
sum=$(sha256sum /tmp/nb-fixture.tar.gz)
printf '%s  netbird_0.80.0_linux_amd64.tar.gz\n' "${sum%% *}" > /tmp/nb-checksums
printf 'truncated' > /tmp/nb-app-body
cat > /tmp/nb-contract-check.uc <<'UCODE'
import { open, readfile, unlink } from 'fs';
import * as uci from 'uci';
function check(condition, message) { if (!condition) die(message); }
function put(path, value) { let f = open(path, 'w'); check(f != null, 'fixture open failed'); f.write(value); f.close(); }
function service() { return loadfile(getenv('NB_TEST_ROOT') + '/luci-app-netbird/root/usr/share/rpcd/ucode/netbird.uc')()['luci.netbird']; }
function configured() { return uci.cursor().get('netbird_bin', 'binary', 'binary_source'); }
let svc = service();
let info = svc.get_binary_info.call({});
check(info.ok && info.data.release.installed && info.data.release.version == '0.78.1' && info.data.release.path == '/usr/bin/netbird', sprintf('manual binary misidentified: %J', info));
let original = readfile('/usr/bin/netbird');
let result = svc.set_binary_source.call({ source: 'release' });
check(result.ok && result.data.already && readfile('/tmp/nb-service-actions') == '', 'already-selected release restarted the daemon');
result = svc.set_binary_source.call({ source: 'custom', version: '9.9.9' });
check(!result.ok && result.code == 'not_installed' && configured() == 'release' && readfile('/usr/bin/netbird') == original, 'missing target changed active selection');
result = svc.set_binary_source.call({ source: 'custom', version: '0.79.0' });
check(result.ok && configured() == 'custom' && system('[ -L /usr/bin/netbird ]') == 0, sprintf('custom activation failed: %J', result));
check(readfile('/usr/share/netbird/bin/netbird-release') == original, 'official binary lost on custom activation');
let custom = readfile('/usr/share/netbird/bin/netbird-v0.79.0');
let actions = readfile('/tmp/nb-service-actions');
result = svc.update_binary.call({});
check(result.ok && result.data.to == '0.80.0' && result.data.path == '/usr/share/netbird/bin/netbird-release', sprintf('inactive official update failed: %J', result));
check(configured() == 'custom' && readfile('/usr/bin/netbird') == custom && system('[ -L /usr/bin/netbird ]') == 0, 'official update overwrote active custom');
check(readfile('/tmp/nb-service-actions') == actions, 'inactive official update restarted custom daemon');
result = svc.set_binary_source.call({ source: 'release' });
check(result.ok && configured() == 'release' && system('[ ! -L /usr/bin/netbird ]') == 0, sprintf('release return failed: %J', result));
let official = readfile('/usr/bin/netbird');
check(official == readfile('/tmp/nb-fixture/netbird') && readfile('/usr/share/netbird/bin/netbird-v0.79.0') == custom, 'round trip lost binary bytes');
put('/tmp/nb-fail-link', '1');
result = svc.set_binary_source.call({ source: 'custom', version: '0.79.0' });
check(!result.ok && configured() == 'release' && readfile('/usr/bin/netbird') == official && system('[ ! -L /usr/bin/netbird ]') == 0, 'failed custom switch did not restore release');
put('/tmp/nb-fail-start', '1');
result = svc.set_binary_source.call({ source: 'custom', version: '0.79.0' });
check(!result.ok && configured() == 'release' && readfile('/usr/bin/netbird') == official && system('[ ! -L /usr/bin/netbird ] && [ -e /tmp/nb-daemon-running ]') == 0, 'failed daemon start did not restore the prior binary and selection');
check(svc.set_binary_source.call({ source: 'custom', version: '0.79.0' }).ok, 'custom setup failed');
put('/tmp/nb-fail-link', '1');
result = svc.set_binary_source.call({ source: 'custom', version: '0.79.1' });
check(!result.ok && configured() == 'custom' && readfile('/usr/bin/netbird') == custom && readfile('/usr/share/netbird/bin/netbird-release') == official, 'failed custom-to-custom switch lost prior selection');
check(svc.set_binary_source.call({ source: 'release' }).ok, 'release setup failed');
check(system('mv /usr/bin/netbird /usr/share/netbird/bin/netbird-release && /bin/busybox ln -s /usr/share/netbird/bin/netbird-release /usr/bin/netbird') == 0, 'legacy fixture failed');
info = svc.get_binary_info.call({});
check(info.data.release.installed && info.data.release.version == '0.80.0', 'legacy release alias not recognized');
check(svc.set_binary_source.call({ source: 'custom', version: '0.79.0' }).ok && svc.set_binary_source.call({ source: 'release' }).ok, 'legacy round trip failed');
check(system('[ ! -L /usr/bin/netbird ]') == 0 && readfile('/usr/bin/netbird') == official, 'legacy round trip did not restore canonical file');
put('/tmp/nb-stop-stuck', '1');
result = svc.set_binary_source.call({ source: 'custom', version: '0.79.0' });
check(!result.ok && configured() == 'release' && readfile('/usr/bin/netbird') == official, 'stop failure changed the active binary');
unlink('/tmp/nb-stop-stuck');
print('PASS: manual/legacy release, round trips, inactive updates, failed links and stuck daemon\n');

function manifest(version, language) {
    let branches = {};
    for (let format in ['ipk', 'apk']) {
        let main = format == 'ipk' ? 'luci-app-netbird_' + version + '_all.ipk' : 'luci-app-netbird-' + version + '.apk';
        let lang = format == 'ipk' ? 'luci-i18n-netbird-zh-cn_' + version + '_all.ipk' : 'luci-i18n-netbird-zh-cn-' + version + '.apk';
        let files = [{ name: main, size: 3000, url: '/obsolete/feed/' + main }];
        if (language) push(files, { name: lang, size: 1000, url: '/obsolete/feed/' + lang });
        branches[format == 'ipk' ? 'openwrt-24.10' : 'openwrt-25.12'] = { format: format, files: files };
    }
    return { version: version, branches: branches };
}
put('/tmp/nb-app-manifest', sprintf('%J', manifest('0.2.0-r4', true)));
put('/tmp/nb-stale-manifest', sprintf('%J', manifest('0.2.0-r3', true)));
info = service().check_luci_app_update.call({});
check(info.ok && info.data.update_available && info.data.main_package == 'luci-app-netbird_0.2.0-r4_all.ipk' && info.data.i18n_package == 'luci-i18n-netbird-zh-cn_0.2.0-r4_all.ipk', sprintf('fork IPK selection failed: %J', info));
check(info.data.feed_url == 'https://cdn.fixture.invalid/InoriHimea/luci-app-netbird/releases/download/v0.2.0-r4/', 'downloads not pinned to fork tag/mirror');
put('/tmp/nb-app-release', '{"tag_name":"v0.2.0-r5"}');
info = service().check_luci_app_update.call({});
check(!info.ok && info.code == 'parse_error', 'manifest for another release tag accepted');
unlink('/tmp/nb-app-release');
result = service().update_luci_app.call({});
check(!result.ok && result.code == 'download_failed' && system('[ ! -e /tmp/nb-unexpected-install ]') == 0, 'truncated application package reached installer');
put('/tmp/nb-app-manifest', sprintf('%J', manifest('0.2.0-r2', true)));
info = service().check_luci_app_update.call({});
check(info.ok && !info.data.update_available, 'older fork revision offered as update');
put('/tmp/nb-app-manifest', sprintf('%J', manifest('0.2.0-r4', false)));
info = service().check_luci_app_update.call({});
check(!info.ok && info.code == 'parse_error', 'missing installed language package accepted');
unlink('/tmp/nb-has-i18n');
info = service().check_luci_app_update.call({});
check(info.ok && info.data.i18n_package == '', 'uninstalled language was added by update');
put('/tmp/nb-has-i18n', '1');
check(system('cp /tmp/nb-fixture/apk /usr/bin/apk') == 0, 'apk fixture failed');
put('/etc/openwrt_release', "DISTRIB_RELEASE='25.12.2'\n");
put('/tmp/nb-app-manifest', sprintf('%J', manifest('0.2.0-r4', true)));
info = service().check_luci_app_update.call({});
check(info.ok && info.data.main_package == 'luci-app-netbird-0.2.0-r4.apk' && info.data.i18n_package == 'luci-i18n-netbird-zh-cn-0.2.0-r4.apk' && info.data.pkg_mgr == 'apk', sprintf('fork APK selection failed: %J', info));
let bad = manifest('0.2.0-r4', true);
bad.branches['openwrt-25.12'].format = 'ipk';
put('/tmp/nb-app-manifest', sprintf('%J', bad));
info = service().check_luci_app_update.call({});
check(!info.ok && info.code == 'parse_error', 'wrong package format accepted');
put('/tmp/nb-app-manifest', sprintf('%J', manifest('../bad', true)));
info = service().check_luci_app_update.call({});
check(!info.ok && info.code == 'parse_error', 'unsafe release version accepted');
print('PASS: stale CDN discovery, tag/manifest binding, pinned downloads, IPK/APK selection and translation boundaries\n');
UCODE
# ucode's fixture executable reads the relative script named "version".
cd /
ucode /tmp/nb-contract-check.uc

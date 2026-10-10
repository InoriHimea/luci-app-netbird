#!/bin/sh
# 在一次性 OpenWrt 容器中验证真实后端调用，禁止在路由器上运行。
# docker run --rm --platform linux/amd64 -v "$PWD:/src:ro" \
#   openwrt/rootfs:x86-64-openwrt-25.12 sh /src/scripts/test-timeout.sh
set -eu
[ -f /.dockerenv ] || { echo '需要一次性容器环境' >&2; exit 1; }
source_root="${1:-/src}"
export NBLIB="$source_root/luci-app-netbird/root/usr/share/rpcd/ucode/lib"
mkdir -p /tmp/nb-test-bin /usr/share/netbird/bin /etc/init.d
export PATH="/tmp/nb-test-bin:/usr/sbin:/usr/bin:/sbin:/bin"
cat > /usr/bin/netbird <<'EOF'
#!/bin/sh
case "$1" in
version) echo 0.73.2 ;;
status) echo '{"daemonVersion":"0.73.2","daemonStatus":"Connected","management":{"connected":true}}' ;;
*) exit 1 ;;
esac
EOF
cat > /usr/share/netbird/bin/netbird-release <<'EOF'
#!/bin/sh
echo 0.80.0
EOF
cat > /usr/bin/apk <<'EOF'
#!/bin/sh
case "$3" in
netbird) echo 'netbird-0.73.2-r1 x86_64 [installed]' ;;
luci-app-netbird) echo 'luci-app-netbird-0.1.0-r22 noarch [installed]' ;;
*) exit 1 ;;
esac
EOF
cat > /tmp/nb-test-bin/ubus <<'EOF'
#!/bin/sh
printf '{"netbird":{"instances":{"instance1":{"running":%s}}}}\n' "${NB_TEST_RUNNING:-true}"
EOF
cat > /tmp/nb-test-bin/pgrep <<'EOF'
#!/bin/sh
exit 1
EOF
cat > /etc/init.d/netbird <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x /usr/bin/netbird /usr/bin/apk /usr/share/netbird/bin/netbird-release /tmp/nb-test-bin/ubus /tmp/nb-test-bin/pgrep /etc/init.d/netbird
cat > /tmp/nb-exit-nine <<'EOF'
#!/bin/sh
exit 9
EOF
chmod +x /tmp/nb-exit-nine
sed '/^while :; do/,$d' "$source_root/luci-app-netbird/root/usr/share/netbird/netbird-autoreconnect.sh" > /tmp/nb-watchdog-functions.sh
cat >> /tmp/nb-watchdog-functions.sh <<'EOF'
_with_timeout_status /usr/bin/netbird --json
EOF
cat > /tmp/nb-timeout-check.uc <<'EOF'
let svc = loadfile(getenv('NB_TEST_ROOT') + '/luci-app-netbird/root/usr/share/rpcd/ucode/netbird.uc')()['luci.netbird'];
let info = svc.get_binary_info.call({});
if (!info.ok || info.data.running_version != '0.73.2' ||
    info.data.luci_app_version != '0.1.0-r22' || info.data.release.version != '0.80.0')
    die(sprintf('版本查询失败: %J', info));
let state = svc.get_status.call({});
if (!state.ok || state.data.status != (getenv('NB_TEST_EXPECT_STATUS') || 'running'))
    die(sprintf('服务状态错误: %J', state));
let shell = loadfile(getenv('NBLIB') + '/shell.uc')();
if (system(shell.with_timeout('/tmp/nb-exit-nine')) != 9)
    die('命令失败退出码被吞掉');
print('版本、落盘文件校验、服务状态通过\n');
EOF
check_watchdog() {
    sh /tmp/nb-watchdog-functions.sh > /tmp/nb-watchdog-status
    grep -F '"daemonStatus":"Connected"' /tmp/nb-watchdog-status
}
check_backend() {
    ucode /tmp/nb-timeout-check.uc
    NB_TEST_RUNNING=false NB_TEST_EXPECT_STATUS=service_stopped ucode /tmp/nb-timeout-check.uc
}
export NB_TEST_ROOT="$source_root"
# 先删除再写:系统自带的 timeout 可能是指向 busybox 的链接,直接重定向会改写 busybox 本体。
rm -f /usr/bin/timeout
cat > /usr/bin/timeout <<'EOF'
#!/bin/sh
echo 'timeout: applet not found' >&2
exit 127
EOF
chmod +x /usr/bin/timeout
echo '场景：timeout 路径可执行，但功能不存在'
check_backend
check_watchdog
rm /usr/bin/timeout
echo '场景：timeout 不存在'
check_backend
check_watchdog
rm -f /usr/bin/timeout
cat > /usr/bin/timeout <<'EOF'
#!/bin/sh
case "$1" in
1|5|6) shift ;;
*) echo '错误的 timeout 秒数' >&2; exit 2 ;;
esac
printf '%s\n' "$*" >> /tmp/nb-timeout-calls
exec "$@"
EOF
chmod +x /usr/bin/timeout
echo '场景：timeout 可用，实际命令经过包装'
check_backend
check_watchdog
grep -Fx '/usr/share/netbird/bin/netbird-release version' /tmp/nb-timeout-calls
grep -Fx 'apk list --installed luci-app-netbird' /tmp/nb-timeout-calls
grep -Fx '/usr/bin/netbird status --json' /tmp/nb-timeout-calls
echo 'timeout 回归通过'

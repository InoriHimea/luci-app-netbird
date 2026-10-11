#!/bin/sh
# 在一次性 OpenWrt 容器中验证 watchdog 脚本收到 TERM 后能及时退出、不遗留 sleep 子进程，禁止在路由器上运行。
# docker run --rm --platform linux/amd64 -v "$PWD:/src:ro" \
#   openwrt/rootfs:x86-64-25.12.2 sh /src/scripts/test-autoreconnect-signal.sh
set -u
[ -f /.dockerenv ] || { echo '需要一次性容器环境' >&2; exit 1; }
source_root="${1:-/src}"
prog="$source_root/luci-app-netbird/root/usr/share/netbird/netbird-autoreconnect.sh"
# 脚本引入的共用有界执行函数随包装在 /usr/share/netbird,此处指向源码目录
export NB_LIBDIR="$source_root/luci-app-netbird/root/usr/share/netbird"
# 用不常见的间隔值标识脚本自己派生的 sleep,避免与其他进程混淆
export NB_AUTORECONNECT_INTERVAL=37
fail=0

sh -n "$prog" || { echo 'FAIL: 语法检查未通过'; exit 1; }

_sleep_children() {
	ps w 2>/dev/null | grep '[s]leep 37' | wc -l
}

_kill_sleep_children() {
	ps w 2>/dev/null | grep '[s]leep 37' | awk '{print $1}' | while read -r p; do kill "$p" 2>/dev/null; done
}

# 参数:场景名。脚本启动后先进入等待,再发 TERM,要求 2 秒内退出且无残留 sleep。
# BusyBox sleep 未必支持小数,按整秒轮询。
_check_term() {
	name="$1"
	sh "$prog" &
	pid=$!
	sleep 2
	if ! kill -0 "$pid" 2>/dev/null; then
		echo "FAIL[$name]: 脚本在发送信号前已退出"
		fail=1
		return
	fi
	[ "$(_sleep_children)" -ge 1 ] || echo "WARN[$name]: 未观察到等待中的 sleep"
	kill -TERM "$pid"
	i=0
	while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 2 ]; do
		sleep 1
		i=$((i + 1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		echo "FAIL[$name]: TERM 后 2 秒仍未退出"
		kill -KILL "$pid" 2>/dev/null
		fail=1
	else
		wait "$pid" 2>/dev/null
		echo "ok[$name]: TERM 后 ${i} 秒内退出"
	fi
	left="$(_sleep_children)"
	if [ "$left" -ne 0 ]; then
		echo "FAIL[$name]: 残留 $left 个 sleep 子进程"
		_kill_sleep_children
		fail=1
	fi
}

# 场景一:找不到 netbird,直接进入等待
rm -f /usr/bin/netbird /usr/sbin/netbird
_check_term no-binary

# 场景二:已连接分支的等待
cat > /usr/bin/netbird <<'STUB'
#!/bin/sh
case "$1" in
status) echo '{"daemonStatus":"Connected","management":{"connected":true}}' ;;
*) exit 1 ;;
esac
STUB
chmod +x /usr/bin/netbird
_check_term connected

[ "$fail" -eq 0 ] && echo 'PASS' || { echo 'FAIL'; exit 1; }

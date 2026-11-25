#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# netbird-autoreconnect.sh — 保守自动重连:
# - 只有 netbird.runtime.desired_connected=1 时才尝试恢复。
# - 已连接且意图缺失时才 adopt;显式断开不会被采样覆盖。
# - 认证 fatal / NeedsLogin 会置 desired_connected=0,避免无限重试。
# - 不保存 setup key;首次注册失败仍要求用户重新点击连接。

TAG="luci-netbird-watchdog"
INTERVAL="${NB_AUTORECONNECT_INTERVAL:-30}"
# 有界执行与守护进程日志级别下发,与 netbird-settings 共用。
. "${NB_LIBDIR:-/usr/share/netbird}/nb-run-bounded.sh"
. "${NB_LIBDIR:-/usr/share/netbird}/nb-log-level.sh"
# 重连连续失败时指数退避(INTERVAL→2x→…→封顶 MAX_INTERVAL),连上即复位;
# 避免长时间 outage 每 INTERVAL 秒一次高成本 do_up + 日志刷屏。
MAX_INTERVAL="${NB_AUTORECONNECT_MAX_INTERVAL:-300}"
backoff="$INTERVAL"
attempt_wait=0   # 距下次重连尝试还需等待的秒数(按 INTERVAL 递减);轮询本身不退避,保证恢复/清错及时

# 收到 procd/系统 TERM/INT 立即退出,避免拖慢 stop/reboot。
# ash 要等前台子进程结束才执行 trap,前台 sleep 会让 TERM 拖满整个 INTERVAL、
# 被 procd 超时后 SIGKILL 并遗留孤儿 sleep;故等待一律走 _sleep(后台 sleep + wait,
# wait 可被信号打断),trap 里顺带结束该 sleep。ubus 调用仍是前台执行,
# 信号会推迟到其结束(原生调用有超时兜底)。
_sleep_pid=""

_on_signal() {
	[ -n "$_sleep_pid" ] && kill "$_sleep_pid" 2>/dev/null
	exit 0
}

trap _on_signal TERM INT

_sleep() {
	sleep "$1" &
	_sleep_pid=$!
	wait "$_sleep_pid"
	_sleep_pid=""
}

_log() {
	logger -t "$TAG" "$*"
}

_reset_backoff() {
	backoff="$INTERVAL"
}

_bump_backoff() {
	backoff=$((backoff * 2))
	[ "$backoff" -gt "$MAX_INTERVAL" ] && backoff="$MAX_INTERVAL"
}

# 守护进程重启(崩溃被 procd 拉起、手动 restart、换二进制)后日志级别回到 info。
# 只在 watchdog_step 确认守护进程有响应(connected / authentication_required)时补下发;
# nb_sync_log_level 记录已下发的 PID+级别,两者都没变时不调用 netbird。
_maybe_sync_log_level() {
	bin="$(command -v netbird 2>/dev/null)"
	[ -n "$bin" ] || { [ -x /usr/bin/netbird ] && bin=/usr/bin/netbird; } || return 0
	nb_sync_log_level "$bin" >/dev/null 2>&1
}

EXITNODE_FLAG="/var/run/netbird-luci-exitnode.restored"

_maybe_restore_exit_node() {
	[ -f "$EXITNODE_FLAG" ] && return 0
	en="$(uci -q get netbird.settings.exit_node 2>/dev/null)"
	if [ -z "$en" ]; then
		touch "$EXITNODE_FLAG" 2>/dev/null
		return 0
	fi
	out="$(ubus -t 30 call luci.netbird restore_exit_node 2>/dev/null)"
	case "$out" in
	*'"result": "restored"'*)
		touch "$EXITNODE_FLAG" 2>/dev/null
		_log "restored exit node \"$en\" after restart" ;;
	*'"result": "already-selected"'*|*'"result": "not-configured"'*)
		touch "$EXITNODE_FLAG" 2>/dev/null ;;
	*'"result": "not-found"'*)
		touch "$EXITNODE_FLAG" 2>/dev/null
		_log "configured exit node \"$en\" is not available on this network; leaving it unselected" ;;
	*)
		: ;;
	esac
}

# The native RPC rereads status and intent under the shared action owner. Never
# replay shell observations into UCI, down, or up; partial upgrades fail closed.
last_failure=0
while :; do
	recover=false
	[ "$attempt_wait" -le 0 ] && recover=true
	out="$(ubus -t 90 call luci.netbird watchdog_step "{\"pid\":$$,\"recover\":$recover}" 2>/dev/null)"
	state="$(printf '%s\n' "$out" | sed -n 's/.*"state":[[:space:]]*"\([a-z_]*\)".*/\1/p')"
	case "$state" in
	connected)
		_reset_backoff
		attempt_wait=0
		last_failure=0
		_maybe_sync_log_level
		_maybe_restore_exit_node
		;;
	attempted)
		attempt_wait="$backoff"
		_bump_backoff
		last_failure=0
		;;
	authentication_required)
		_reset_backoff
		attempt_wait=0
		last_failure=0
		_maybe_sync_log_level
		;;
	stopped|not_installed)
		_reset_backoff
		attempt_wait=0
		last_failure=0
		;;
	disconnected|maintenance) : ;;
	*)
		[ "$last_failure" = 1 ] || _log 'action policy or owner unavailable; leaving connection intent and agent unchanged'
		last_failure=1
		;;
	esac
	[ "$attempt_wait" -gt 0 ] && attempt_wait=$(( attempt_wait - INTERVAL ))
	_sleep "$INTERVAL"
done

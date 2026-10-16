#!/bin/sh
# luci-app-netbird —— 一键安装(添加软件源,安装本插件 + 简体中文语言包)。
# 用法:  sh -c "$(curl -fsSL https://luci-app-netbird.okk.sh/install-zh.sh)"
#   或:  wget -O - https://luci-app-netbird.okk.sh/install-zh.sh | sh
set -e

REPO="https://luci-app-netbird.okk.sh"

# 添加软件源。先把 feed.sh 下载到文件再执行:`wget | sh` 在下载失败时 sh 读到空输入、
# 退出码为 0,会在没有软件源的情况下继续安装。
FEED_SH="$(mktemp)"
trap 'rm -f "$FEED_SH"' EXIT
if command -v wget >/dev/null 2>&1; then
	wget -O "$FEED_SH" "$REPO/feed.sh"
else
	curl -fsSL -o "$FEED_SH" "$REPO/feed.sh"
fi
[ -s "$FEED_SH" ] || { echo "无法下载 $REPO/feed.sh" >&2; exit 1; }
sh "$FEED_SH"

# 安装本插件 + 简体中文语言包
if [ -x /bin/opkg ]; then
	opkg install luci-app-netbird luci-i18n-netbird-zh-cn
else
	apk add luci-app-netbird luci-i18n-netbird-zh-cn
fi

echo ""
echo "完成。打开 LuCI -> 服务 -> NetBird。"

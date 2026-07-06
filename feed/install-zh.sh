#!/bin/sh
# luci-app-netbird —— 一键安装(添加软件源,安装本插件 + 简体中文语言包)。
# 用法:  sh -c "$(curl -fsSL https://luci-app-netbird.okk.sh/install-zh.sh)"
#   或:  wget -O - https://luci-app-netbird.okk.sh/install-zh.sh | sh
set -e

REPO="https://luci-app-netbird.okk.sh"

# 添加软件源
wget -O - "$REPO/feed.sh" | sh

# 安装本插件 + 简体中文语言包
if [ -x /bin/opkg ]; then
	opkg install luci-app-netbird luci-i18n-netbird-zh-cn
else
	apk add luci-app-netbird luci-i18n-netbird-zh-cn
fi

echo ""
echo "完成。打开 LuCI -> 服务 -> NetBird。"

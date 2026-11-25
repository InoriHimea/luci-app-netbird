# SPDX-License-Identifier: Apache-2.0
#
# luci-app-netbird — LuCI app to manage the NetBird mesh-VPN client.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for NetBird
LUCI_DESCRIPTION:=LuCI web interface to manage the NetBird mesh-VPN client \
	(authentication, connection, settings, peers status and logs).
# 全部运行时依赖走 EXTRA_DEPENDS:只写进包 control/PKGINFO 的 Depends,不触发 SDK 去
# 编译它们的 target 链。原因:
#   - +netbird 会拖 golang/host(C23 typedef bool 冲突)
#   - +luci-base 会拖 lucihttp(SDK 缺 ucode/module.h)
# 这些包在目标机由 opkg/apk 提供;control/PKGINFO 的 Depends 仍完整列出,运行时正常解析。
# 格式(apk):**逗号分隔 + 每项带版本约束**。OWRT25 apk 路径(CONFIG_USE_APK)经
# include/package-pack.mk 的 FormatDepends 处理 EXTRA_DEPENDS,要求逗号分隔且每项必须有版本
# 约束(无约束直接 $(error);空格分隔会被当成单项 "netbird (版本约束 rpcd)" 致依赖搅烂成
# netbirdrpcd、其余丢失——apk add 下如此)。`(>=0)`=任意版本;此格式对 ipk(原样塞入版本化
# Depends,opkg 接受)与 apk 同时成立。参照 luci-app-adguardhome 同类(golang)惯例。
# 不列 libuci:apk 下它是 **ABI 版本化**包(目标上叫 libuci20250120,`apk list libuci` 为空),
# SDK 的 GetABISuffix 在 SDK 上下文取不到其 ABI 后缀 → 渲染成裸 libuci>=0 在目标无法解析
# (apk add 下 breaks);且 libuci 被 rpcd/rpcd-mod-ucode/uci 传递依赖保证存在,无需显式列。
LUCI_DEPENDS:=
# ucode / ucode-mod-fs / ucode-mod-uci:后端 import 'fs'/'uci',后台下载任务调用 ucode 命令行;
# 22.03 的 luci-base 不依赖它们(靠 firewall4 间接装上),精简或 fw3 固件上会缺。
# conntrack:网络页「删除转发规则即时断开已建连接」靠 conntrack 定向 flush;缺它会静默
# 退化为只挡新流、已建流持续。列入依赖使该行为在所有部署一致可靠。
LUCI_EXTRA_DEPENDS:=rpcd (>=0), rpcd-mod-ucode (>=0), ucode (>=0), ucode-mod-fs (>=0), ucode-mod-uci (>=0), ucode-mod-uloop (>=0), ucode-mod-socket (>=0), luci-base (>=0), conntrack (>=0)
LUCI_PKGARCH:=all
LUCI_URL:=https://github.com/InoriHimea/luci-app-netbird
LUCI_MAINTAINER:=looong-cat <foxhis11@gmail.com>

PKG_NAME:=luci-app-netbird
PKG_VERSION:=0.2.2
PKG_RELEASE:=3
PKG_MAINTAINER:=looong-cat <foxhis11@gmail.com>
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

# i18n 子包版本跟随主包 release。luci.mk 默认 PKG_PO_VERSION=findrev(luci 仓 git rev),
# 在 luci 树外 standalone 构建时恒为 "0" → 每次发布 i18n 子包版本不变,opkg 把"同版本"
# 子包当已最新而跳过升级,译文更新到不了 opkg 升级用户(apk 则照常 replace、不受影响)。
# 固定为主包版本(PKG_RELEASE 长期为 1),PKG_VERSION 递增时 i18n 子包版本一并递增 → opkg 升级也刷新 .lmo。
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

# /etc/config/netbird 标记为 conffile:opkg 升级不覆盖用户配置;
# 刷机保护由 uci-defaults 追加 /etc/sysupgrade.conf 负责。
# 注:须在 luci.mk include 之前定义 —— luci.mk 内部会调用 BuildPackage,
# 之后定义就来不及被收录。
define Package/luci-app-netbird/conffiles
/etc/config/netbird
/etc/config/netbird_bin
/etc/config/netbird_health
endef

# 替换 luci.mk 默认的安装脚本,只改一处:不发 HUP,改为约 5 秒后在脱离当前会话的
# 后台执行 /etc/init.d/rpcd restart。
# - 延迟:22.03、23.05 的 rpcd 重载时不再回复进行中的调用;从页面更新本插件时
#   update_luci_app 必须先把结果返回给页面,否则安装成功页面却超时报失败。
# - restart 而非 HUP:rpcd 收 HUP 后 execv 自身,ucode(24.10/25.12 未含上游
#   1dd1f88c81)给每个已编译源文件常驻一个无 O_CLOEXEC 的 fd,每次重载整代继承,
#   多次升级后 rpcd 描述符累积。restart 起新进程,描述符回到基线;代价是 LuCI
#   会话丢失,页面提示重新登录。
# - setsid:脱离安装者(rpcd → opkg/apk)的会话和进程组,rpcd 停止时不连带。
#   22.03 的 busybox 没有 setsid,改用 start-stop-daemon -b(同样新建会话);
#   -p 指向不存在的 pid 文件,避免按 /bin/sh 匹配到已有进程而拒绝启动。
# 其余两行和默认脚本相同。
define Package/$(PKG_NAME)/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	if command -v setsid >/dev/null 2>&1; then
		setsid sh -c 'sleep 5; /etc/init.d/rpcd restart' </dev/null >/dev/null 2>&1 &
	elif command -v start-stop-daemon >/dev/null 2>&1; then
		start-stop-daemon -S -b -p /var/run/luci-netbird-rpcd-restart.pid -x /bin/sh -- \
			-c 'sleep 5; /etc/init.d/rpcd restart' </dev/null >/dev/null 2>&1
	else
		( sleep 5; /etc/init.d/rpcd restart ) </dev/null >/dev/null 2>&1 &
	fi
	exit 0
}
endef

# luci.mk 内部已 $(eval $(call BuildPackage,...)),不要再重复调用(否则 package
# 重复定义报错)。
include $(TOPDIR)/feeds/luci/luci.mk

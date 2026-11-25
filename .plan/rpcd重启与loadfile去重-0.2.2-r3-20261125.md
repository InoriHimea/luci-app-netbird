# rpcd 重启替代 HUP + loadfile 去重 — 0.2.2-r3 — 2026-11-25

背景：TODO.md 11-25「rpcd fd泄漏」调查。ucode 2025.07.18（24.10）/2026.07.09（25.12）每个已编译源文件常驻一个无 O_CLOEXEC 的 fd；rpcd 收 HUP 后 execv 自身，整代 fd 继承。本插件 postinst 的延迟 HUP 每次升级累积一代（武汉约 61 个），上限 1024。

版本：fork 规则，`PKG_VERSION=0.2.2` 不变，`PKG_RELEASE` 2 → 3，tag `v0.2.2-r3`。

## 实现

- [x] Makefile postinst：去掉 `killall -HUP rpcd`，改为约 5 秒后脱离会话执行 `/etc/init.d/rpcd restart`：有 `setsid` 用 setsid；22.03 busybox 无 setsid 时用 `start-stop-daemon -b`；都没有才退回子 shell 后台。`update_luci_app` 结果先返回页面
- [x] versions.js 更新完成提示改为“管理服务将重启，需要重新登录”；pot 与 zh_Hans po 同步
- [x] netbird_cli.uc / state.uc 改为 `create(deps)` 工厂，netbird.uc 传入已加载的 shell/paths/cli 实例；独立使用时缺省依赖才自行 loadfile；scripts/test-timeout.sh 适配
- [x] PKG_RELEASE 递增到 3

## 文档

- [x] CHANGELOG 0.2.2-r3
- [x] docs/ARCHITECTURE.md 中 SIGHUP 重载描述改为延迟 restart，并说明 lib 只加载一次

## 测试

- [x] scripts/test-package-upgrade.sh：断言升级后恰好一次延迟 rpcd restart、在安装器返回之后、不在安装器会话内、postinst（含 postinst-pkg）不含 HUP；断言 netbird.uc 每个 lib 文件最多打开一个 fd；失败时非零退出
- [x] 容器门禁（58.34，官方 openwrt/rootfs，新旧代码同批对照）：
  - 24.10.5 / 25.12.2：test-timeout、test-uci-commit、test-autoreconnect-signal、test-recovery-arbitration、test-watchdog-pending-settings、test-rpcd-backup-migration、test-binary-and-app-update、test-agent-update、test-logout-drain、test-worker-actors 全部 rc=0
  - test-package-upgrade（CI 构建包 r2→r3→回滚 r2→再升 r3→卸载）：24.10.5 opkg、25.12.2 apk 均 failures=0；restart 1 次、安装器返回后约 5s、独立会话；netbird.uc 每个 lib 文件 fd=1
  - 22.03.6：test-uci-commit、test-autoreconnect-signal、test-rpcd-backup-migration 通过；r3 postinst 在 22.03 容器内（无 setsid，走 start-stop-daemon）restart 1 次、延迟 5s、独立会话、无 HUP。整包无法装进 22.03 容器（feed 缺 ucode-mod-socket，r2 相同），test-timeout 等因 22.03 ucode 不支持 `?.` 失败，与 r2 基线逐项一致，非本版本回归
  - 健康 run.sh（24.10/25.12）与 test-offline-agent-restart（需一次性 QEMU 客体，rc=2 拒跑）新旧结果相同，属既有限制
- [x] SDK 构建 24.10 IPK / 25.12 APK：GitHub Actions run 45634945317（候选分支，仅构建，发布跳过）成功

## 发布与验收

- [x] 提交工作流：release commit dce5207 `release: 0.2.2-r3`、annotated tag `v0.2.2-r3`、推送 origin/main 与 tag；GitHub Actions run 45637936155 三个 job 成功；Release v0.2.2-r3 为 Latest，4 个包 + manifest.json（version=0.2.2-r3）
- [x] 武汉 192.168.3.1 升级验收（11-25 22:59）：update_luci_app 18s rc=0 并返回结果；rpcd PID 17378→28513，fd 193→66（deleted 53→0）；NetBird PID 5101 不变；三份配置与升级前备份一致；netbird.uc/state.uc 与 dce5207 一致；check_luci_app_update 无更新；get_status running

# 待验证

> `TODO.md` 管执行、调查和决策；本文件只管可独立执行的验收（自然触发、现场复验、外部证据核对）。每节列触发条件、通过标准和操作边界；验结或经本人取消整节迁入 `VERIFY-m.md`。验收失败回 `TODO.md`，不自动取得任何操作授权。

## [待验] rpcd中envelope.uc残留2个fd的来源（2026-11-26）

- [ ] 背景：v0.2.2-r3升级后武汉rpcd fd 193→66、deleted 53→0，但envelope.uc仍占2个fd；推测为netbird-health.uc所在VM另行加载一份，未核实。见TODO-m.md节「v0.2.2-r1～r3发布与rpcd fd泄漏处置（2026-11-24～11-25）」。
- 触发：任意时刻可验；下次武汉升级插件后再验一次更佳。
- 通过标准：`ls -l /proc/$(pidof rpcd)/fd`中envelope.uc数量与源码中的加载点（import/loadfile）一一对应，且多次rpcd重启后数量不增长；若存在可去重的重复加载，转TODO.md立项。
- 边界：武汉只读SSH；不重启rpcd/netbird，不改设备文件。

## [待验] zh-cn语言包真机升级路径（2026-11-26）

- [ ] 背景：武汉未装luci-i18n-netbird-zh-cn，r17→r1→r3升级只验证了主包；i18n子包随PKG_PO_VERSION升级刷新.lmo只有容器测试覆盖。
- 触发：有已装zh-cn语言包的设备执行插件更新时。
- 通过标准：update_luci_app rc=0后`opkg list-installed`/`apk list -I`中语言包版本等于主包版本，Versions页及更新后"重新登录"提示显示中文。
- 边界：仅在本人指定的设备上做常规插件更新，不为验收额外装包或改配置。

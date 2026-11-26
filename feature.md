# 特性与外部请求

> 提议、搁置、在途的特性及对其他团队/上游的请求；交付并验证后整节迁入 `feature-m.md`，附设计要点（契约、决策、约束）。执行类事项写 `TODO.md`。

## [提议] 请求OpenWrt 24.10/25.12 backport ucode fd修复（2026-11-26）

- 内容：ucode上游提交1dd1f88c81（2026-10-16，source: close the file of a source after its compilation）修复已编译源文件fd常驻；OpenWrt main（ucode 2026-10-28）已含，24.10（2025-07-18）、25.12（2026-07-09）未含。
- 价值：rpcd每次HUP重载都会继承上一代全部.uc fd；插件侧v0.2.2-r3已改用rpcd restart规避，但其他包和固件自带的rpcd reload仍会累积。
- 状态：未提交；需本人决定是否以个人身份向OpenWrt提issue/PR，提交内容不含现网信息。

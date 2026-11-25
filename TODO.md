# NetBird agent 夜间自动更新实施待办

状态：武汉r17只诊断ON（60秒/rev8/基线1），自动恢复OFF、owner none、agent更新OFF。最小P1及timer完成后60秒修正已通过短窗口验收；修正后独立24小时观察已于北京时间11-19 19:47完成并于11-24审阅：取证完整、健康为有限定通过（非全绿）；代际周期修正已热部署武汉待15:35–15:45撞期确认，LAN探针诊断字段已部署。最近核对NBH项目24项中17完成、7处理中，剩余现场验收、56窗口/独立恢复入口及推广门槛未解除。

## [进行中] NBH-19最小P1上线后的剩余现场验收（2026-11-16）

- 原始目标：承接武汉持续诊断，完成真实Linux LAN探针与中央汇总；最小三机凭据交付、SSH限权、中央单轮和通过后启用timer均已完成，完整过程归档TODO-m.md同日完成节，不再重复Create/check/fetch/安装。
- 当前（2026-11-17只读复核）：P1 timer enabled/active waiting、service success，旧netbird-ha-monitor.timer仍active；武汉node fresh、固定LAN两PASS/fresh，LAN boot仍5f5aa365-ca78-4f58-88d0-d41d3a2e9c54。24小时取证完整，但存在瞬态UNKNOWN，不是持续健康或全站点验收通过。
- 授权边界：仅最小三机P1；旧netbird-ha-monitor.timer保持active/waiting，owner none/投递0；武汉11保护SHA与PID9497保持，未改agent/路由/ACL/56封锁或计划，不扩大推广。
- 剩余1：其它代表性生产方向、真实节点/中央失联恢复、生产ACL负向和真实通知收件未验；逐项先明确精确来源/目标/故障窗口或通知身份再执行，不能以SSH越权拒绝代替网络ACL验收。
- 剩余2：当前boot5f5aa365-ca78-4f58-88d0-d41d3a2e9c54绑定证明有效至2026-12-15T14:38:06Z；boot/接口/来源/网关/目标/预算/基线变化即失效，不能自动续证明。两SSH key分别2026-12-15T04:07:52Z与04:10:15Z到期，维护/续期另批，不使用管理key兜底。
- 验收/下一步：保留P1日常只诊断并观察新鲜度、UNKNOWN与独立LAN结果；剩余场景有真实证据后逐项关闭NBH-19关联标准。56仍须维护窗口和独立恢复入口，不能直接清封锁重试。
- 证据：C:/Users/25321/AppData/Local/Temp/nbh-p1-reproof-xqo0ogkv/p1-live-report.json；Jira NBH-19附件11319（22333字节，下载SHA763c1ccb0b56173d3ffa198a00127e0450ed4f432639e1f4ef32efe3d9b7e1ac一致）、评论11251，NBH-1评论11252均GET确认，未转Done。
- 24小时观察已审阅：原始目标为持续只诊断取证、只读拆解UNKNOWN、到期核对全部分母/空窗/唯一run/状态原因/资源及前后保护；2026-11-17本人允许继续后已完成，完整证据归档TODO-m.md同日节。不重新采样、不取密、不新增探测、配置变更或故障注入。
- 取证结论：collection_complete，1441行/13251513字节，UTC11-15T17:45:04.477299至11-16T17:45:07.934613，跨度86403.457秒，最大间隔63.275秒、>75秒空窗0；全部状态计数与原始JSONL对账一致。中央1355个独立样本、86次重复；有效武汉run1345（原status的1346包含一次null/null，报告已纠正），两LAN各1345个独立run。
- 健康结论：未达到持续全绿；中央node 41个非fresh样本=32 RESULT_STALE+8 COMMAND_TIMEOUT+1 NODE_UNREACHABLE。LAN55为1431PASS/10 COMMAND_TIMEOUT，LAN56为1431PASS/9 COMMAND_TIMEOUT/1 NODE_UNREACHABLE；这些异常均下一采样点恢复，不能据约60秒采样间距宣称精确故障时长或目标宕机。
- 武汉检查：15项分母始终完整，6项基础UNKNOWN保持；10样本出现GENERATION_CHANGED（8段，最长连续2样本），独立router55/56各1/2次TIMEOUT，均后续恢复；本地缓存始终fresh。UNKNOWN分类不能只沿用初始未配置结论，也不删检查或放宽判定追求全绿。
- 保护复核：全窗配置/身份/进程引用无漂移，本次远端11武汉SHA及PID9497一致，中央10个保护文件SHA一致；自动恢复OFF，owner none/provider_accepted0，原监控未变。复核是窗口结束后当前检查，不冒充截止时刻同步11文件校验。
- 证据：C:/Users/25321/AppData/Local/netbird-observer-observations/p1-20261115T174221Z/；review-20261117.json、review-current-cache.json、protection-after-review.json及不可变原samples/status保留。原JSONL SHA256 be071a5418d8833acdae89c0432d6279713bf9fba0951c4f522c1793a8e00a9a；资源仅取样last-run峰值，不推算全程CPU。
- 旧源结果已定位并修正：扩展窗口1424次service调用仅1360个poll，64次重复旧poll；32次RESULT_STALE全部对应重复发布。修正前OnUnitActiveSec=60s与Python入口严格60秒准入计时基准不同，导致跳轮；已获准改为OnUnitInactiveSec=60s并通过3个切换后自然有效周期。原119–121秒是跳过后的重复view，不是新SSH读取旧文件，原始异常证据不改。
- 日历约束：具名现场验收应安排在2026-12-15T04:07:52Z（武汉key先到期）前，LAN key04:10:15Z、当前boot证明14:38:06Z随后到期；延期续期和新证明另批，boot/路径提前变化立即失效。56窗口、其它方向、失联/ACL负向及真实通知仍按上列范围另定。
- Jira审阅已同步：NBH-19附件11320（30312字节，下载SHA256 04427f2d3c15ab1b295eb70710b78a8a309709dda5a652cd763eae16d15b8b87一致），评论11255；NBH-1评论11256，均GET验证，保持处理中。浏览器旧tab失效发生在请求执行前，新tab先GET确认无附件/评论后才上传，未重复写入；已释放本轮tab。
- 本轮进展：调度机制离线重现、本地候选验证及获准生产timer切换/三周期验收均完成，详TODO-m.md同日生产完成节。保持60秒准入/140秒TTL/10000ms预算，不改Python逻辑或其它服务；SSH/代际/RDP历史原因缺口与其它现场门槛仍保留。
- 后续路线逐项保留：P1其它方向/失联恢复/ACL负向/真实通知先明确目标与窗口；56仍缺本人具名维护窗口与独立恢复入口，不reset或重试；55→上海→武汉→DC推广依赖56通过。APK签名信任待匹配批准签名材料，物理断电/真实故障回滚另需窗口，不借本轮排障操作。
- 本轮验收：三类异常各有证据支持的原因或明确不可恢复证据缺口；存在修复则先复现后验证且保留原异常。保护基线、原始样本/attempt不覆盖；结论、后续边界和非秘密证据同步账本/Jira，不将排障完成冒充全部现场验收通过。
- 节点/SSH证据缺口已核清：原13个代际/RDP异常run在现役102个历史/特殊缓存文件中均不再存在，原采样未保存before/after字段，不能恢复具体变化字段。51.160扩展窗口来源过滤认证日志2711次公钥接受、8次关闭、无超时/reset/认证失败分类；未绑定逐probe且中央未留stderr/阶段耗时，不能据此判断真实丢包或目标故障。保留原因未定，不补采伪造历史。
- 后续候选证据位于原观察目录diagnosis-20261118/：diagnosis.json和netbird-observer-p1.timer；原review/样本/附件不覆盖。上轮报告的119–121秒“新发布/旧源”解释需以本轮勘误为准，异常计数和保护结论不变。
- 后续门槛复核（仅核对，不冒充执行）：P1新增方向缺具名来源/目标，失联/ACL负向缺故障窗口与恢复范围，真实通知缺获准owner/用途身份/收件验收；保持NOT_RUN。56仍需本人指定至少20分钟窗口及独立于NetBird的恢复入口；未给出新材料，不清失败封锁。55/上海/武汉/DC继续依赖56通过；APK签名缺匹配的批准签名材料，物理断电/真实回滚缺独立窗口，不读取额外秘密或进行破坏性测试。
- 诊断勘误已同步：NBH-19附件11321（24918字节，下载SHA256 6d84f2a1425b2001a1f29d9ae1c4db5f87e023ae6ccb72861544b79cff9b2e5a一致），NBH-19评论11257、NBH-1评论11258均GET验证，原报告不覆盖。
- 本人“实施最小修正并验收”范围已完成：只改gateway3/100.125.250.19的netbird-observer-p1.timer为完成后60秒；备份、systemd-analyze verify、daemon-reload及仅restart timer成功。原备份/root/nbh-p1-timer-fix-20261118-f5532f76/timer.before，事务/证据在diagnosis-20261118/。
- 原生行为通过：切换后poll1794994769→1794994833→1794994897，间隔64/64秒，武汉与两LAN每轮fresh/PASS、无重复旧poll/服务失败。首次启动重显的切换前poll1794994687已排除并留纠正记录，不能用3条日志冒充3个切换后有效周期。
- 最终保护通过：武汉11SHA/PID9497保持，中央保护仅timer按批准SHA改变，其他文件不变；新旧timer均active、P1 enabled，自动恢复OFF、owner none/accepted0。未手动once、未取密、未重开24小时、未改56/路由/ACL/阈值/目标；此为短窗口修正验收，不是新的24小时健康结论。
- 生产修正已归档并同步：NBH-19附件11322（11421字节，下载SHA256 f03657d1cd00ca72647d1b240e6690b9cc171ccc12e48d2f60415d634b38c3db一致），NBH-19评论11259、NBH-1评论11260均GET确认，保持处理中。后续若安排修正后完整观察须新建独立窗口，不覆盖原采样；本轮按明确范围只验3个自然有效周期。
- 修正后24小时窗口（11-18 19:47至11-19 19:47）已于11-24审阅并归档至TODO-m.md同日完成节：取证完整，健康为有限定通过、非全绿；Jira审阅评论NBH-19 11400、NBH-1 11401，附件11402（17203字节，另存下载SHA256与本地逐字节一致）。
- 未定原因处理：约2小时20分GENERATION_CHANGED已归因为watchdog（实测30.1035秒周期）与60秒健康采样拍频，代码修正7692606已于11-24 13:33获准热替换到武汉（三文件，备份/root/nbh-genfix-20261124/*.before，未重启，agent PID9497不变），部署后连续轮次PASS；06:25–06:50读取拥塞与rdp56单次CONNECT_FAILED离线复析仍未归因。
- 撞期确认（11-24 15:57只读）：部署后保留的100轮全部node:collection PASS、跨轮无变化，武汉11保护文件OK（健康.uc不在保护集）；按相位反推15:28–15:31应有重叠，但保留记录中无一轮快照抓到binop租约，不能证明该重叠被采样到，结论为“与修正一致、未确证”。下次重叠约17:45–17:55，可做定向观察（同时记录锁/pidof时间与健康轮次）。包仍为r17，重装/升级会恢复旧文件，正式发包前须纳入新版本。
- r18已发布（11-24 17:12）：fork Action run 45361492158双SDK构建与发布success，Release v0.2.0-r18指向3350121；IPK内collect/maintenance/boundary三文件与HEAD及武汉热部署SHA一致（773e15ae/c44d91eb/2b27d68a），APK为v3格式本地未拆验；签名仍UNTRUSTED。注意：7692606推送时Action曾以同一标签覆盖v0.2.0-r17资产（13:31），现r17资产已非原记录SHA。武汉当前文件等同r18，包元数据仍r17，未在设备上安装r18。
- 上游v0.2.2合并（11-24，分支merge-upstream-0.2.2，未进main、未发版）：合并09b8fb6+测试桩适配42100d8；保留fork健康修复/动作仲裁/安装事务/watchdog，不恢复软件源二进制来源与上游收编逻辑，不引入Cloudflare Pages部署；带入curl预检、校验和强制、环境变量传setup key/PSK、apk feed公钥sysupgrade保护。上游4个回归脚本+健康run.sh --unit 27文件在58.34隔离容器全PASS。fork Action run 45367850668仅构建（发布跳过）：24.10 IPK/25.12 APK 0.2.2-r1，IPK中78个非前端文件与分支HEAD一致（前端11个为LuCI压缩）。官方openwrt/rootfs 24.10.5(opkg)/25.12.2(apk)临时联网容器：r18安装→0.2.2-r1升级→回滚r18→再升级→卸载全部rc=0，关键文件SHA与对应源一致，UCI标记跨升级/回滚保留，binary_source=release，init/watchdog 0755，uci-defaults清理，无rpcd .bak，卸载后关键文件0残留、配置保留。未测：ubus/rpcd实际加载与服务重载、真实设备、apk feed公钥分支；APK签名UNTRUSTED。待定：版本号（当前0.2.2-r1，标签v0.2.2-r1）后再合main发版；上游watchdog改动未带入需单独评审。
- 武汉撞期复查（11-24 18:03只读）：保留100轮16:24–18:03覆盖17:45–17:55窗口，100/100 node:collection PASS、跨轮6项UNCHANGED、maintenance false、PID9497、三文件SHA不变；仍无一轮快照含binop租约，结论同15:57“与修正一致、未确证”。
- v0.2.2-r1已发布（11-25 11:59）：PR#1合main（410e3cf），首次发布run 45433721302因合并带入上游release.yml未冲突段`PUBLIC_VER="${VER%-r1}"`，标签/manifest成v0.2.2并标latest，r18及以后fork设备更新检查（_PKGVER_RE要求vX.Y.Z-rN）会报无兼容版本（读码推断，未在设备验证）。修复ac39b92恢复完整x.y.z-rN（与r18 workflow一致），run 45543446947发布v0.2.2-r1为Latest，manifest version=0.2.2-r1，两IPK载荷与已验证build-only构建逐文件一致（89/2）；APK未拆比、签名UNTRUSTED。已删除v0.2.2 Release及fork远端v0.2.2标签（fork的410e3cf与上游同名标签5006f38冲突）。后续合并上游须核对release.yml的标签/manifest版本逻辑；真实设备“检查更新”待验证；上游watchdog改动仍待评审。
- 武汉真机升级验证（11-25 13:43）：Nexus github-group补release-assets域名后，r17设备check_luci_app_update返回update_available=0.2.2-r1；经update_luci_app（setsid后台，nohup随SSH断开被杀未执行）7秒升至0.2.2-r1，rc=0，netbird.uc与ac39b92一致（85ccc3df…，3972行），三份配置与升级前备份逐字节一致，rpcd/netbird运行、Management/Signal Connected、Peers 26/34不变，复查update_available=false；浏览器Versions页正常，显示v0.2.2（versions.js appVer仅显示层去-r1，属预期）。该机未装中文包，i18n升级路径未验证。剩余：评审上游watchdog改动。
- v0.2.2-r2（11-25）：补上游watchdog两项缺口。①`/etc/netbird-settings.pending`不再让watchdog_step返回maintenance（原先非do_up连上后watchdog永久停摆、待应用设置永不应用），连续4轮已连接仍有标记时补应用一次并清标记，非连接轮计数归零；`/etc/netbird-update/settings.pending`仍为维护门。②watchdog在connected/authentication_required时调用nb_sync_log_level，守护进程重启后补发日志级别（PID+级别不变不调用）。新增scripts/test-watchdog-pending-settings.sh（旧代码失败`settings marker still gates the watchdog`）；24.10.5/25.12.2容器通过该测试与test-autoreconnect-signal、test-recovery-arbitration；25.12.2容器通过三个node测试；22.03.6/25.12.2通过test-uci-commit。版本规则改为fork口径：PKG_VERSION跟上游，fork自身发版递增PKG_RELEASE，RELEASING.md同步修正。武汉真机（11-25 15:47）：rpcd与ubus脱开（仅34对象、无session/luci.netbird，PID7166睡眠不动，620fd含424已删除）→`/etc/init.d/rpcd restart`恢复（NetBird PID5101不变）→check_luci_app_update返回0.2.2-r1→0.2.2-r2→update_luci_app 7s rc=0；15:48:07 watchdog补发日志级别（applied=`5101 info`，之后PID/级别不变不再调用）；pending标记不存在，该修复未在真机触发；15:47:37一次`action policy or owner unavailable`后未再现（推测升级中rpcd未加载完，未核实）。脱开原因未查明。
- rpcd fd泄漏（11-25调查）：ucode 2025.07.18（24.10）每个已编译源文件在程序存活期间一直占一个fd，fopen无O_CLOEXEC（fdinfo flags 0100000）；rpcd收HUP后execv自身，上一代fd全部继承不关，升级替换过的文件显示deleted。武汉每代约61个（本插件53：loadfile不缓存，shell.uc每代4份、netbird_cli/paths各2份；import在netbird.uc与netbird-health.uc两个VM各一份），上限1024≈15次重载；脱开时620=71+9×61，即此前已重载9次、未到上限，脱开另有原因。每次升级重载2次：武汉固件（24.10.8，REVISION 2026073111）的`/lib/functions.sh` default_postinst对含acl.d的包同步`rpcd reload`，加上本插件postinst的延迟HUP；OpenWrt上游main/25.12/24.10的functions.sh及22.03.6/24.10.5/25.12.2容器均无此reload，属该固件定制（`/usr/libexec/emmc-health-install-mmc`也会reload rpcd）。上游修复ucode 1dd1f88c81（2026-10-16 source: close the file of a source after its compilation），OpenWrt main（ucode 2026-10-28）已含，24.10（2025-07-18）、25.12（2026-07-09）未含。
- LAN探针诊断字段b84ebfe已于11-24 13:47获准部署：51.160与gateway3的lan_probe.py由da100c3a…替换为80df5386…（备份/root/nbh-lanprobe-diag-20261124/，导入检查OK，未重启），13:48:31首轮rdp55/56 PASS并带elapsed_ms 30/31；中央保护基准中该文件改为批准值80df5386…，其余9文件不变；回执lanprobe-diag-deploy-receipt.json。下次CONNECT_FAILED将带errno名failure。


## [阻塞] 武汉诊断功能例外、P1与后续推广验收（2026-11-14）

- 原始目标：本人要求按推荐规划任务并执行；顺序为武汉持续只诊断→真实LAN探针→56受控更新验收→逐节点推广，不以阶段启动代替完成。
- 阶段1取证已收口：按批准范围观察Windows192.168.80.163/br-lan→10.10.10.55/.56查询、router RDP3389与本地结构，原24小时标准未缩短；没有更改网络、ACL、agent、计划或发送通知。
- 阶段1限定结论：1441样本/独立run、无读取错误或过期、最大间隔60.001秒，连续调度/缓存发布与前后保护层通过；功能结果1432轮结构完整，9轮代际UNKNOWN和1次节点RDP TIMEOUT未抹除，不能将零FAIL当全PASS。自然变化留证、独立LAN、peer/路径绑定等仍未验收。
- 阶段2已完成最小上线（2026-11-16）：51.160真实Linux来源/当前boot路径证明、两用途身份与受限SSH、gateway3非root中央单轮及60秒timer均通过，见TODO-m.md同日完成节。其它代表方向、生产故障/ACL负向与真实收件仍未验；不以此放行推广。
- 阶段3：为56编写具名维护窗口/严格LAN恢复入口/备份/候选与失败封锁处理/验收方案；本次先做准备，不立即重试0.82.1、不清封锁、不改既有计划，具体生产动作须窗口与方案具备后批准。
- 阶段4：仅在56真实agent升级及功能门槛通过后，按55→上海→武汉→DC逐节点计划；本轮不执行其他节点推广。
- 56具名方案/窗口：目标仅10.156.56.100；维护时间仍需本人指定，预留至少20分钟操作与恢复空间。先证明不依赖被更新NetBird的SSH/控制台恢复入口，不能把当前经武汉mesh可达的管理地址叫作独立LAN恢复；该入口未交付前不执行。
- 56具名方案/变更：先保存现役r7/daemon0.82.0事务、0.82.1失败封锁和私有身份/配置基线，另批56单节点候选插件升级；先验证插件不动agent及原计划，再验证官方候选SHA/架构/48小时版本龄/空间和原wt0 HTTP探针。未到窗口不发start/reset/reconnect。
- 56具名方案/封锁：仅在本人批准一次受控重试且实时封锁集合确认为仅0.82.1时，才考虑现有reset_failure；该API清空全部失败版本，出现其它封锁即停，不借总括批准全清。先留原始失败事务，不将reset当修复或自动重复重试。
- 56具名方案/证据：更新前先稳定采样，激活后记录真实daemon版本/PID/start/管理与Signal/身份及DNS比对/规则路由/原wt0 HTTP；120秒恢复、连续5分钟、10分钟硬截止均不放宽。保存失败前后样本而非仅通用message；每个原有LAN业务目标须另列获准来源/目标后验收，不能用HTTP代替全部业务。
- 56具名方案/退出：失败即由现有事务恢复旧版并重新验证连接/身份/DNS/业务，保留封锁及证据，不自动再试；成功也只记录本次成功层级，先完成56具名业务门槛后才申请下一节点。真实故障回滚/断电不以本次成功升级冒充。
- 当前现场只读复核：r17/health ON rev8、baseline1，fresh且当前无FAIL；82payload+10稳定保护SHA+获准health配置SHA共93项匹配，原UCI/PID9497相同，agent0.80.0管理/Signal Connected。自动恢复OFF、owner none、agent更新OFF；本次未改配置或重启服务。
- 已完成前置修复：r16修正有效规则链支持表误报，r17修正旧ucode RDP高位字节UTF8扩展；真实预演、RED→GREEN、实际旧runtime/打包原生probe及双SDK均通过。r16首次失败后CAS6→7暂停，r17修复后CAS7→8恢复，详细事实归档TODO-m.md；不隐藏失败、不以改目标/协议/规则要求掩盖。
- 取证窗口：2026-11-13 19:06:26+08至2026-11-14 19:06:26+08，collector elapsed86400.236秒，原始状态collection_complete；不重启或延长同一轮取证，原status的REQUIRES_REVIEW保留，人工限定结论另存。
- 证据：C:/Users/25321/AppData/Local/Temp/nbh-r17-release-kq14jz3e/wuhan-observation/下status.json、samples.jsonl与acceptance-review.json；原始样本6772923字节/SHA5c20c10e144114c49643e3f09ecd85ea19836a9cf26624b657964b0918b4b3ff。完整限定结论归档TODO-m.md和docs/health/baseline.md。
- 功能例外保留：9轮GENERATION_CHANGED的前后原始边界未由外部collector保留，原因未定，不凭采样结构hash不变否认瞬态变化；.55于11-14 16:02:26一次RDP TIMEOUT，下一周期恢复，不能认定NetBird或业务根因。没有为收口删除UNKNOWN或补采一段全绿。
- 下一步优先：保留已上线最小P1的日常只诊断与新鲜度观察，再按明确范围推进未验的生产方向/故障/ACL/收件。56仍待窗口和独立恢复入口，不重试/清封锁/推广；原24小时功能例外不因P1上线关闭。
- Jira：NBH-1评论11305、NBH-19评论11306均201/GET200，保持处理中；报告附件11401共14616字节，下载SHA9c06d5da641756e560db6b54f2dcdf1ab21c37cc0ef205f52d38d5eb94889d58一致。
- 完整本地归档：closeout-evidence-20261114.zip为169883字节/SHAed49650f0587bd8aaa448b6f0abb5e69df9915a56f548038ead2eb64a557ad11，含原status/samples及审阅/保护回执。可选Jira原始ZIP上传因Chrome relay扩展断开，在联网写入前失败；本地原件和已上传报告均保留，不重放成功评论/附件。

## [阻塞] 按建议处理56回滚与NBH剩余验收（2026-11-13）

- 原始目标：本人批准按上轮建议处理；先核清56的0.82.1回滚，再推进NBH-19及关联现场验收，不扩大推广。
- 子项1：有界读取56事务/调度/agent日志并脱敏，关联失败窗口；可复现代码问题在隔离环境修复验证，不对现网重试升级、reset封锁、改计划或重启。
- 子项2：核对NBH-19现有中央适配器、LAN执行器与可用受管来源/受限身份，完成可达的准备与验证；缺合格来源或交付权限则明确阻塞，不强改候选路由。
- 子项3：逐项核对NBH-4/6/7/9/10剩余条件，必要时同步非秘密Jira进展；负向ACL、真实通知、故障注入及部署仍遵循精确范围/凭据边界，不因总括同意自行扩大。
- 验收：回滚原因以实际证据或明确不可恢复缺口结论交付，后续具名验收逐项保留PASS/NOT_RUN及执行条件，父任务不冒充完成。
- 当前状态：启动DNS误判已在原生25.12及实际武汉旧runtime隔离矩阵RED→GREEN修复，独立r15双SDK/原生包及武汉单节点插件试装完成（详TODO-m.md）。现场失败采样未保存，56回滚无法唯一归因；56不重试、不解除封锁，不把武汉插件验收当真实agent升级或推广放行。
- NBH-19的11-13准备快照：当时Windows不能作为Linux产品执行器，.58.34/.110走自身wt0，仅隔离disabled烟测通过。此来源/身份阻塞已由11-16的51.160真实路径、专用受限身份和中央上线解除，不再重复准备；不生成假attestation。
- 下一步条件：NBH-19的其它生产方向、失联故障、负向ACL和真实收件分别按范围推进；真实engine与56更新仍独立验收。历史NBH-1评论11300/11302、NBH-19评论11301均确认，新上线证据见11251/11252；父任务保持未完，不把最小上线等同全场景Done。
- 本人选择的候选支线已完成：仅武汉r14→r15插件升级，82常驻payload匹配、11保护SHA/PID/原UCI保持，RDP62/36ms通过；monitor OFF/rev5、automatic OFF、owner none。原agent更新、56封锁/计划、其它节点及P1范围不变；完整构建/边界/回退及清理证据归档TODO-m.md。

## [阻塞] 剩余现场验收与Jira证据收口（2026-11-08）

- 原始目标：按本人要求推进剩余验收和Jira任务；不将武汉r14单节点兼容性通过当作全网业务或推广通过。
- 子项1：核对56原计划的真实执行/事务、120秒重连/5分钟观察、身份/DNS/探针和现有业务证据；缺少历史证据保留缺口，不手动触发升级或降低48小时门槛。
- 子项2：核实合法武汉LAN来源、既有两台RDP及代表目标，执行已明确范围的无凭据正向测试，独立证明路径；生产ACL负向、抓包、真实告警或新探针部署若缺精确授权/身份/目标，先列明再受控推进，不借其他用途取密。
- 子项3：实时读取Jira及关联验收标准，补充r14真实交付/现场进展，按完整证据逐项收口；未测项保留NOT_RUN，不只凭关联开发Done关闭需求或Epic。
- 范围：既有SSH严格信任、已批准管理目标与只读核验；本轮不推广其他节点、不改计划/ACL/路由、不重启agent、不注入故障，不读取浏览器凭据或现网秘密文件。
- 验收：每项结论有实际命令/接口或既有可核对回执，Jira mutation仅一次并读取确认；未满足项记录明确原因和可执行下一步，父任务保持直到要求完成。
- 当前状态：本轮已授权的Windows两RDP正向/初次路径实证及Jira同步全部完成；Linux产品探针按本人选择暂缓，ACL负向/其它方向/真实通知与56历史定时验收门槛仍保留。本轮不推广或改变既有计划/网络/agent。
- 56历史进展（11-08快照）：r7/daemon0.82.0，当时事务为0.81.5→0.82.0 committed、开始2026-11-01 03:01:54；当前事务已被下述11-13回滚覆盖，不再把旧结果当现状。journal缺调度来源，不凭时间吻合补造触发来源或重连时间。
- 56当前功能通过：302917ms内31/31样本健康、11/11原wt0 HTTP探针通过；PID27245稳定，public key/Mesh/management/DNS指纹逐样本与事务基线一致；3个运行事务/调度/平台适配库与已验证r7包SHA一致。本轮五分钟观察不冒充原升级后的逐样本回执，推广门槛暂保留。
- 武汉Windows验收完成：192.168.80.163/物理接口14到10.10.10.55/.56:3389，TCP及无凭据RDP HYBRID=2协商均通过；本轮59465/59466源端口的SYN在br-lan入、wt0出同seq同目的，观察源NAT至100.125.129.101。26秒4包、载荷0、内核丢0；不再仅依赖bind或route get证明该两条路径。
- Linux来源预检：现有192.168.58.34和192.168.58.110从各自LAN地址到RDP目标的自然路由仍走其自身wt0，均不准作为直经武汉网关的LAN探针；未为通过而停agent/改路由/部署探针。
- Jira已实际收口：NBH-2/3/5/8四个P0 Story的完整需求对应具名层级PASS已核对，说明/评论/Done41均成功且GET完成；评论11236/11237/11238/11239。原真实拓扑/故障NOT_RUN层未改为PASS，不以关联Done代替验收。
- Jira防重与最终状态：标记NBH-ACCEPTANCE-20261108-R14-01；Epic实际附件11316/5767字节，下载SHA384813d3d13e0e5a7997c202a770789da7e3dd589af8de5a7e9eb885286043dc一致。最终24项中17完成/7处理中（NBH-1/4/6/7/9/10/19）；其余六项转31且GET确认，NBH-19保持处理中。评论11240–11246；未重放成功mutation。
- 56真实页面补验：临时只读session进入实际LuCI，daemon/CLI均0.82.0、Management/Signal已连接、Mesh100.125.61.255/16、内核接口；浏览器errors为空，session已撤销、隔离页已关闭。当前观察不补造原始定时触发/重连时长。
- 本人明确批准：本机192.168.80.163→10.10.10.55/.56:3389本轮临时源端口，在武汉br-lan/wt0做≤30秒/40包SYN包头采样，无业务载荷；原始文件只留网关root私有目录。先验证过滤器与自动截止，采样后只导出结构化包头和哈希，不外传PCAP。
- Linux产品探针仍缺：两候选源自然路由走自身wt0，不能强行bind改出口后伪称自然路径；需另外合格受管Linux来源/身份，或另批隔离环境方案。Windows本轮只算手工正向验收，不能冒充已部署observer.lan_probe。
- 证据：local://nbh-node56-observation-summary.json、nbh-node56-r7-engine-integrity.json、nbh-node56-ui.json、nbh-real-lan-rdp.json、nbh-wuhan-real-prereqs.json、nbh-linux-lan-candidate.json、nbh-remaining-acceptance-report.json、nbh-jira-mutation-receipts.json、nbh-jira-final-summary.json；Jira附件与每个事项GET已实际确认。
- 路径补证实际收据：NBH-19附件11317/3591字节，下载SHA697236441e5b4f82a47b315f066d0e9a3a5f036aecbe057aab0762a1d8c31cca一致；NBH-19/1说明PUT204、评论11247/11248 HTTP201、GET处理中确认。最终仍17完成/7处理中，没有借Windows手工验收关闭Linux产品P1。
- 原始PCAP仅在武汉/root/nbh-lan-acceptance-20261108-c306b123（700），lan.pcap与mesh.pcap（600）；没有PCAP外传。8保护SHA不变、PID12682、monitor OFF/rev5、automatic OFF/owner none；guardian完成、两tcpdump及guard均exit0。
- 后续可执行条件：自然经武汉的51.160与专用身份/产品P1已于11-16上线；ACL负向/其它代表目标/真实通知仍须精确范围与用途凭据。56历史调度来源及原始重连证据缺口未消除，不开启其它节点推广。
- 11-13复核/新增推广阻断：56事务989abd9b-151e-4413-ba22-c43d7370db09为0.82.0→0.82.1，03:02:00开始、03:02:40更新为rolled_back；0.82.1已封锁，当前daemon/CLI0.82.0、Management/Signal正常、原wt0 HTTP探针200。failure仅为健康窗口失败或取消的通用文本，cancel_requested=false；无逐样本原因，不能认定新版缺陷或回滚根因已明确。不重试、不reset、不改计划；后续先做针对该事务的有界只读日志关联，再决定是否需隔离复现。
- 11-13武汉现状：r14/agent0.80.0在线，规则105/110存在，两目标from192.168.80.163+iif br-lan均wt0/table netbird，Windows无凭据RDP33/58ms通过。monitor OFF/rev5、automatic OFF、owner none，旧缓存stale/CONFIG_CHANGED；不是持续巡检通过。daemon PID9497不同于11-08的12682，原因未定，不宣称跨日进程不变。
- 11-13决策：不推广；优先处理56回滚阻断，再推进NBH-19真实Linux来源/受限身份/中央汇总，联动NBH-6/9/10验收。NBH-4需A23负向边界，NBH-7需A03真实engine事件；不得以已实现替代现场证据。巡检启用/目标基线、负向测试、真实通知及部署仍需对应精确范围，不自授生产动作。
- 新证据：local://nbh-syn-path-report.json、nbh-syn-capture-receipt.json、nbh-syn-post-state.json、nbh-path-jira-final.json；本轮完成证据归档TODO-m.md，父任务保留未完成范围。

## [阻塞] NBH Jira 开发任务顺序实施与交付（2026-11-06）

- 原始目标：按顺序开发NBH-11至NBH-24；同步进度与状态，必要时添加Jira附件和评论，存在Bitbucket代码关联时引用真实关联。
- 授权范围：本仓库开发、隔离验证及对应Jira进度/评论/附件；不扩大为生产部署、故障注入、真实告警或路由器配置修改。
- 验收：逐项读取Jira完整要求和依赖，实际实现并验证；未执行项明确NOT_RUN，不以计划或代码存在标完成；引用真实代码/构建证据，不伪造Bitbucket链接。
- [x] NBH-11/T01：基线、Schema、模型完成；本地提交68867a8，22项原生断言与5场景通过；独立审查问题经RED/GREEN修复。Jira已完成HTTP204，评论11203，附件11300/11301；未push。
- [x] NBH-12/T02：采集适配器完成；本地提交f7f8f75，runner12/parser26/collector12通过；Jira完成、评论11205、附件11302；未push。
- [x] NBH-13/T03：规则、路由与LAN判定引擎完成，本地fa76bb9；Jira完成HTTP204、评论11208、附件11303；未push。
- [x] NBH-14/T04：后台巡检与维护共存完成，本地92e106c；原生procd/探针/截止和实际APK降级/卸载通过；Jira完成HTTP204、评论11212、附件11304；详细证据归档TODO-m.md，未push。
- [x] NBH-15/T05：独立UCI/RPC/ACL/导出完成，本地9f90407；Jira完成HTTP204、评论11214、附件11305；完整证据TODO-m.md，未push。
- [x] NBH-16/T06：LuCI巡检页面与Status摘要完成，本地92a37b5；原生浏览器11场景及实际动作/ACL/下载通过，Jira完成、评论11216、附件11306；证据TODO-m.md，未push。
- [x] NBH-17/T07：低噪声告警与独立observer完成，本地4b3ee2b；原生alerts27/runtime24/export19与TLS/LuCI验证通过，Jira完成/评论11218/附件11307；证据TODO-m.md，未push。
- [ ] NBH-19/T09：实现已提交8c91eb0；指定Linux两RDP真实路径、受限SSH与中央P1上线及timer修正已完成，最新证据附件11322/评论11259。其它代表方向、真实失联恢复、网络ACL负向和真实通知收件仍未完成，Jira保持处理中，不能勾完成。
- [x] NBH-20/E01：dcc7577，A25/A26隔离原生与真实LuCI通过；Jira完成11225/11310/HTTP204，完整证据已归档TODO-m.md。
- [x] NBH-21/E02：e95e0e0及E03依赖验收完成；Jira附件11312/评论11230/transition41 HTTP204，GET完成；完整证据TODO-m.md，未push。
- [x] NBH-22/E03：09a1ba6，A29隔离仲裁验收及定点复审通过；Jira附件11311/评论11229/完成HTTP204，GET完成；证据TODO-m.md，未push。
- [x] NBH-23/E04：本地412befd，E05依赖已清；原附件11313保留，最终评论11235 HTTP201、Done41 HTTP204、GET完成10001，完整证据TODO-m.md，未push。
- [x] NBH-24/E05：本地7414037完成A25–A32/真实guest与离线agent/r9双SDK及包与源恢复；附件11314/11315 HTTP200、评论11234 HTTP201、Done41 HTTP204且GET完成10001，完整证据TODO-m.md。
- [x] 逐项更新Jira状态、进度评论与必要证据附件；NBH-19因真实验收阻塞明确保留处理中，未强行改Done。
- [x] 核实Bitbucket仓库关联：当前origin为GitHub InoriHimea/luci-app-netbird；Bitbucket当前用户可见仓库完整分页3页未找到netbird/luci匹配，不伪造代码链接。已记录Jira评论11201。
- 当前状态：14项开发/验收中13项完成；NBH-19最小真实Linux路径、受限SSH与中央P1已于11-16上线，但其它生产方向、真实失联故障、网络ACL负向及真实通知收件尚未完成，Jira继续处理中。其余交付与所有推广门槛保持。
- 2026-11-18只读核对：Jira全量24项，17完成，NBH-1/4/6/7/9/10/19七项均处理中；NBH-19评论11259、Epic评论11260确认最小P1及timer修正完成。旧正文的Linux未部署/原gateway2名称及以下早期“未提交/未实现/未部署”均属历史快照，不重复执行；仍保留各项未验条件，不自动改Jira状态。
- T01证据：见docs/health/baseline.md与TODO-m.md；合成模型验证不代表T02/T03采集判定或真实业务验收。
- 早期原生夹具：network=none、cap-drop=ALL、128MiB/0.5CPU/64PID；固定镜像digest b4fa13109cd5e8e8075c01fa7def985de559fd3a5bfc7e59a866d509ab986b0b。E05自有QEMU/包测试的最小能力、私有挂载与清理另见TODO-m.md；无宿主生产挂载或生产路由器改动。
- Jira进度评论11202已保存（HTTP201），报告18项原生断言与尚未完成范围，没有提前转完成。
- 四节点只读兼容性盘点已记录docs/health/baseline.md：56当前daemon0.82.0；55为0.78.1；上海/武汉0.80.0；全部插件r7。后三台缺少timeout命令，后续采集必须独立有界或明确UNKNOWN。DC保持原门槛未检查；版本变化不等于56业务验收通过。
- T02证据已归档TODO-m.md与docs/health/baseline.md；原生统一入口全部通过。生产未改动；端点比较不等于原子快照，表清单不等于防火墙执行证明。
- T04已归档：完整后台服务、Schema run与A21真实APK生命周期证据见TODO-m.md、docs/health/baseline.md、local://nbh-t04-evidence.txt；隔离包不等于SDK发布或真实VPN验收。
- T05已归档：原生9方法/HTTP分权、CAS重载、完整分母多人合并、导出/HTTPS/3项审查修复与新payload真实包生命周期通过，见TODO-m.md与docs/health/baseline.md；仅隔离源码组装APK，不冒充SDK/生产验收。
- T06已归档：本地92a37b5、原生LuCI 11回归及真实ACL/动作/浏览器关闭后执行/下载证据见TODO-m.md与docs/health/baseline.md；Jira附件11306/评论11216/完成HTTP204已成功，不重复。
- T07已归档：本地4b3ee2b、完整原生/HTTPS/LuCI/Schema/导出及审查RED/GREEN见TODO-m.md和docs/health/baseline.md；附件11307/评论11218/完成HTTP204已成功，不重复。
- T08已归档：本地3d182dd、真实双SDK r8包/回退包/明确范围bundle、实际生命周期/性能/五旧回归完成；Jira附件11308/评论11220/完成HTTP204，详细证据TODO-m.md与docs/health/release-r8.md。签名UNTRUSTED和所有真实拓扑/生产门禁未改变。
- T09当前：已读完整契约并开始独立P1实现；Jira transition31 HTTP204、评论11221 HTTP201已成功，不重复。中央采集/LAN执行器与原生路径验收仍进行中，未标完成。
- T09范围1：保留gateway2既有监控，新增固定命令的受限只读Schema采集，不新开公网口；poll失败/节点不可达/结果不更新分开，时间/boot/run校验禁止旧绿灯。
- T09范围2：独立LAN探针身份与预批准目标ID/协议/预算；有agent时绑定LAN接口并核实自然路由来源/下一跳，初次路径归因需要有界授权包头证据，不能用bind代替。两台武汉RDP及其他方向真实验收需独立记录，禁密码和任意shell。
- T09范围3：LAN FAIL不得被router/gateway2 PASS覆盖；未配置/不可达UNKNOWN且分母不变。中央事件与node/path/category/故障周期关联、默认仅中央发送跨站消息，独立记录接受与收件；无自动owner接管。
- T09验收：A06/A09/A10/A15/A16/A17/A18/A20/A23；真实来源/路径、失联与全局去重实测；P1独立证据，不以P0替代。先RED→最小GREEN→原生回归→独立审查，不能为验收改生产ACL/故障注入或发真实通知。
- T09实现计划：节点固定只读缓存发布器；独立Python标准库中央采集/新鲜度与持久事件去重；独立批准目标LAN执行器与来源/自然下一跳/初次路径凭据校验；隔离实际转发命名空间验证。生产路径未获完整证据时保留NOT_RUN，不将隔离武汉形状夹具声称真实武汉验收。
- T09模型RED→GREEN：observer/model.py与tests/observer/test_model.py，18项通过；覆盖失联不复用旧绿、同run改时间/跨boot复用、样本回退/时钟反转、独立LAN分母/失败及跨重启事件去重；审出未哈希枚举/时钟回退遗忘去重ID等实际失败后修复。
- T09原生只读发布器：新自有nbh-t09-node-20261107（network none/capdrop ALL/128MiB/.5CPU/64PID）；固定snapshot-v1实际返回NO_RESULT，带shell后缀命令实际exit2/COMMAND_DENIED。未启动健康监控或改共享夹具。
- T09独立transport.py原生烟测：正常进程exit0；输出超限OUTPUT_LIMIT；关管道后挂起及延迟子进程均约202ms截止；等待后无迟写，私密原子状态可读。leader保留至进程组清理、最终reap有界。下一步中央持久采集/事件队列、合法LAN执行器及实际独立转发/SSH链路；仍不等于完整T09交付。
- T09新增实现：observer/central.py（独立once/read、持久去重队列/有界HTTPS子进程）、observer/lan_probe.py（批准IPv4目标、LAN绑定/自然路由、boot/目标/基线绑定路径回执）；均未部署到生产或改gateway2监控。
- T09回归进展：原生Linux 33项全部通过（1.498秒），包括中央3/2阈值/间隔去重、LAN身份/路径/完整RDP协商、合并stdout/stderr上限、关管道挂起截止、成功leader后延迟子进程不迟写。节点短TTL、批准目标变更旧PASS、队列满时重复事件误报溢出均经实际RED→GREEN修复。
- T09隔离路径实测：自有LAN→GW→target三个network-none命名空间，仅修改其veth/地址/路由/forwarding；有界96字节包头抓取50包/内核丢0。来源192.0.2.2到两个RDP地址与HTTP目标均在gwlan0入/gwout0出各见4条，原始头部SHA256为6791f10e584e044cdb3a05c0dad6e7f02de8e1ef9fd2443b16fb51897c1c2486。
- T09探针原生证明：无初次路径回执UNKNOWN；具实际抓包绑定回执后三目标PASS；未批准ID实际exit2，错误自然下一跳UNKNOWN。仅隔离路径，真实武汉两RDP/ACL/A23仍NOT_RUN。
- T09真实SSH集成：仅新建自有127.0.0.1:22439临时sshd（私有合成key/known_hosts、节点与LAN不同forced-command身份、900秒lease），未改全局SSH/PAM/账号或公网端口。中央原生采集成功；read与过快once状态字节不变、新SSH会话0。
- T09独立LAN优先级：节点缓存为明确合成P0绿灯；隔离目标rdp-b地址撤销时，实际LAN FAIL使总览unhealthy，节点仍healthy；恢复地址后三目标PASS。三次采集只保留1个源事件/去重ID，owner=none未发消息。
- T09下一步：完整失联/恢复与只读SSH越权实测、中央合成HTTPS未知投递/重启去重、UNKNOWN原因保真、独立审查与交付文档；未提交、未完成Jira。当前四个自有容器和私有转发/SSH夹具保留；进程有lease，后续只能续用自己的配置，验收结束只清自有资源。
- T09进度同步：Jira评论11222 HTTP201已保存（27项回归、隔离路径/固定SSH/独立LAN优先级与明确NOT_RUN边界）；未转Done，不重复发送。
- T09最新防重放：LAN缓存保留last_source跨失败轮询，拒绝旧run重标时间、同run跨boot及同boot样本回退；队列满时重复ID不误报容量，新ID在不能入队时不提前记seen。Linux 33项回归已覆盖。
- T09路径回执到期实测：到期后中央节点仍fresh但LAN全UNKNOWN、总览unknown；不是失败重跑。新一轮隔离包头实证后才签新合成回执（SHA256 8b2c3f5024359f25289e0a71dfe3d0d7c4684d1087222fef0cefc13e8c3c5c28），最新原生中央代码恢复三目标PASS/overall healthy。
- T09原始输出持久保存：local://nbh-t09-native-progress.json（11份初始回执，追加本轮Linux/到期/新包头与RED证据）；不是完整最终交付证据。
- T09新增RED→GREEN：保留当前LAN UNKNOWN原因的固定公开词表，过期改PROBE_STALE；三次明确拒绝后的记录计failed不再计queued，允许有界展示淘汰但保留去重ID，避免永久堵塞后续事件。Linux36项通过（1.501秒），真实central read显示过期三目标UNKNOWN/PROBE_STALE且overall unknown。
- T09实际合成HTTPS：私有loopback TLS 200→accepted、503→failed、丢响应→unknown、协调进程在提交后SIGKILL→重启unknown，各仅1次请求；新进程重载accepted/unknown不重放，独立发送子进程已消失，全部receipt_verified=false，无真实通知。
- T09实际SSH故障续验：自有daemon lease到期时连续3轮NODE_UNREACHABLE形成一次事件；复用既有自有配置/合成key启动900秒lease，两个真实间隔成功轮询后同episode recovery一次。初始烟测错误把20秒TTL与两个延后轮询混用并误计独立源事件，失败回执保留；修正夹具TTL30/事件类别后续验通过，未重跑已成功初始步骤。
- T09只读边界：节点key命令后缀、节点key请求LAN命令、LAN key请求节点命令实际exit2；错误key/专用信任文件实际COLLECTION_FAILED（执行已越过这些断言，后续夹具断言失败不冒充完整首轮成功）。缓存自然过期read返回RESULT_STALE且状态SHA不变。
- T09交付文档：新增docs/health/observer.md；独立正确性/安全审查已通过completion分别发起cmp-15c3dce5c2179f36/cmp-15c3dce5c3d79f37，结果待收取；不是已完成审查。原始进展JSON现20份回执，T09仍未提交/未转Done，真实武汉/ACL/收件仍NOT_RUN。
- T09独立审查结果已收取：local://nbh-t09-core-review.txt与local://nbh-t09-boundary-review.txt。发现队列满时已提交incident状态导致事件永久丢失、墙钟修正可延长旧绿灯、禁用监控误报恢复、不完整HTTP状态行误PASS、继承PATH执行ip/ssh，以及process-group不包含主动setsid逃逸的限制；均为代码推理，不冒充运行复现。
- T09审查修复计划：先各自RED，修复持久incident准入事务/单调源样本截止/disabled不投恢复票/HTTP完整行/固定可信可执行路径；明确可信ssh/ip/Python进程组边界不等于恶意可执行文件沙箱，主动逃逸需外部受控cgroup，不擅自修改宿主cgroup或扩大生产权限。修复后再次原生验收/审查，未提交。
- T09审查修复进展：禁用监控改为非投票并中断连续计数；HTTP缺CRLF/超长状态行经真实socket RED→GREEN，完整204仍PASS；固定/usr/bin/ssh与/usr/sbin/ip并净化子进程PATH/locale，经恶意PATH实际烟测未执行替身。Linux39项通过（1.522秒），source stale诚实保留。incident队列准入事务/单调样本截止尚待修复，禁止提交。
- T09两项HIGH已RED→GREEN：队列满的failure/recovery转移只有事件进入持久seen才提交，否则保留前态下轮再生；源boot/run/sample绑定collector boot与单调截止，同缓存重读、失败间隔、墙钟慢调和collector重启均不续期，节点与LAN/read两路径覆盖。Linux44项通过（1.556秒）；第二轮独立正确性/边界审查cmp-15c3e0df55579f38与cmp-15c3e0df57179f39已发起，尚待原生新路径烟测和结果，不提交/不转Done。
- T09第二轮审查已收取local://nbh-t09-core-review-2.txt与local://nbh-t09-boundary-review-2.txt：旧boot回放可重新锚定、LAN新样本漏collector时钟反转、node ID与lan:key事件键碰撞、JSON指数溢出；先补RED再最小修复。RDP按首个完整TPKT帧验证，不把后续流/EOF冒充已验证，需澄清文档。原生CLI已证明满队列释放后一次failure再生、节点/LAN过期单调缓存UNKNOWN且read字节不变；不改宿主时钟。
- T09最终定点审查发现队列修复仍漏瞬态：已拒failure在下一轮恢复、已拒recovery在下一轮再坏时会被抹去。改为每个incident持久保留一个pending_event，准入前暂停该incident计票但继续更新实际健康；有空位后先准入原事件再恢复计票。须补状态反转RED与真实CLI烟测，前述“仅回滚再生”不再作为充分修复证据。
- T09实现交付：8c91eb0（13文件，未push）；最终持久pending修复经状态反转RED→GREEN与实际CLI通过，Linux48项1.593秒。定点审查local://nbh-t09-pending-review.txt未发现该修复阻塞；代码证据local://nbh-t09-code-evidence.txt。四个自有容器/临时SSH身份/源树已验证归属后清除，共享主夹具未动；两份包头已本地保存并匹配原SHA。
- T09未完验收：禁止把隔离路径当武汉真路径；现有范围不含生产探针部署、ACL变更/故障或真实通知，缺受控生产来源/预批准目标与新路径实证，保留Jira处理中。后续E01–E05开发不消除此验收欠项。
- E01–E05的原始逐项目标、实施/失败/修复、原生/UI/SDK与恢复证据、Jira收据已归档TODO-m.md；E04/E05完成仅指本地及明确隔离层级，不授权生产启用或故障。
- 最新交付：C:/Users/25321/AppData/Local/Temp/nbh-e05-release-8fpugk5b.zip，1236894字节，SHA256 6610b5796c04e7944c4eaff817777c519dfa755af3fb81bf08e6993723b4b261；Jira实际ZIP附件11315下载复核同大小/同SHA，报告11314。
- 唯一剩余开发父项仍为NBH-19/T09完整现场验收；11-16已完成指定Linux两RDP路径、receiver SSH限权及中央timer上线，尚未满足所有代表方向/失联故障/网络ACL负向/真实通知收件。后续仅在各项精确授权与恢复条件具备后执行，不重放成功取密、Jira或生产操作。

## 当前未完成事项与推广门槛

**后续推广暂停，直到 56 的首次真实定时升级及功能验收通过。** 保留 56 现有计划和 48 小时版本龄要求；不因计划已启用、readiness 通过、检查跳过或维护窗口已经过去而放行。此次仅整理记录，不触发立即升级、重连、故障注入或其它节点的配置变更。

### 56：首次现网功能验收（阻塞后续推广）

- [ ] 读取实际定时执行记录、事务结果和运行版本，确认由原计划触发的真实升级成功提交。未到时间、版本龄不足、没有新版、下载失败或其它跳过结果均不能代替真实升级成功；不要为赶进度降低 48 小时门槛或手动触发来冒充定时执行。
- [ ] 确认新版实际运行，120 秒内恢复 management/signal，并完成连续 5 分钟健康观察；观察期进程稳定，不以磁盘上的版本号代替 daemon 版本。
- [ ] 对照升级前基线复核 public key、Mesh IP、实际持久身份目录、管理地址和关键 DNS 设置；保留 `DisableDNS=true`、自定义 init、外部 watchdog 原业务逻辑及连接意图。
- [ ] 复验经 `wt0` 访问 `http://100.125.222.103/` 的 HTTP 探针，并按 56 既有用途检查已配置的 LAN↔Mesh 转发、路由/出口及 DNS 行为；HTTP 探针通过不等于所有 LAN 业务通过，不为验收新增网络配置。
- [ ] 核对真实 LuCI 状态、独立监护及两个 watchdog 的升级后行为，无脚本错误、遗留维护或暂停状态；若发生失败，先核实恢复旧版后的连接、身份、DNS 与探针，保留故障及失败版本限制，不直接 reset 掩盖问题。
- [ ] 记录执行时间、旧/新版本、事务结果、健康观察及业务检查证据，明确写入“56 验收通过”后才继续推广。单次成功升级不能被表述为现网失败回滚或断电恢复已通过。

### 56 通过后的逐节点推广（当前均未执行）

- 每台操作前重新核对当时状态，保留私有备份和可用回退路径；确认真实身份目录、官方来源、连接健康、空间、早期恢复、独立监护、外部 watchdog 保护和本节点经 Mesh 可达的 HTTP(S) 探针。不得照抄其它节点的探针或假定历史状态仍然有效。
- [ ] **55**：安全门通过后启用北京时间 **03:30** 计划，完成该节点实际执行及功能验收，再继续下一台。
- [ ] **上海**：55 通过后启用北京时间 **04:00** 计划，逐项复验后继续下一台。
- [ ] **武汉**：最后启用既定四节点计划中的北京时间 **04:30**，特别核对既有 LAN↔Mesh 和路由/出口业务；不并行修改多台网关。
- [ ] **DC**：56 通过后再检查当前插件/客户端版本、二进制来源、持久身份与 DNS、init/watchdog、探针及恢复条件；按实际情况补齐插件部署，再安排错峰计划并验收。尚未指定 DC 的执行时间，不将 SSH 已通当作升级安全门已通过。
- [ ] 各节点完成后更新实际版本、时间、探针、事务/业务验收结果及备份位置；有失败即停止继续推广，先恢复并查明原因。

### DC：已解决的 SSH 身份问题

- [x] 用户确认 LAN 地址为 `10.10.10.190`；通过现有默认 `C:/Users/25321/.ssh/known_hosts`、`StrictHostKeyChecking=yes` 和已有登录凭据，只读登录成功，返回 `iStoreOS-dc`、iStoreOS `24.10.8`（`2026073111`）。
- [x] 默认文件中的 ED25519 指纹为 `SHA256:LFMvCo1TCL9b6i19V92XAI9FOGVZUCqDSc3y5IPa88s`。部署专用 `known_hosts_infra_gateways` 没有 DC LAN/Mesh 条目，**不等于当前存在主机密钥冲突**；后续可继续使用已验证的默认文件，不关闭严格校验，不需新增登录密钥或 NetBird Setup Key。
- 本次身份核验没有修改信任文件、插件、agent 或计划。以下历史记录中的“DC 未连接”仅描述当时部署/启用阶段；不再以旧 SSH 阻断结论排除 DC，未完成项改为上述就绪检查和 56 灰度门槛。

### 独立未完成项与验收边界

- [ ] **APK 签名信任**：匹配仓库签名 secrets 与公钥后重新构建并实测验签；解决前仍按 `UNTRUSTED` 对待，不因 CI 成功宣称签名可信，不擅自旋转密钥。与当前 IPK 节点的 56 灰度验收分开记录。
- 真实现网失败回滚、物理路由器断电/重启恢复尚未验证；现有证据为隔离回归，不为补齐证据而擅自对现网注入故障。这些维护验收如需安排，另行明确窗口和恢复入口。
- 上述候选版本和下一次执行时间必须在实际验收时重读；文末日期是启用时快照，不据此推定任务已经执行或通过。


## 调度与准入
- [x] 单机默认每天北京时间 03:30；维护窗口 03:00–05:00，正确换算设备时区，不修改系统时区。
- [x] 仅官方稳定 release，默认发布满 48 小时；custom、主动断开、服务关闭、连接异常、资源不足、其它维护时跳过。
- [x] 持久记录每日执行和失败版本，避免时钟回拨重复执行；错过不在白天补跑。
- [x] 现场错峰建议：56 03:00、55 03:30、上海 04:00、武汉 04:30。首次仅启用 56，其余计划仍关闭；56 首个真实升级维护窗口及功能验收通过后再逐台启用。DC 的 SSH 身份现已核验，插件/升级就绪仍待检查，详见上方待办。

## 共享事务与数据安全
- [x] 手动与定时更新共用事务核心和现有二进制互斥锁，长操作在独立 worker 中执行。
- [x] 自动模式强制版本固定、SHA-256、归档完整性、ELF 架构、可执行版本校验；准备期间旧服务不停。
- [x] 按峰值保留磁盘、临时内存及回滚空间；旧二进制及恢复所需状态保存在私有持久目录，不以 /tmp 作为唯一回退副本。
- [x] 旧服务完全停止后快照实际 profile/身份目录；同文件系统准备候选文件，再原子 rename，不删除后截断写入。
- [x] 不更换管理端、不注销、不使用 setup key 重新注册，不覆盖现有自定义 daemon init。

## 健康检查与恢复
- [x] 最多 120 秒恢复连接；连续健康观察 5 分钟，每 10 秒采样，停止旧版起 10 分钟独立硬截止。
- [x] 验证真实运行版本、稳定进程、management/signal、public key、Mesh IP、关键 DNS 设置和升级前可达的配置探针；不以 peer 数或 ping 代替业务检查。
- [x] 新版失败自动恢复旧二进制及必要状态并复验；连接未恢复不得显示“回滚成功”。
- [x] 激活失败版本进入阻止名单；回滚失败暂停自动更新，保留原因及现场。
- [x] 持久事务日志、独立异常恢复、早于 NetBird 的开机恢复，覆盖 worker SIGKILL、超时和重启；恢复幂等，恢复前清除孤儿写进程。

## 并发与界面
- [x] 插件 watchdog 在认证/连接意图处理之前识别维护状态；不借用 desired_connected=0 作为锁。
- [x] 外部 /root/ztn-watchdog.sh 必须接入维护保护；未完成对接不准启用无人值守；显式备份并前置保护，不重写其业务逻辑。
- [x] 手动连接、断开、配置应用、来源切换、二进制更新与事务协调；取消在切换后执行恢复，不杀出半成品。
- [x] 版本页提供默认关闭的启用开关、时间/时区、探针、版本龄、状态、结果/跳过原因、检查、安全触发、取消及解除失败限制。
- [x] 配置保存到独立 netbird_bin，保存计划不触发 NetBird 重连；插件自身不无人值守更新。

## 验收与文档
- [x] 隔离回归：下载网络失败、坏包/SHA 不匹配、空间不足、新版启动/连接失败、身份/DNS 改变、SIGKILL、重启恢复、watchdog 并发、时钟回拨/重复执行和取消。
- [x] 在隔离环境运行真实程序、证明提交/回滚/中断恢复；验证真实 LuCI 配置和状态界面，未修改现网 agent。
- [x] 更新中英文 README、架构、变更记录和本待办；已移除临时验收脚本、两个测试容器、浏览器页及 SSH 隧道。硬件故障、管理端停机/吊销不被冒充为可自动修复。

## 已执行验收

- 五个脚本通过：`test-agent-update.sh`、`test-binary-and-app-update.sh`、`test-timeout.sh`、`test-autoreconnect-signal.sh`、`test-rpcd-backup-migration.sh`。孤儿写入回归确认：杀死 worker 后，延迟子进程不能在恢复后再次破坏身份文件。
- 真实 OpenWrt procd / RPC / HTTP / LuCI 链路配合隔离原生 ELF 客户端夹具：观察 **302 秒**后才提交 `0.78.1 → 0.80.0`，身份/DNS 不变，提交后清理私有回退副本。
- 真实 LuCI 验证：启停计划及保存不重连；检查稳定版；安全触发；取消后恢复旧版；解除失败版本限制；后台切换来源及取消恢复；最终操作无浏览器脚本错误。
- 下载 CDN 不可达及 SHA-256 错误均保持旧进程 PID 不变；维护期间拒绝断开操作，认证 watchdog 不采样/改写意图，设置应用被延后。
- 停止独立监护服务后，截止 worker 仍可单独终止超时事务并恢复旧版；容器重启后，早期钩子先恢复旧二进制/身份，正常启动后再完成联网复验。
- 两个 LuCI JS 文件语法通过；42 条新界面翻译及格式占位符检查通过；38 个 RPC 方法与 15 读 / 22 会话写 ACL 对齐，另一个写方法仅供本机 watchdog 使用。

## 验收边界

- 上述客户端为隔离原生 ELF 夹具，HTTP 探针使用隔离接口；不是对现网 NetBird 控制面、真实 Mesh 链路或路由器断电的验收。
- 已补齐 24.10 IPK / 25.12 APK SDK 构建、发布资产校验、APK 隔离安装及四台现网插件部署。尚未取得物理路由器断电/重启或真实 agent 自动升级的验收证据；后续推广统一等待 56 功能验收，DC 另需完成插件/升级就绪检查。

## r7 提交、发布与插件部署

- [x] 核对改动、递增版本并确认发布安全门槛。
- [x] 提交本次实现、版本与验收文档：`14d3984988c6d22e0a7e477f8b8c75fb39ab6d71`。
- [x] 推送 main，确认 24.10 IPK / 25.12 APK 构建及 Release 资产通过：Actions `39011005934`，发布 `v0.2.0-r7`。
- [x] manifest、包版本/内容/依赖与 GitHub SHA-256 摘要通过，r6 回退包已保留。两份 APK 对仓库公钥实测仍为 UNTRUSTED；未配置匹配的签名 secrets，不宣称签名可信。
- [x] 56 主包与原已安装的中文包升级 r7；30 个包拥有文件逐一匹配，真实 LuCI、新 RPC、监护服务正常；agent PID/身份/DNS/init/watchdog 与现有 UCI 哈希未改变。
- [x] 依次升级 55、上海、武汉主包至 r7，保持各自原语言包安装状态；每台均通过 30 个文件校验、真实 LuCI 页面和受保护状态复验。DC 未连接、未修改。

### 部署终态

| 节点 | 插件 | NetBird 客户端 | 自动更新 | 验收 |
|---|---|---|---|---|
| 56 | 0.2.0-r7，中文包同步 r7 | 0.78.1，进程未重启 | 已启用，每天北京时间 03:00 | Connected，真实页面显示启用且无脚本错误 |
| 55 | 0.2.0-r7 | 0.78.1，进程未重启 | 关闭 | Connected，真实页面无脚本错误 |
| 上海 | 0.2.0-r7 | 0.80.0，进程未重启 | 关闭 | Connected，真实页面无脚本错误 |
| 武汉 | 0.2.0-r7 | 0.80.0，进程未重启 | 关闭 | Connected，真实页面无脚本错误 |

- 四台身份实际目录仍为 `/overlay/netbird-lib`；插件部署时保留 `DisableDNS=true`，未接入外部 watchdog。随后 56 计划启用时显式备份并前置维护保护，原 watchdog 业务逻辑逐字未变；其余节点未修改。56 启用后身份文件、NetBird 二进制、自定义 init、resolver、`/etc/config/netbird` 哈希及 PID 均未变化，UCI 无待提交变更。
- 每台保留私有安装前备份、r6 回退 IPK 和 r7 安装日志；临时包暂存目录、只读 UI 会话、浏览器页、SSH 隧道和隔离安装容器已清理。
- Release：[v0.2.0-r7](https://github.com/InoriHimea/luci-app-netbird/releases/tag/v0.2.0-r7)；构建：[Actions 39011005934](https://github.com/InoriHimea/luci-app-netbird/actions/runs/39011005934)。

## 2026-10-17：56 自动更新计划启用

- 用户授权启动计划后，按既定灰度门槛仅启用 56：`enabled=1`、`time=03:00`、`timezone=UTC-8`、`min_age_hours=48`、`profile_dir=/overlay/netbird-lib`。未调用立即升级、重连或服务重启。
- 探针为 `http://100.125.222.103/`（55 的 LuCI HTTP 服务），56 上 `curl --interface wt0 --noproxy '*'` 实测 HTTP 200，路由为 `wt0`。用于证明升级前后跨节点 Mesh HTTP 可达，不代表下游所有 LAN 业务均已验收。
- 原配置及外部 watchdog 备份：`/root/netbird-auto-enable-20261017/before.tar.gz`（私有目录，归档 0600）。官方集成入口另保留 `/root/ztn-watchdog.sh.before-netbird-update`，仅在原脚本首行后增加维护保护；原业务逻辑与备份逐字一致，空闲 guard 允许正常巡检。原每两分钟 watchdog cron 不变；周日 03:00 的历史脚本仅检查并通知版本，不执行安装，保持不变。
- RPC readiness 通过，独立监护及早期开机恢复就绪，事务为空闲。真实 LuCI 版本页显示已启用、03:00、48 小时、探针和持久身份目录，浏览器无脚本错误。
- 启用时 RPC 返回的下次计划检查：**2026-10-18 03:00（北京时间）**。当时白天实际调用 tick 返回 `not-scheduled-minute`，未启动更新；此处不代表该夜间任务已有执行结果。
- 启用时检查的候选为 `0.81.2`，发布于 `2026-10-16T09:18:31Z`（北京时间 10-16 17:18:31）；当时检查返回发布未满 48 小时、不可升级。按该快照估算，若候选版本不变，10-18 03:00 仍将跳过，最早符合版本龄的既定计划为 10-19 03:00；后续须核对实际候选和结果，不为灰度降低版本龄。
- 55、上海、武汉现场读取开关仍为关闭，监护服务运行；DC 未连接、未修改。56 首次真实升级和回滚能力的现网结果尚未发生，不以本次启用、跳过或隔离测试冒充现网升级成功。

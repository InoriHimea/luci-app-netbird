# 已完成任务（2026-11）

## [完成] timer修正后独立24小时窗口完整审阅与事后保护（2026-11-24）

- 原始目标：本人要求按推荐顺序继续：全量审阅修正后窗口、只读核对事后保护，再同步账本/文档/Jira并本地提交。只读，不重新采样、不once、不取密、不改远端。
- 结论：取证完整（1441/1441、最大间隔60.016秒、原JSONL SHA256 dab88102a1f694f06760df0f3a9f8a3b3db2041f9424ee7263f8b173ecb110f0不变）；健康有限定通过、非全绿。rdp55独立run全PASS，rdp56仅1次孤立CONNECT_FAILED；其余为读取超时类UNKNOWN且均恢复。详细计数见TODO.md NBH-19节。
- 事后保护UTC11-24T02:22：武汉11SHA OK/PID9497、中央10SHA一致、两timer active、automatic OFF、owner none/accepted0；不冒充截止时刻同步校验。
- 证据：p1-postfix-20261118T114322Z/review_postfix.py（SHA256 1f640a40…）、review-20261124.json（17203字节，SHA256 0ba692dfb937d7ef036639ae6e3481ae320d0858a0149411b9576779f7f91ed6）、protection-after-review.json（1769字节，SHA256 3e94d31420f2bf23b1c4d5379467db2da0dd119931af92894a2d0065e0b9f3ed）。
- Jira：经Orca已保存连接（admin，orca jira 1.4.263）发审阅评论，标记NBH-P1-POSTFIX-REVIEW-20261124-01；NBH-19评论11400、NBH-1评论11401均回读正文一致，状态保持处理中。Orca CLI无附件命令，附件p1-postfix-24h-review-20261124.json由本人手动上传NBH-19，附件11402（2026-11-24 10:37:07 +0800，admin，application/json，17203字节与本地一致）；依据本人粘贴的REST附件元数据核对，附件未下载、远端SHA未核验，回执jira-review-attachment-receipt.json。未读取浏览器凭据。

## [完成] timer修正后独立24小时只读取证启动（2026-11-18）

- 原始目标：本人要求有任务则按推荐顺序继续；先进行修正后独立24小时观察，再按完整证据推进剩余验收。此节只归档准备和启动，完整窗口审阅仍在TODO.md进行中。
- 预检：原窗口collection_complete且未覆盖；中央10文件SHA匹配修正后基线，武汉11保护SHA/PID9497一致，两个timer active、P1 enabled，automatic OFF、owner none/provider_accepted0，两LAN起始fresh/PASS且boot不变；窗口结束早于最早身份期限12-15T04:07:52Z。
- 独立窗口UTC2026-11-18T11:47:06.218417至11-19T11:47:06.218417（北京时间11-18 19:47至11-19 19:47），持久service nbh-p1-postfix-24h-20261118，wrapperPID62816/PythonPID28232。目录C:/Users/25321/AppData/Local/netbird-observer-observations/p1-postfix-20261118T114322Z/，父级postfix-20261118-launch.json和自身attempt独占防重。
- 采样：每60秒只读中央read及武汉已发布缓存/进程，24小时截止/64MiB上限；不调用once/凭据helper/新目标探测，不改远端配置。新增同一缓存的snapshot原因、前后变化字段名、可用性与run绑定，不外传边界原始值；节点有效unique排除null，跨读代次不一致保留计数。
- 验证：实际新入口smoke两端ok/15检查；原生ucode纯内存fixture正确识别routes变化，脚本编译检查通过。首4样本/4中央独立poll、最大间隔60.00046秒，边界可用且run一致、中央保护匹配；其中UTC11:50:06的rdp56 UNKNOWN/COMMAND_TIMEOUT如实保留，不把启动证明当全绿或24小时通过。
- 新入口SHA256 87a21858436a1270d406478f2c81d52c1a178743287806d1142a83f906a9995b；samples/status/reference/preflight/smoke/protection-before/startup-checkpoint留新目录，原窗口及报告不变。父级claim只是防重预约，实际运行以本窗口attempt/status和服务ready/persist证据为准。
- Jira启动检查点：NBH-19评论11261、NBH-1评论11262均POST201/GET验证，保持处理中，页面已释放。必须保持本机开机联网不睡眠；空窗不补造，不能自动重开同一轮。
- 剩余：到期检查全部分母/唯一run/重复/新鲜度/异常原因/边界摘要及前后保护，分别判断取证完整和健康。其余方向/失联/ACL/通知、56恢复入口/窗口、推广、签名与物理故障门槛未改变；不续签或延期证明。


## [完成] 本地修改提交及Jira与待办核对（2026-11-18）

- 原始目标：本人要求先提交本地修改，再查看剩余Jira任务及待办；本轮不推送、不改Jira状态或执行生产操作。
- 首次提交：0d83344，fix: finalize r17 compatibility fixes and P1 acceptance records；22文件，1034行新增/28行删除，包含r10–r17兼容性修复/行为回归、package-input.py及README/发布/验收/账本。没有暂存Python缓存，未改写既有提交或推送。
- 本轮验证：实际运行package-input.py，118归档项/26个0755目录/10个LF可执行脚本通过，版本r17；输入SHA256 0db5702cd956c4d97b4d2a96e9af9efdb4dc204d9d27ff853aef22488db723da与此前已原生验收r17输入一致。22个提交文件的凭据模式筛查无命中；未声称本轮重跑原生ucode/双SDK或生产验收。
- Jira实时全量搜索：24项，17完成，7项处理中（1 Epic、5 Story、1 Task）；另完整读取NBH-19与NBH-1评论，最新11259/11260确认timer及三自然周期验收。查询页已释放，API只读，未转状态/改说明/发评论。
- NBH-1：Epic父目标，关联未完成项仍阻塞收口。
- NBH-4：F-03路由检查；A23真实多区/未授权目的与协议负向安全验收未完成。
- NBH-6：F-05业务探测与视角；A08完整单端点故障对照、A23负向ACL、其它真实方向与跨视角验收仍缺。指定Linux两RDP路径/受限身份已完成，不沿用正文旧快照重复部署。
- NBH-7：F-06历史变化取证；A03真实已连接engine重连且daemon PID不变的完整证据未完成，旧异常before/after不可追回，不以隔离offline daemon替代。
- NBH-9：F-08低噪声告警；真实中央/节点/LAN联合投递与用户收件闭环未完成，仍缺精确用途/收件批准。
- NBH-10：F-09 LuCI页面；真实P1结果接入与现场端到端跨视角验收未完成，页面可打开/合成缓存不是通过。
- NBH-19：T09 P1；最小三机上线、受限SSH、24小时取证及timer修正已完成，其它方向、真实失联恢复、网络ACL负向和真实通知收件未完成。修正后的独立24小时观察尚未启动，不替换原样本。
- 本地剩余：56具名维护窗口及不依赖NetBird的恢复入口、真实定时升级与功能门槛；通过后55→上海→武汉→DC逐台推广；APK签名仍UNTRUSTED；物理断电/真实故障回滚未验。历史SSH/代际/RDP原因缺口保留，不用新数据补造旧根因。
- 文案核对：Jira正文保留旧需求/阶段快照，NBH-6/19的Linux未交付文字已落后于最新证据；以最新评论与分层验收判断，不因此转Done。本地TODO状态摘要及NBH-19未勾选项已更新，早期进度明确为历史；完整历史逐字保留。
- 非秘密查询证据：local://nbh-jira-backlog-audit-20261118.json和local://nbh-jira-backlog-latest-evidence-20261118.json；审阅记录另作本地docs提交收尾，不推送。


## [完成] gateway3 P1 timer最小修正与三自然周期生产验收（2026-11-18）

- Jira完成证据：NBH-19附件11322，11421字节，下载SHA256 f03657d1cd00ca72647d1b240e6690b9cc171ccc12e48d2f60415d634b38c3db一致；NBH-19评论11259、NBH-1评论11260均POST201/GET确认。状态保持处理中，旧附件/评论不覆盖；本轮浏览器页已释放。

- 原始目标：本人明确选择“实施最小修正并验收”，只修正gateway3 P1调度跳轮，备份/原生验证/切换后观察至少3个自然有效周期，不扩大为24小时重采或其他生产动作。
- 实施：事务nbh-p1-timer-fix-20261118-f5532f76，原timer SHA087753b02d733a14bb19485d2cf723e942fa2dd2dc78c7dec334463af86b03c7；原文件备份/root/nbh-p1-timer-fix-20261118-f5532f76/timer.before（受保护）。仅OnUnitActiveSec=60s→OnUnitInactiveSec=60s及相应描述，候选原生systemd-analyze verify退出0，daemon-reload/只restart timer退出0，APPLIED。
- 已加载配置：TimersMonotonic同时含OnUnitInactiveUSec=1min和OnActiveUSec=15s，不再含OnUnitActiveUSec；该属性有多行，单字典解析会丢项，最终保留原始lines验证。timer enabled/active waiting，新SHA d9a9842895f66518cdef2aa0a5e18d8c9acc04fea94e446a4ea14a9d190c8b0e。
- 行为验收：journal follow只读等待，不轮询重触发；切换后poll1794994769、1794994833、1794994897共3个有效自然周期，间隔64/64秒。每轮武汉fresh、rdp55/56 PASS且fresh、run推进，重复旧poll0、service failure0，原来源/接口/网关/目标/预算/baseline/boot保持。
- 边界纠正：首次watch按日志时间包含了OnActive启动重显的切换前poll1794994687，不作为合格3轮。原timer-natural-cycles.json保留，timer-natural-cycles-boundary-review.json明确作废其通过结论；最终以timer-natural-cycles-qualified.json的3个poll_at>切换完成时刻为准，不掩盖首轮测量错误。
- 最终保护：武汉11保护SHA/PID9497与start保持；中央保护仅获准timer改变，服务文件/代码/配置/known_hosts等其余9文件不变。P1与旧ha timer active，自动恢复OFF、通知owner none/provider_accepted0；两LAN最终PASS/fresh且boot5f5aa365-ca78-4f58-88d0-d41d3a2e9c54保持。
- 证据在原观察目录diagnosis-20261118/：timer-cutover-attempt/before/result、timer-loaded-directives、timer-natural-cycles-qualified、timer-final-protection及timer-production-acceptance.json；独占attempt和原备份保留，不重复切换。没有手动once、业务取密、重启agent/宿主、重开24小时或修改56/路由/ACL/目标/阈值。
- 限定结论：调度修正及短窗口原生验收通过，不代表新的24小时持续健康、其他历史SSH/代际/RDP原因或全站点/推广通过。后续门槛仍见TODO.md。


## [完成] P1调度跳轮定位与本地候选验证（2026-11-18）

- Jira回执：NBH-19附件11321共24918字节，下载SHA256 6d84f2a1425b2001a1f29d9ae1c4db5f87e023ae6ccb72861544b79cff9b2e5a一致；NBH-19评论11257、NBH-1评论11258均POST201/GET确认。此为原附件11320解释勘误，未覆盖原报告或转Done；生产timer应用尚未批准/执行。

- 原始目标：本人批准按路线推进，先定位旧源结果/SSH异常/代际与RDP瞬态，再按门槛推进现场验收。此节归档已完成的有界排查与候选验证；生产修正、历史缺口与其它现场门槛仍留TODO.md。
- 调度机制：扩展窗口1424次service调用/1360个唯一poll/64次重复旧poll；32次RESULT_STALE全部匹配重复发布。现役OnUnitActiveSec=60s与Python入口monotonic严格60秒准入计时基准不同，入口间隔略不足60秒时整轮跳过，形成约120秒实际采集间隔；代码和时间线匹配，启动抖动机制已离线重现，原历史入口毫秒耗时未保存。
- 勘误：上一审阅按sampled_at建字典覆盖了首次发布，119–121秒对应最后一次跳过后的view。首次poll源年龄58–60秒，首次完成输出61.520–64.994秒，不是新SSH读到了两分钟前的文件。旧附件11320、原review和样本均保留不覆盖；下方原审阅节的旧源解释以本节为准，异常分布/保护结论不变。
- 最小候选：仅本地timer将OnUnitActiveSec=60s替换为OnUnitInactiveSec=60s，描述改为completion-spaced；其余Timer/Install值不变。避免改变产品的早调用防重复、140秒TTL或10000ms预算。候选SHA256 d9a9842895f66518cdef2aa0a5e18d8c9acc04fea94e446a4ea14a9d190c8b0e。
- 离线实测：执行实际observer.central.cycle/view，控制时钟/SSH fixture并记录内存状态写入；59.9秒入口无SSH/无写入、旧结果随后RESULT_STALE；60秒边界执行；完成后60秒的62.7秒入口执行并保持后续fresh。配置解析及差异检查通过。这不是Linux原生timer验证，也未应用到gateway3。
- 历史证据缺口：13个代际/RDP异常run在102个当前历史/特殊缓存中无匹配，原采样不含before/after，具体字段/超时阶段不能追回。代际签名不含流量计数器，API与SSH读取同一latest/cache逻辑；缺证不等于没有变化。另发现未获得代际时forward原因可能误标，但实际本轮node:collection也为GENERATION_CHANGED，不将该旁支冒充根因或顺带改码。
- SSH范围：node调用最多3秒，LAN完整SSH调用最多目标2秒+1秒且受总预算约束；COMMAND_TIMEOUT不等于RDP目标超时。51.160固定窗口来源过滤认证2711次接受/8次关闭、无timeout/reset/auth失败分类，不绑定逐probe，且中央未保留stderr/阶段耗时，不能证明网络丢包有无。
- 证据：原观察目录diagnosis-20261118/diagnosis.json与netbird-observer-p1.timer；原样本/attempt未改、业务取密0、新增目标探测0、远端配置修改0。生产timer修正、自然周期验收需本人批准；其它方向/失联/ACL/通知、56独立恢复与维护窗口、后续推广、APK签名和物理故障边界不变。


## [完成] P1完整24小时取证审阅与保护复核（2026-11-18）

- Jira收口：NBH-19附件11320，30312字节，下载SHA256 04427f2d3c15ab1b295eb70710b78a8a309709dda5a652cd763eae16d15b8b87与本地一致；NBH-19评论11255、NBH-1评论11256均POST201/GET验证。旧tab失效前未执行请求，新tabGET确认不存在后上传；留本地attempt/receipt/verified记录，不重复发布，状态未转Done。

- 原始目标：承接本人批准的P1持续24小时只诊断观察，审阅完整分母、空窗/重复周期、状态原因、资源和前后保护；区别连续取证与业务健康，不能以单轮或零FAIL替代24小时验收。本轮完成审阅，不关闭整个NBH-19或推广门槛。
- 取证通过：原采样终态collection_complete，1441行/13251513字节；UTC2026-11-15T17:45:04.477299至11-16T17:45:07.934613，实际壁钟跨度86403.457秒，最大采样间隔63.275秒、>75秒空窗0。逐行JSON解析和node/LAN/coverage计数完全匹配status；原始文件未改写。
- 分母：1355个独立中央样本、86次重复；武汉有效非空run1345、LAN55/56各1345。原status的node1346包含(null,null)哨兵，不是有效运行，审阅报告纠正但不篡改原记录；1441个观察样本不等于1441次独立探测。
- 健康未通过持续全绿：中央武汉41个非fresh样本=32 RESULT_STALE+8 COMMAND_TIMEOUT+1 NODE_UNREACHABLE；LAN55为1431PASS/10 COMMAND_TIMEOUT，LAN56为1431PASS/9 COMMAND_TIMEOUT/1 NODE_UNREACHABLE。以上均单样本异常且下一采样点恢复；约60秒到下一正常样本不是精确故障时长，不宣称目标宕机/真实丢包。
- 武汉15项检查分母始终完整、本地缓存始终fresh；6项基础UNKNOWN保持。10个样本出现GENERATION_CHANGED（8段，最长连续2样本、下一正常点约120秒）；独立router55/56分别1/2次TIMEOUT，均后续恢复。固定未知与瞬态异常分开，不以LAN成功覆盖结构/router未知。
- 日志关联：只读中央service扩展UTC17:44至次日17:47日志，5696条记录=1424次Starting/JSON应用结果/Deactivated successfully/Finished，启动间隔60.002–61.023秒，无其它服务失败事件。按结构化JSON解析，不能将failed字段名（值0）误当失败日志；1424是扩展窗口，不混入1441观察分母。
- 新鲜度线索：32次RESULT_STALE全部匹配中央发布记录，发布时fresh但源结果已118.867–120.521秒旧；读取时178–180秒，超过140秒限制。同期直接武汉缓存全部fresh且比中央源结果新119–120秒。排除这些样本的systemd停调度，尚未确定旧源结果成因，不改freshness/超时或重触发探针。
- 保护复核：全窗引用配置/身份/agent和health进程无变化、两timer active、自动恢复OFF、owner none/provider_accepted0；中央10文件SHA保持。窗口结束后UTC11-17T15:51:20只读复核武汉11保护SHA/PID9497一致、中央SHA一致、两LAN PASS/fresh且boot保持。此为事后复核，不冒充截止瞬间11文件同步采样。
- 资源：中央last-run MemoryPeak取样最大15343616B、CPUUsageNSec249665000；武汉health RSS1520–1600KiB。仅采样峰值，不声称完整资源profiling/24小时CPU用量。
- 证据目录C:/Users/25321/AppData/Local/netbird-observer-observations/p1-20261115T174221Z/：review-20261117.json、review-current-cache.json、protection-after-review.json、central-journal-parsed.json及原samples/status/reference/attempt。原JSONL SHA256 be071a5418d8833acdae89c0432d6279713bf9fba0951c4f522c1793a8e00a9a。原采样入口作为审计材料保留，不重新执行。
- 剩余：旧源结果与SSH瞬态异常根因待定位；其它生产方向、失联恢复、网络ACL负向、真实通知与56窗口仍未验。身份/证明到期约束不变，不扩权、不取密、不改远端服务/路由/ACL/配置；Jira保持处理中。


## [完成] P1只读24小时取证启动与UNKNOWN归类（2026-11-16）

- 原始目标：本人批准按推荐继续P1持续观察及只读UNKNOWN分析，另要求将SSH key/boot证明到期纳入具名验收日历。本节仅归档启动与归类；完整24小时审阅仍在TODO.md等待真实时间窗口，未验收通过。
- 归类：初始武汉fresh/snapshot complete，15项9PASS/0FAIL/6UNKNOWN；2peer为PEER_SELECTION_UNVERIFIED，2路径router和2节点LAN为NOT_CONFIGURED。独立router endpoints均PASS，中央LAN两PASS；model保守聚合保留local_structure/router_probe/overall未知。实际部署model/evaluate/cache/observer-read四SHA匹配，无改码/删检查或放宽判定。
- 有界取证：本机service nbh-p1-readonly-24h-20261116已ready并设persist，PythonPID66552；UTC11-15T17:45:04.464995至11-16T17:45:04.464995（北京时间11-16 01:45至11-17 01:45），每60秒读取中央read及武汉缓存/进程，24小时截止、64MiB上限、独占attempt、JSONL逐条fsync/status原子写入。不调用once、业务探测或凭据helper，不改远端配置。
- 启动验证：实际smoke两端ok，启动后3样本/central-node-两LAN各3独立run，最大间隔59.9998秒，两LAN各3PASS，无读取失败/过期/边界或引用变化计数。中央last-run MemoryPeak取样最大14077952B/CPUUsage211627000ns、武汉health RSS1544–1576KiB，仅初始取样。
- 保护：武汉原11保护SHA/PID9497保持、自动恢复OFF；P1与旧ha timer active，通知owner none/投递0。本机必须保持开机联网，睡眠/断网空窗不补造；60秒采样与约61秒timer可能合理重复，需结合唯一run与新鲜度审阅。
- 证据：C:/Users/25321/AppData/Local/netbird-observer-observations/p1-20261115T174221Z/；sampler脚本为仍在运行的采集入口，不能提前清理。samples.jsonl/status.json/reference.json/unknown-initial-review.json/protection-before.json均保留，到期重新核对完整分布和前后保护，不将REQUIRES_FULL_REVIEW_NOT_AUTO_PASS当PASS。
- 日历：具名验收应在2026-12-15T04:07:52Z首key到期前安排；LAN key04:10:15Z/证明14:38:06Z随后到期，源boot/路径绑定变化更早失效。延期需另批维护与新证明，无自动续签/证明延期或管理key兜底。
- Jira：NBH-19评论11253、NBH-1评论11254均POST201后GET200验证，未转Done；无新PCAP/秘密上传。56维护窗口/独立恢复与推广门槛保持。


## [完成] NBH-19两用途交付、受限SSH与中央最小P1上线（2026-11-16）

- 收尾：最后复核P1 timer enabled/active waiting、service Result=success/ExecMainStatus0/User=netbird-observer/TimeoutStart20s，旧监控active/waiting。自有本机一次性p1_deliver.py/acceptance.py及bytecode已删除，保留非秘密报告、持久防重记录与回执；不得按历史脚本路径重放业务读取/交付。final-service-state.txt留证。

- 最终交付：按本人要求完成两用途凭据安全交付、真实SSH限权、中央单轮及通过后60秒timer启用；这是最小三机P1上线，不是整个NBH-19/全站点/推广验收完成。原始业务目标和逐步快照保留在下方。
- 实际验收：固定netbird-observer-p1.service/UID987/LoadCredentialEncrypted通过12项命令/认证与8项PTY/TCP转发/X11检查，共20项。合法cache fresh与LAN disabled命令可用，任意shell、命令后缀、SFTP、错用途key、错目标、PTY、直接/远程转发、X11被拒；agent/userRC/tun依据实际restrict解析与服务实现/配置，不冒充独立现场故障注入。
- 上线：仅两个独立配置enabled从false改true，正式单轮武汉node fresh、两LAN PASS。启用timer后70秒观察sample1794761490→1794761551，两个LAN run_id变化且PASS/fresh；timer enabled/active waiting，原netbird-ha-monitor.timer active/waiting，owner none/投递0。site overall仍unknown，未覆盖原结构/router等未验视角。
- 保护与回退：两端原授权字节均保留，root私有backup/<EID>/authorized_keys.before；LAN与central启用前配置分别在/root/nbh-p1-activation-20261116/config.before.json。武汉11保护SHA/PID9497一致；没改agent/路由/ACL/56封锁/计划。临时systemd验收override和远端acceptance.py已删除，恢复原正式入口/20秒deadline。
- 期限：Wuhan/LAN SSH key分别2026-12-15T04:07:52Z/04:10:15Z；当前boot路径证明2026-12-15T14:38:06Z到期，绑定变化立即失效。不自动续签、重取凭据、延期证明或借管理key兜底。
- Jira完成同步：NBH-19评论11251、NBH-1评论11252均POST201/GET200验证，任务未转Done；NBH-19附件11319，22333字节，下载SHA763c1ccb0b56173d3ffa198a00127e0450ed4f432639e1f4ef32efe3d9b7e1ac一致。其余生产方向/失联故障/ACL负向/真实通知收件与56现场验收仍保留TODO.md。
- 非秘密证据目录C:/Users/25321/AppData/Local/Temp/nbh-p1-reproof-xqo0ogkv/：p1-live-report.json、acceptance-core.json、acceptance-forward.json、central-first-collection.json、automatic-cycle.json、final-preservation.json及Jira回执。无PCAP/私钥/DPAPI上传。
- 失败如实保留：此前误用武汉未运行sshd配置/错误authorized_keys位置、shell key选项拼接/解释器与无Python假设已在补充取密前纠正并真实烟测；两次验证脚本漏传now/引用已过滤path_verified字段属于验收脚本错误，不是产品故障，也未补发探测掩盖。此前已成功read/revoke后内存丢失，只有本人明确补批的各一次读取被执行，无静默重取。

### 实施历史快照（以下状态仅对应当时，最终结论见本节首部）

- 原始目标：本人要求继续后续任务；承接24小时取证后的优先项，推进真实Linux LAN探针和中央汇总，不把已完成连续采集层等同P1或推广通过。
- 子项1：只读查既有项目/资产记录及已管理Linux候选，核实其自然来源、接口、下一跳和目标路由；不广扫网段，不为合格而停NetBird/改路由，不读取业务秘密或维护身份。
- 子项2：按现有observer契约核对合格来源、中央落点和专用forced-command身份的接入条件，完成可达的配置/受限接收端验证准备。新建VM/容器、授予生产SSH身份、安装调度、抓包取证或真实通知若需要具体生产变更，先呈现实际目标与最小范围再取得该项批准。
- 子项3：根据核定结果执行已获准范围，保存非秘密证据并同步NBH-19/父任务；身份或目标缺失保留明确阻塞，不伪造attestation，不重放成功Jira操作。
- 验收：交付具名合格来源与实测自然路径/能力结论、最小受限接入方案及真实未决项；现场产品探针须有对应新路径证明和受限身份后才可算完成。武汉现有monitor/agent/网络、56封锁/计划及推广门槛不变。
- 来源资格与路径均已完成：51.160/eth0自然到两RDP目标经192.168.3.1，不走自身NetBird；原有管理SSH只用于已批准预检/部署，没有复制或用作常驻采集身份，旧Torii夹具Bao身份未用。两条实际SYN/RDP证明见下方及TODO-m.md。
- 中央信任已核清：旧known_hosts_gateway2_verified对应退役8.134.92.75；E:/pikachu既有11-09迁移账本明确100.125.250.19已由gateway3/115.159.158.245接管，既有known_hosts_gateway3_migration_20261109_verified的两条pin指纹均为SHA256:sxg5lGNIDwZtFGxsbz/eqpzH493b0MTkrFD4LsCAWbs，与呈现值严格一致。改用该既有正确pin文件后只读登录成功，未改任何信任文件或放宽校验。
- 中央当前：gateway3/100.125.250.19已安装独立nonroot用户netbird-observer（UID987/GID985）及代码/config/state/service/timer；disabled CLI与原生read服务exit0。新timer disabled/inactive、两credential尚未交付，旧netbird-ha-monitor.timer active/waiting保持；原业务/agent/路由/ACL不改。
- 来源就绪预检：51.160为主机netns（与PID1相同）、无NetBird策略规则，source+device bind通过；OpenSSH9.9p1支持受限key方案，/root/.ssh700、authorized_keys600，未读其内容。当前全局SSH允许PTY/forward/userRC，必须用独立key限制并实测，不把普通root登录当P1受限身份验收。
- 接收器当前：51.160已安装固定代码/disabled配置/两个真实新源attestation，武汉仅新增独立cache gate；两个实际gate无身份均COMMAND_DENIED，未追加公钥或身份metadata，不能把普通管理SSH或内存授权测试当生产限权通道通过。
- 配置与保护：固定rdp55/rdp56、2000ms、source51.160/eth0/gw3.1/baseline1；新proof绑定boot04351e13-7c39-43eb-a20a-a453804bbb2f，有效期不超过2026-12-14T17:08:37Z，boot/路径/基线变更须新证明。武汉11保护SHA/PID相同，原diagnostic配置与56封锁/计划保持。
- 已部署边界：仅新增三机独立P1目录/非root账号/停用中的原生单元，不接管旧监控，不开放新公网端口、不新增P1 VM/容器；receiver gate与consumer credential路径按固定contract，授权公钥/metadata及加密业务credential等身份交付后才写入。
- 身份边界：两用途非秘密成功回执已本机只读核对，status均IDENTITY_DELIVERED，identity_saved/receipt_saved/login_token_revoked均true，三项unknown均false；role/target/consumer/KV version1选定绑定相符、身份及key均未到期。仅核对receipt JSON，未读取DPAPI/私钥、未联网或消耗登录次数；完整身份/回执绑定仍由获准helper在真实消费时校验。
- 本人已精确批准：最小三机P1试点（51.160固定两目标探针、武汉cache-only身份、gateway3独立非root/60秒采集），先按统一GUI受控开通两用途SSH身份；另批准192.168.51.160→10.10.10.55/.56:3389两次无凭据RDP，以及武汉br-lan/wt0≤30秒/40包纯SYN头取证，原PCAP只留目标root私有，不外传。独立自动截止先验，再发请求。
- 当前交付：E:/pikachu/infra/deployment/dist-netbird-observer-20261115/enrollment-gui/enrollment-gui.exe，self-check24用途/0问题/Tk可用，两实际窗口已视觉验证；工作证据C:/Users/25321/AppData/Local/Temp/nbh-p1-20261115-35x617k_/implementation-manifest.json及p1-implementation-report.json，不含PCAP/密钥/DPAPI。
- 本人私密开通步骤已回报完成：wuhan-snapshot完整成功回执已提供，lan-51160在重新启动其面板后由本人回报“完成”。不重复Create/issue、不额外check登录；后续在获准消费前核对非秘密成功交付回执及绑定，不在聊天传token/私钥。
- 本人关闭原GUI后要求再次启动已完成：曾重新打开netbird-observer-lan-51160，PID67512/HWND39061682实际可见；仅核对自有窗口可见性，不读输入框/截图或触发预检/Create。随后本人回报第二用途已完成；本会话未操作私密维护或读取业务身份。
- 本人提供的wuhan-snapshot交付回执：IDENTITY_DELIVERED，identity_saved/receipt_saved/login_token_revoked均true，mutation/save/secret_id三项unknown均false；enrollment_id=95deb1bc-ef37-42e9-ae29-c805eb5eea0b，key指纹SHA256:w8qKJ6pu/tBKAGoM+IGCIpvcDgYhiM+TIeNRF34KMQA，身份到期2026-12-15T04:07:57.805815+00:00，key到期2026-12-15T04:07:52+00:00。255仅交付时额度快照，不是实时余额；此为本人回报，未由agent取密复验，不等同receiver部署、业务消费或P1上线。
- 权限衔接：两用途reader/engine/gate/GUI及最小HCL模板已验；16目标备份/apply/check全ok、块外字节全保持，新OMP18.13.3原生完整规则/helper/两role/KV与不追认边界均true，无prompt/业务取密。当前实施会话不读新DPAPI；待身份交付后由实际加载精确边界且获准当次读取的消费会话接续。
- 接续顺序：核对成功交付/pins/gate SHA→一次获准读取并revoke→gateway3 host-key加密credential与receiver公钥/公开metadata交付→真实命令/PTY/forward/错误目标拒绝→一次中央收集→才启用timer。当前业务身份、专用key认证/中央循环均未通过，不将安装disabled当上线。
- 本人追加要求“完成剩下作业”：目标为两用途凭据安全交付、真实SSH限权/一次中央收集及通过后启用timer；本次先核对允许的非秘密成功回执。现行规范明确本实施会话不读新DPAPI，不能通过子进程/子agent或改规则追认；业务读取与部署由实际加载精确规则的获准消费会话接续，不重复Create/check，不擅自启用timer。
- 非秘密回执核对完成：lan-51160 enrollment_id=be1d4694-7458-4216-8cc4-d4c7527c45e9，身份到期2026-12-15T04:10:21.009162+00:00、key到期2026-12-15T04:10:15+00:00；wuhan-snapshot与本人先前提供回执一致。两身份无需重签或额外登录。剩余硬门禁是规范禁止本实施会话读新DPAPI，而非缺少身份或要求本人再次开通；须全新消费会话实际加载精确规则后按本人批准范围交付/验收，不能用子进程/子agent绕过，timer保持disabled。
- 新消费会话接续（2026-11-15）：当前会话已实际加载NetBird P1两用途精确规则，本人“完成剩下作业”覆盖一次各用途读取/revoke、加密交付、真实SSH限权/一次中央采集及通过后启用timer；不重复Create/check。只读预检发现51.160实际boot_id=5f5aa365-ca78-4f58-88d0-d41d3a2e9c54，而两attestation绑定04351e13-7c39-43eb-a20a-a453804bbb2f；boot变化使旧证明失效，须新限定路径证明后才能继续。武汉publisher fresh/config8/baseline1、agent PID9497及gate SHA匹配；51.160 gate SHA匹配；中央timer仍disabled/inactive、旧监控active/waiting、两credential不存在。本轮未读DPAPI/私钥、未改远端或启用采集。
- 本人已批准按原限定范围重新路径取证：新证明绑定当前boot 5f5aa365-ca78-4f58-88d0-d41d3a2e9c54，verified_at=2026-11-15T14:38:06Z、expires_at=2026-12-15T14:38:06Z，evidence SHA=f3a9da3cd40c430e5add283170978d22b912d1acddfd1667914fbf5c8b3ed586。两流62055/62056在br-lan入/wt0出同seq同目的同端口，SNAT100.125.129.101，转发0.285/0.238ms；4纯SYN/载荷0/内核丢0，独立20秒guard实际3142ms正常drain，RDP TPKT/X.224确认25/21ms且selected HYBRID=2。原PCAP仅/root/nbh-lan-p1-reproof-0c0485ae，未导出；11保护SHA和agent PID9497一致。旧boot证明不延期、不复用。
- 2026-11-16继续：保留父目标（两用途安全交付→SSH限权→中央单轮→通过后timer），先核查实际现场与交付工具，不重放已成功读取或路径取证。
- 上一阶段真实消费已发生：wuhan-snapshot与lan-51160各fetch一次且revoke成功，EID分别95deb1bc-ef37-42e9-ae29-c805eb5eea0b、be1d4694-7458-4216-8cc4-d4c7527c45e9；未完成接收端备份/公钥/加密credential交付。导入cryptography失败在此之前，未产生额外登录。
- 当前Eval运行时已丢失，两业务值不再可用；不通过重跑fetch重构内存。先做非秘密预检与可靠交付准备；需要补充读取时须本人明确批准两用途各一次，失败/未知仍不补跑。武汉无Python，上一备份命令未成功；旧监控、56与推广边界保持。
- 2026-11-16前置核定：武汉22实际PID5454/dropbear2024.86-r3，root公钥入口为/etc/dropbear/authorized_keys，与/root/.ssh/authorized_keys不同inode；不以未运行sshd的配置推断能力。武汉使用restrict+固定/usr/bin/ucode gate EID，来源与期限由固定gate校验；LAN使用OpenSSH restrict/from/expiry-time（UTC Z）+固定python3 -I gate，不改SSH服务。
- 非秘密交付烟测通过：两实际宿主root私有临时目录执行同一接收器发布流程，验证原字节备份/保留、metadata600、重复交付拒绝；中央host-key加密/解密同进程比对使用公开非key夹具通过，root600，临时目录已清。未将测试公钥装入实际SSH授权文件。
- 交付入口C:/Users/25321/AppData/Local/Temp/nbh-p1-reproof-xqo0ogkv/p1_deliver.py，使用既有E:/pikachu/infra/.venv/Scripts/python.exe；--preflight实际PASS、credential_reads=0，新boot两attestation仍valid、两端metadata/backup与中央credential均不存在，timer仍disabled。--apply须另批两用途各一次补充读取，checked CurrentUser独占attempt→fetch/revoke→同进程SSH stdin host-key加密→受限公钥/metadata，失败/未知不重试；不依赖跨轮Eval保存业务值。烟测证据同目录delivery-smoke.json。
- 本人2026-11-16明确选择“批准各补充读取一次”：wuhan-snapshot与lan-51160各至多一次helper读取/revoke，同进程交付gateway3加密凭据与两端受限公钥/metadata；SSH限权与中央采集通过后才启用timer。失败/未知不补跑，不重签、不动旧监控/网络/56；本条记录授权而非执行成功。
- 补充消费/交付已成功：两用途各一次fetch/revoke，无重试；各stage=DELIVERED_NOT_ACTIVATED。gateway3两credential以host key加密、root600并同进程解密比对一致；两接收端公钥/metadata按固定gate与EID发布，原授权字节备份在各/root/netbird-observer-backup/<EID>/authorized_keys.before。私钥未进入Windows文件/参数/环境/日志；checked CurrentUser尝试/收据在%LOCALAPPDATA%/infra-netbird-observer-delivery/。下一步实际非root service SSH限权，source/collector/timer尚未启用。
- 路径证明完成：source51.160端口62055/62056到.55/.56:3389，br-lan入/wt0出同seq同目的同端口，SNAT到100.125.129.101，转发2.219/2.404ms；4个纯SYN、载荷0、内核丢0，独立20秒guard正常drain、实际3114ms。原PCAP仅/root/nbh-lan-p1-20261115-a90252f1（700，文件600）。11保护SHA和agent PID未变；新boot04351e13-7c39-43eb-a20a-a453804bbb2f绑定证明，未外传PCAP。
- 失败/纠正如实保留：首次controller因Windows文本管道CRLF于5ms退出，未发GO、0目标请求，改为LF字节传输并sh-n/hash验证后才发一次两条流。测量helper错误要求响应flags=0，原始结果FAIL保留；两响应实际type2/flags0x2f/长度8/HYBRID2，现有产品rdp_confirm离线复核均PASS（33/30ms），未重发或改写原结果。
- 工具验证已完成：Windows56测试（2 native skip）+实际武汉ucode内存门禁2例通过；独立GUI打包/self-check和两真实私密空窗口通过，无生产Bao请求或新bootstrap读取。Jira恢复后NBH-19评论11249/NBH-1评论11250均201/GET200、保持处理中；附件11318共8664字节，下载SHAbfc261a7d71ffcd0b5fca0f1ca17eca003b11580e4493d87dea7a7b2dd34a2dc一致。

## [完成] NBH-19真实Linux路径证明、受控GUI与暂停组件（2026-11-15）

- 原始目标：本人分别批准最小三机P1试点及新源两次无凭据RDP/≤30秒40包纯SYN头路径取证；此节归档已完成准备，真实专用身份/受限key/中央循环仍待本人私密开通，父目标留TODO.md。
- 执行主体：现有51.160/eth0→武汉192.168.3.1→10.10.10.55/.56:3389，source端口62055/62056（均在两host默认ephemeral范围之外），未改路由/停NetBird或新建P1实例。
- 安全先验：BPF编译通过，强制初始SYN且IP长度等于IP+TCP头长，payload0；20秒独立runner guard先以sleep60/250ms烟测，实际TIMEOUT/193ms且cleanup_confirmed=true。正式每interface最多20包，总上限40，原PCAP只留root。
- 失败记录：Windows文本pipe使controller CRLF，5ms退出且未发GO/0目标请求；按LF bytes重新传输、sh-n及SHA一致后才发两条实际流。正常capture3114ms、cleanup确认，未重放目标请求。
- 实际路径：br-lan入/wt0出各两SYN，目的/源端口/seq逐条一致，SNAT192.168.51.160→100.125.129.101，转发2.219/2.404ms；总4包、TCP载荷0、内核丢0，rawPCAP与logs root600/父700。
- RDP如实解释：源实际19字节请求，均收到19字节HYBRID2确认，33/30ms。throwaway helper错误要求flags=0而返回FAIL，原结果保留；实际flags0x2f属于有效扩展，现有产品rdp_confirm离线复核两响应均PASS，0新增请求、没有改原结果或以宽松fallback掩盖故障。
- 原证据：/root/nbh-lan-p1-20261115-a90252f1（仅网关root），structured-proof.json SHA0db5ec06954c42a7167282b7bcbdb96a958261a555c727aa04d97706227e1906，包含两个rawPCAP SHA和结构化headers；没有PCAP外传。
- 新源receipt：boot04351e13-7c39-43eb-a20a-a453804bbb2f、probe_id lan-wuhan-51160、baseline1、固定eth0/source/gateway/两目标/rdp/2000ms均绑定，最多有效至2026-12-14T17:08:37Z，变更/重启不自动延长，不复用Windows旧证明。
- 三机无秘密安装：51.160固定observer源码/config/attestations（disabled）及严格gate，武汉仅新增cache gate；两实际gate缺identity都COMMAND_DENIED，无公钥/metadata追加。r17原payload和health不改，capture前后及最终11保护SHA/PID一致。
- 中央安装：gateway3非root netbird-observer UID987/GID985、新代码/private cfg/state和service/timer；真实disabled CLI与独立原生read服务exit0，固定LAN分母保留2项UNKNOWN。配置disabled、timer disabled/inactive、两加密credential absent，旧ha timer active/waiting不动。
- 修正如实记录：tar uname=root覆盖数字uid导致初次cfg600/root拒绝非root读，已只修正新cfg所有者并验证；oneshot的RuntimeMaxSec被systemd忽略，改为有效TimeoutStartSec20/FailureModekill/Stop2秒，实际show已确认。未改其它unit或压制错误。
- 两用途工具：E:/pikachu新增netbird_observer_contract/credentials/enrollment/gui及四行为测试，保留并行Sub2API registry/spec变更。Windows56项（2 native skip）通过，实际武汉ucode内存合成I/O门禁2例通过；一处Windows测试mock路径用Path对象修正，无Linux产品权限放宽。
- GUI交付：E:/pikachu/infra/deployment/dist-netbird-observer-20261115/enrollment-gui/enrollment-gui.exe，SHAd6b23274e11f7468ae9307c43d89b40243d3b78bf56a03aa2ce2fbe81c468c8c；独立打包0、self-check24用途/Tk/0问题，两实际空窗口只捕获自有PID/标题并视觉通过，未输入秘密/点击联网，测试窗口已关闭。
- 规则与权限：唯一源加入两用途固定helper/KV/role/profile、keypair/expiry/gate/host/consumer绑定和私密维护边界；原16目标先字节备份再apply/check，全ok、块外16/16保持。新OMP18.13.3原生ctx完整新规范/两role/KV及不追认边界全部true，无prompt/业务取密；临时扩展与空cwd已删。
- 权限证据：source SHA44c7dcad9e1cf7140a253b1a1a679b145a75b2ddc27e3b22dc6171e673b9aaaf；备份/manifest/distribution/ctx回执在C:/Users/25321/AppData/Local/infra-inventory/netbird-observer-policy-20261114T182132645728Z。当前旧实施会话未读新DPAPI或业务私钥，文件分发/实际加载不等于身份交付。
- 最小模板/文档：E:/pikachu/infra/openbao/policies/netbird-observer-provisioner.hcl（固定20路径/无wildcard）与两reader模板各2路径，仅可选维护模板、未在线应用；部署README/agent-policy-onboarding及本项目docs/health/observer.md同步。
- Jira：本轮恢复可用后，NBH-19评论11249/NBH-1评论11250均POST201/GET200，保持处理中；附件11318/8664字节下载SHAbfc261a7d71ffcd0b5fca0f1ca17eca003b11580e4493d87dea7a7b2dd34a2dc一致。仅结构化非秘密报告，不含PCAP/密钥/DPAPI。
- 当前阻塞：本人在两用途私密GUI输入短service issuer并Create/issue；成功后新加载且获准的消费会话一次read/revoke、交付加密credential与receiver公钥/公开metadata，实测SSH命令/PTY/forward/错ID拒绝与一次中央采集后才启用timer。没有复用普通root key常驻、Bao身份查询/维护或真实通知，56与推广不放行。
- 完整公共交付：C:/Users/25321/AppData/Local/Temp/nbh-p1-20261115-35x617k_/implementation-manifest.json、p1-implementation-report.json及测试/GUI/规则/安装回执；local://nbh-p1-51160-path-proof.json、nbh-p1-51160-attestations.json、nbh-p1-rdp-canonical-review.json、nbh-p1-central-installed-verified.json、nbh-p1-implementation-jira.json。没有commit/push/public release。

## [完成] NBH-19现有LAN来源与迁移后中央节点预检（2026-11-14）

- 原始目标：本人要求继续后续任务，先承接真实Linux LAN来源核定与受限接入准备；本节只归档只读前置/现有代码guard验证，不标P1部署或端到端验收完成。
- 来源发现：从E:/pikachu既有受管主机记录核定root@192.168.51.160（route.ai），严格known_hosts_51160_verified及现有公钥登录成功。旧Torii夹具AppRole早已过期，未调用该helper、Bao或旧profile；未读取私钥。
- 自然路径：对10.10.10.55/.56的普通route get及from192.168.51.160查询均eth0/下一跳192.168.3.1；仅local/main/default规则，不走自身wt0。此为来源资格/内核选路，不是独立包头路径证明。
- 实际能力：Linux6.12、Python3.12.11、固定/usr/sbin/ip与/usr/bin/ssh可用，主机netns与PID1相同；真实SO_BINDTODEVICE(eth0)+bind(192.168.51.160)成功，未connect业务目标、未listen或创建服务。
- 接收端：OpenSSH9.9p1、root .ssh700/authorized_keys600；只读元数据，未读authorized_keys内容。全局PTY/forward/userRC当前允许，P1必须逐key限制并在实际接收端验证，未把现有普通root登录当受限身份通过。
- 中央阻断与解除：起初对100.125.250.19用旧gateway2 pin失败。既有E:/pikachu11-09迁移记录明确该peer转移到gateway3，既有known_hosts_gateway3_migration_20261109_verified中115.159.158.245及100.125.250.19的指纹均SHA256:sxg5lGNIDwZtFGxsbz/eqpzH493b0MTkrFD4LsCAWbs，与呈现值完全一致。
- 中央预检：用该正确既有pin严格登录后hostname=gateway3、Python3.12.13、固定SSH可用，自然到来源/武汉网关走wt0/table7120、源100.125.250.19。原netbird-ha-monitor.timer仍active/waiting；新observer配置/状态目录不存在，未改信任文件、接管旧监控或新增任务。
- 发布器：武汉实际cache-only CLI返回fresh=true、node_id=wuhan-r14-trial、config8/baseline1；只读缓存、不触发检查。未配置告警的event_gap仍为true，未伪造事件/外部视角完整性；这不是新key的SSH鉴权验收。
- 配置与guard：两份实际目标配置经当前validator通过（仅格式），保持disabled/owner none；在真实来源主机内存加载现有transport/lan_probe，两目标均UNKNOWN/PATH_NOT_ATTESTED、path_verified=false。没有创建文件、attestation或目标连接，guard证明缺证明不假通过。
- 最小提案：现有51.160固定两RDP目标的按次探针，武汉固定snapshot-v1只读key，gateway3独立非root/60秒中央采集；不新建VM/容器、不改原应用/网络/agent/ACL、不开放新公网端口、不发告警或模型请求。
- 身份提案：agent-kv/data/netbird-observer/wuhan-snapshot-ssh与agent-kv/data/netbird-observer/lan-51160-ssh，各固定consumer/target/命令与最小reader；服务端存在性未查，角色/helper/交付尚未授权。需按统一GUI受控开通并由加载精确边界的消费会话承接，不借其它用途或把工作站root key复制到collector。
- 待本人选择：精确三机接入/专用身份开通；另为新源51.160批准两次RDP无凭据探测及武汉br-lan/wt0≤30秒/40包纯SYN头路径证明。原PCAP仅目标root私有，不用此前Windows证明替代，不在当前预检阶段实施。
- Jira：本轮新开NBH-19页面遇Chrome relay45秒连接超时，未执行认证/评论写入；不是未知写入，不重放历史成功mutation。已完成前置保存在账本及本地报告，Jira进度待relay恢复后同步。
- 证据：local://nbh-p1-51160-preflight.json、nbh-p1-51160-source-capabilities.json、nbh-p1-51160-receiver-preflight.json、nbh-p1-current-central-preflight.json、nbh-p1-wuhan-publisher-preflight.json、nbh-p1-51160-guard-smoke.json、nbh-p1-51160-plan.json。全部无业务秘密；当前没有生产文件、身份、调度、路由或配置写入。
- 剩余：P1目标主体已具备前置，不再以“没有现有Linux候选”阻塞；真实受限交付/路径证明/中央循环仍未完成，父任务TODO.md待具体授权，56及推广门槛不变。

## [完成] 武汉24小时取证收口：连续采集与保护层（2026-11-14）

- 原始目标：本人表示“应该够了”后，按原24小时条件核对完整样本与武汉保护基线，收口已具备证据的层级；不缩短标准，不扩大为真实LAN、agent升级或全网推广通过。
- 窗口：2026-11-13 19:06:26+08至2026-11-14 19:06:26+08，原collector elapsed86400.2358588秒，最终样本elapsed86400.0005518秒；1441样本/1441独立run，状态collection_complete。
- 覆盖：最大采样间隔60.001214秒，无>75秒空窗、读取错误、过期样本或FAIL检查；固定分母15、配置rev8/基线1、monitor未停、automatic全为false。样本时间戳第一到最后略少24小时约0.011秒，是首采相对启动的调度偏移，不冒充新增时长或缺失整轮。
- 资源与身份：health始终PID6072/start98350425，agent始终PID9497/start63787988；health RSS取样2012–2164KiB，首2116末2104。CPU ticks增量25805，不在未核实tick频率时换算CPU百分比；不宣称worker瞬时峰值或engine从未重连。
- 重要例外：结构完整1432/1441轮，9轮GENERATION_CHANGED保持UNKNOWN；样本索引3/4/158/310/620/1074/1229/1377/1378。外部collector没有保留这些轮次的原始前后边界，原因未定；不能将单一采样结构hash解释为期间没有变化或自然变化留证已通过。
- 端点：.55为1440 PASS+1 UNKNOWN/TIMEOUT，.56为1441 PASS；合计2881 PASS+1 UNKNOWN/2882次，不是业务uptime。超时发生11-14 16:02:26，16:03:26下一周期恢复；未认定网络/NetBird/应用根因，未重试探测制造PASS。
- 判定：仅24小时连续调度/缓存发布、资源取样与前后保护层PASS；功能证据部分通过并保留例外，所有run总览unknown符合未验证LAN/peer/绑定视角。没有把零FAIL说成全绿，也没有缩分母或重取一段全绿数据。
- 现场复核：严格SSH只读，82payload+10稳定保护SHA+获准rev8 health配置SHA共93项匹配；原netbird/netbird_bin导出、daemon PID与基线相同。当前fresh、无FAIL，agent0.80.0 Management/Signal Connected、Mesh100.125.129.101/16；monitor ON/automatic OFF/owner none/agent更新OFF保持。
- 操作边界：本次未改监控或业务配置、重启/重连agent、网络/ACL/计划、56封锁或生产渠道；没有模型请求、故障注入、真实通知。没有认证UI或真实LAN/升级/断电验收。
- 原始证据：samples.jsonl共6772923字节，SHA5c20c10e144114c49643e3f09ecd85ea19836a9cf26624b657964b0918b4b3ff；原status和样本未改写，REQUIRES_REVIEW保留，人工限定结论另存acceptance-review.json。
- 完整本地归档：C:/Users/25321/AppData/Local/Temp/nbh-r17-release-kq14jz3e/wuhan-observation/closeout-evidence-20261114.zip，共169883字节/SHAed49650f0587bd8aaa448b6f0abb5e69df9915a56f548038ead2eb64a557ad11；含status/samples、人工报告和保护/RPC回执。
- Jira：NBH-1评论11305、NBH-19评论11306均POST201/GET200，仍处理中；报告附件11401/14616字节，下载SHA9c06d5da641756e560db6b54f2dcdf1ab21c37cc0ef205f52d38d5eb94889d58与实际本地字节一致。
- Jira边界：首次页面导航超时但已打开，恢复该页后myself200，成功写入后关闭页面。随后可选原始ZIP上传在browser.open时遇relay扩展断开，尚未发上传请求；不重复成功mutation，不读取浏览器凭据或借其它用途认证回退。原始ZIP仅本地保留，不能声称已上传。
- 历史核对：此前900秒/16样本及17.52小时/1052样本的零FAIL只是中途汇总，不等于零UNKNOWN；本次完整独立重算明确披露9代际轮次和1超时，避免从零FAIL推导全业务健康。
- 后续：本轮取证结束不需机械延长；常驻只诊断保持原状。优先P1合格Linux来源/受限身份/新attestation；56仍需窗口和独立恢复入口，A23/真实engine/收件及推广门槛不变，父任务留TODO.md。
- 报告与收据：acceptance-review.json、jira-closeout-receipt.json；local://wuhan-observation-accepted.json、wuhan-closeout-protection.txt、wuhan-closeout-router.json、wuhan-observation-closeout-jira.json、wuhan-closeout-archive-proof.json。docs/health/baseline.md同步限定结论。

## [完成] 武汉诊断前置修复与24小时取证启动（2026-11-13）

- 原始目标：按本人要求规划并执行武汉只诊断→真实LAN探针→56受控更新→逐节点推广；本节只归档前置修复、监控配置和取证启动，24小时验收及其它生产门槛未完成，保留TODO.md父任务。
- 任务规划：四阶段及56具名窗口/独立恢复入口/私有备份/官方候选与48小时版本龄/封锁集合/120秒+5分钟+10分钟门槛/失败退出均落TODO.md。56需窗口与不依赖被更新VPN的恢复入口后再批准操作，未重试/清封锁或改原计划。
- 基线：Windows192.168.80.163、br-lan，目的10.10.10.55/.56、前缀10.10.10.0/24，表main+netbird、原生105/110、允许wt0；两个router-origin RDP3389端点。无Linux LAN探针，不假设primary/backup peer或跨视角证明。
- r16缺陷与修复：真实只读complete预演规则/forward PASS，但routes因main suppress default被误报ROUTE_SHADOWED；evaluate.uc现在按有效规则链选表判shadow/link，仍检查预期前缀。RED→32断言PASS覆盖抑制默认/未抑制WAN/更具体main三边界；全health入口及实际旧runtime evaluator通过。
- r16构建与试装：双SDK主/中文均通过；主IPK209255字节/SHA95017b41b1add889159c554a41198c3c794ceda11dc53a1d8718dee67af04ebe。原生APK升级、已装evaluator32项及uid81/root握手通过；首次原生升级遇离线world helper锁exit99，确认helper结束后再升级exit0，不把锁失败当产品通过。
- 首轮现场：武汉r15→r16 exit0、82payload/11保护SHA通过；health CAS5→6后新鲜15项，规则/路由/from+iif PASS，但.56 RDP_CONFIRM_INVALID。未直接当业务断联或触发恢复。
- r17根因：有界原生socket诊断发送20字节而TPKT声明19字节，旧ucode将\\xe0展开为c3a0，目标reset。CAS6→7暂停health，仅停止诊断服务、agent PID9497不变；24小时尚未计时。
- r17修复：probe.uc请求opcode用chr(224)生成原始字节；tests/health/probe.uc从实际loopback接收端检查19字节/TPKT/X224，真旧runtime RED→21断言PASS。有效响应测试使用原始字节而非Unicode转码文本，未以source-text或mock echo当证明。
- r17验证：全health入口exit0；已打包probe在25.12和实际武汉旧runtime各21断言PASS。武汉有界主动无凭据诊断由发送20/被reset变为发送19/收到19字节HYBRID确认32ms，不涉及TLS、账号或桌面登录。
- r17构建：两委派provider503在首工具前失败，未产生构建；父会话接续自有SDK克隆并行执行nobody clean/compile，双SDK各exit0。主IPK209268字节/SHAe65a27f71938810d9a72f5d0ba4c72b32f3c3bacae8df85be1a162b00487fc80；输入SHA0db5702cd956c4d97b4d2a96e9af9efdb4dc204d9d27ff853aef22488db723da。APK实际公钥验签UNTRUSTED/exit1。
- 回退与保护：目标私有/root/netbird-monitor-20261113-988c3c0f（700）保留初始health配置、rev7暂停配置、获准rev8配置SHA、r15/r16回退包及10项不应变化保护SHA；旧全量身份备份仍在r15目录，不导出或复制身份。
- 当前现场：武汉主包r17，82非配置payload匹配；10保护SHA/agent PID9497及netbird/netbird_bin原UCI不变，Management/Signal Connected、agent0.80.0。health CAS7→8/基线1、60秒/eventwatch，仅独立配置获准变化；automatic OFF/owner none/agent更新OFF。
- 首轮结果：fresh=true，15项中9 PASS/0 FAIL/6 UNKNOWN；两路径规则、路由、forward与两个RDP endpoint PASS，peer及path-router/LAN未绑定视角保留UNKNOWN，总览unknown而非全绿。未创建认证LuCI会话或宣称UI验证。
- 持续取证：本机服务wuhan-diag-24h-20261113，PID27340、mode=persist，2026-11-13 19:06:26+08启动、预计2026-11-14 19:06:26+08截止；每60秒仅SSH读缓存/固定进程资源/结构摘要，25秒调用界限、24小时单调截止、100MiB证据上限，无配置/探测/恢复动作。
- 已观察：900秒/16样本/16个独立run，读取错误/过期/失败样本均0，health RSS取样2084–2116KiB；不是全天或峰值资源结论。需要本机保持运行联网，空窗不得补造；到期仍需审阅完整证据和保护基线，未提前标PASS。
- Jira：NBH-1评论11303、NBH-19评论11304均POST201/GET200，均处理中；附件11400（2556字节）下载SHA8fde6f9af8907e34b95e38228afbce10ca1fa8e53b92565479ce268c9fff61bb一致。说明四阶段、真实缺陷/修复及24小时仅启动，未关闭未测事项。
- 清理：两自有native容器按ID核验删除，SDK克隆删除exit0，保留原SDK/版本化产物与回退；持久取证服务明确保留，Jira页关闭。最后一个猜测UCI键读取exit1不作状态结论，权威get_agent_update_status实际enabled=false/idle已读取。
- 交付：C:/Users/25321/AppData/Local/Temp/nbh-r17-release-kq14jz3e含四包、输入、manifest、原生/旧runtime/现场/Jira证据与observe_wuhan.py；wuhan-observation/status.json和samples.jsonl持续保存。没有commit/push/tag/公开发布。
- 证据：local://wuhan-monitor-preview.json、wuhan-monitor-preview-r16.json、nbh-r17-probe-red.txt、nbh-r17-old-probe-green.txt、nbh-r17-health-green.txt、nbh-r17-packaged-probe.txt、nbh-r17-packaged-old-probe.txt、wuhan-monitor-r17-save.json、wuhan-monitor-r17-first.json、wuhan-observation-initial-progress.json、wuhan-diagnostic-plan-jira.json、wuhan-diagnostic-jira-attachment-proof.json、nbh-r17-cleanup.txt。
- 剩余：24小时到期审阅；P1合格Linux来源/受限身份/新attestation；56窗口和独立恢复入口；A23/真实engine/收件及逐节点推广均未执行。父任务继续TODO.md，不把启动和首轮正常当整体交付完成。

## [完成] 更新器r15候选构建与武汉LAN单节点插件验收（2026-11-13）

- 原始目标：本人选择“先验收更新器修复”，先独立候选/旧runtime/原生包验收，再仅武汉LAN插件试装；56不重试、不解除封锁，P1不取消，不触发agent升级/重连、自动恢复、告警或网络变更。
- 版本与输入：Makefile release15；复用scripts/package-input.py显式755目录/LF输入，SHA5e16707e407ff0b035aea73bfc7c01ca7512cd082d450a16a16438752f8c29f6。保留r14原件，不commit/push/tag/公开发布。双SDK各复制到独立自有目录、nobody构建exit0，无修改保留SDK或并行服务。
- 四包：主IPK209164字节/SHA1fbc1b387757a258366be1af03c26efaf68ca19559ad648212296f01e599f222；中文IPK12817字节/SHA3af83f5c4abffee6c16c9c9f75c369c04ab493b80a7abe982808df22eb356eb3；主APK210566字节/SHA2d436532c23aea0b0f8ad4847158ba72e491b2b5277aa4754aaf3f80a4ee57da；中文APK12696字节/SHA90f01f30b44ec557652b17cbf85534021c5c9ad2904362c2a5e8903bb4119861。IPK22目录755、shebang LF，实际updater payload等于源；APK目录模式亦通过。
- 旧runtime：仅从武汉复制ucode/fs/uci/ubus/uloop/socket及必要非秘密动态库，runtime归档SHA39477e65d5463defc989c92917f84e18917acab70e6647bcb6c368915ab138cf；network-none/cap-drop/init-reaper自有容器完整更新矩阵exit0。没有导出身份配置，也没有把编译成功当旧平台通过。
- 原生包：独立25.12 procd/rpcd/apk，匹配依赖仅fixture内无脚本预装、不加载宿主内核模块；实际r14→r15→r14→r15均exit0，3个UCI及custom init SHA保持、init调用0、RPC可用/automatic OFF，已装updater匹配IPK。uid81首次因镜像/tmp755不可写失败，改自有1777父目录后非root ubusd/rootclient握手exit0。
- 负面边界：APK实际公钥验签仍UNTRUSTED/exit1。原生卸载exit0，自定义netbird/init仍保留，两个未改默认conffile netbird_bin/netbird_health被包管理器清理；因此卸载后盲目四文件hash检查exit1，不宣称全保留或改包管理器掩盖。首次候选上传后错误cmp到已耗尽stdin导致exit1，随后独立PID/11SHA检查通过才执行安装；没有重复生产安装。
- 武汉前置：严格已信任LAN SSH、回程br-lan；network.netbird无旧迁移段；确认r14回退SHA4e7e241cfb2e32b66f6c2a8152a72437b940c261f407fa4cd4460b0a630f3b81。私有/root/netbird-r15-trial-20261113-3b1f6ce3（700），before.tar.gz（600、15579284字节）tar可读，11保护SHA、原UCI、daemon基线及r14回退包均留目标，不外传身份。
- 武汉安装：仅已有主包opkg r14→r15 exit0，未新增原不存在的语言包。已停用health注册删除提示Not found符合原OFF状态；真实RPC get_status/get_agent_update_status/get_summary/get_automatic可用，无导入失败。实际82非配置常驻payload全匹配IPK。
- 生产保护：11SHA全部OK（binary/custom init/root watchdog/netbird/netbird_bin/health/network/firewall/resolver/两个身份JSON）；PID9497相同、两原UCI逐字相等；daemon0.80.0 Management/Signal Connected、Mesh100.125.129.101/16，LAN回程br-lan。monitor OFF/rev5、旧缓存stale/CONFIG_CHANGED、automatic OFF/owner none、agent更新关闭保持。
- 业务：Windows192.168.80.163源端口63005/63006到10.10.10.55/.56:3389，TCP及19字节RDP HYBRID=2协商62/36ms通过，无凭据或桌面登录；本轮无抓包、不新增初次路径实证。认证后LuCI UI、真实agent升级及持续巡检启用均NOT_RUN，不能据此放行56或全网推广。
- Jira：NBH-1评论11302，标记NBH-WUHAN-R15-20261113-ACCEPT-01，POST201/GET200确认，仍处理中；NBH-19/关联现场验收状态不改，56回滚唯一根因仍缺失败采样。
- 交付：C:/Users/25321/AppData/Local/Temp/nbh-r15-release-i0z017gl，四包/package-input.tar/manifest及构建、旧runtime、native生命周期、安装/RPC/82payload/保护/业务收据；docs/health/baseline.md与CHANGELOG.md同步。
- 清理：两自有容器按ID核验删除、两SDK克隆删除exit0；保留原SDK/构建输出/本地交付/目标私有回退，不触碰并行服务。Jira浏览器关闭，未新建LuCI会话。
- 证据：local://nbh-r15-oldruntime.txt、nbh-r15-native-lifecycle.json、nbh-r15-wuhan-backup.json、nbh-r15-wuhan-install.json、nbh-r15-wuhan-post.json、nbh-r15-wuhan-integrity.json、nbh-r15-wuhan-rpc.json、nbh-r15-wuhan-rdp.json、nbh-r15-jira-final.json、nbh-r15-cleanup.txt。本支线无剩余操作，P1与推广父门槛继续TODO.md。

## [完成] 56启动DNS误判隔离修复与NBH-19前置核对（2026-11-13）

- 原始目标：按本人批准顺序处理56回滚，再推进NBH-19及关联验收；生产重试/封锁清除/计划/ACL/agent/真实通知均不操作。
- 现场证据：56现役agent_runtime.uc/agent_update.uc与源相同判定链；0.82.1于03:02:06.894启动、03:02:06.994 shutdown，0.82.0于03:02:09.953启动。基线connected=true、DisableDNS=true、5个DNS服务器；事务只保存通用failure，无失败采样。日志脱敏后仅保留相关生命周期，原始内容未落盘或上传Jira。
- 修复：agent_update.uc的invariants_changed将动态DNS发现与持久DNS/resolver分开；连接前允许动态列表未完成发现，固定设置仍立即拒绝变化；控制面连接后仍要求完整DNS/身份基线及5分钟连续健康。没有放宽120秒/10分钟边界、进程稳定、探针、失败封锁和真实回滚条件。
- 回归：scripts/test-agent-update.sh新增启动收敛/超时、启动期DisableDNS/resolver变化与连接后DNS变化；原生OpenWrt隔离RED exit254→GREEN exit0，完整安装、12种失败、空间/stop拒绝、调度、SIGKILL、early boot、孤儿写入及迟到恢复矩阵通过。CHANGELOG.md与docs/health/baseline.md已同步。
- 运行烟测：自有network-none/cap-drop容器另启动真实未注册NetBird0.77.0，仅回环management；实际status返回management/signal=false、DNS0、Mesh为空。证明启动状态形态，不作为0.82.1或真实VPN验收。现场回滚受此缺陷影响仍为推断，不能唯一归因；修复仅本地源，未commit/push/打包/部署。
- NBH-19：scout只读核对部署契约/CLI/身份/attestation；没有已交付合格Linux LAN源/受限身份，Windows不受现有实现支持，已知Linux候选自然走自身wt0。不能凭已有Windows两RDP证据签发Linuxattestation。开发宿主临时私有目录实际central once/read均exit0、disabled/owner none、LAN NOT_CONFIGURED、投递0；未生产轮询或发消息。
- Jira：标记NBH-FOLLOWUP-20261113-STARTUP-DNS-01与NBH-FOLLOWUP-20261113-P1-PREFLIGHT-01；NBH-1评论11300、NBH-19评论11301均201并独立GET200确认，状态不改。NBH-4/6/7/9/10的负向ACL、engine、LAN及收件现场条件保留。
- 清理：自有容器5f5d9c99a2c8996635230195a4f850c9ea912569ffb3a1cd49694f4517064939按ID核验后删除；自有observer临时目录删除exit0，Jira页关闭；未操作并行开发宿主既有容器。默认SSH信任缺条目后改用既有torii-test-known_hosts严格验证，不新增或绕过主机键。
- 证据：local://node56-rollback-log-redacted.txt、node56-rollback-baseline-summary.txt、node56-startup-red.txt、node56-startup-green.txt、nbh-observer-preflight-20261113.json、nbh-followup-jira-20261113.json、nbh-followup-cleanup-20261113.txt。
- 剩余交付：生产候选验收与推广未通过；NBH-19需合格来源/受限身份/现场基线与新路径证明，A23/真实收件另按范围授权；父任务保留TODO.md，不把本次源码修复或disabled烟测当P1完成。

## [完成] 武汉运行复核、56回滚发现与Jira优先级判断（2026-11-13）

- 原始目标：检查武汉netbird-luci运行；正常则判断继续推广或推进Jira其它任务。范围为严格主机键SSH只读/RPC、已有两RDP无凭据检查、Jira只读；没有配置/部署/重启/升级/抓包/真实通知/Jira写入。
- 武汉当前：设备uptime约11天7小时、插件0.2.0-r14、daemon/CLI0.80.0、Management/Signal Connected、Relay2/2、DNS5/5、Mesh100.125.129.101/16、25/34 peers；原连接watchdog与agent更新monitor进程存在，健康巡检服务无注册符合关闭状态。
- 巡检边界：monitor=false/rev5、paths/endpoints空、baseline_revision=0、automatic=false、notification owner=none；get_summary/get_checks均正常响应但fresh=false/CONFIG_CHANGED，旧run仍473698190/rev4。只能确认RPC可用/关闭态正常，不能声称持续巡检或全部健康；日志环形缓冲中匹配巡检/updater异常的行计数0不等于历史无故障。
- 网络实测：规则105/110存在，两RDP目的的from192.168.80.163+iif br-lan查询均wt0/table netbird；本机192.168.80.163源端口56790/56792到10.10.10.55/.56:3389分别33/58ms完成TCP及19字节RDP HYBRID=2协商，未登录桌面。本轮未抓包，不把查询或源绑定当新的独立路径实证。
- 运行连续性限制：武汉PID9497，不同于11-08的12682；boot_id仍ae133e50-515f-4359-8ac9-e922882fac93。只证明当前正常，daemon重启原因未定。LuCI实际导航到登录页，无既有认证，不读取密码或创建会话，本轮未验证登录后UI。
- 56新阻断：实际事务989abd9b-151e-4413-ba22-c43d7370db09，0.82.0→0.82.1，2026-11-13 03:02:00开始、03:02:40更新为rolled_back，0.82.1在blocked_versions。journal只有健康窗口失败或取消通用failure，没有逐样本失败字段/调度来源；cancel_requested=false不能单独确定根因。当前0.82.0、Management/Signal Connected，wt0原HTTP探针200，回滚状态称旧版本健康已验证；本轮未重放更新或解除封锁。
- Jira实时：myself/search均HTTP200，共24项、17完成、7处理中；NBH-1/4/6/7/9/10/19。已读取需求与最近评论，无新增开发缺项结论；主要仍缺真实P1集成、A23负向安全、A03真实engine和真实收件闭环。
- 决策：保持推广暂停；先核清56这次失败的可用日志证据，不靠恢复联网放行。Jira下一项优先NBH-19（受管合格Linux LAN来源+受限身份+中央采集），带动NBH-6/9/10；NBH-4/7按各自安全/维护验收条件推进。武汉持续巡检若要启用，应先批准路径基线与仅诊断运行范围，不启用自动恢复/告警。
- 证据：local://nbh-jira-20261113.json、local://nbh-wuhan-rdp-20261113.json、local://nbh-node56-rollback-20261113.txt及本会话原生SSH/RPC输出。八个保护文件本轮SHA已采集，但未与旧基线逐项比对，未声称保护哈希跨日不变。
- 收尾：两浏览器页已关闭；本次检查/决策完成，后续回滚排障、持续巡检启用及P1生产验收仍保留TODO.md父任务，不因调查完成关闭业务交付。

## [完成] Windows真实LAN路径实证与本轮Jira收口（2026-11-08）

- 原始目标：推进剩余验收/Jira；本人随后明确批准仅两条指定RDP流的≤30秒/40包无载荷SYN采样，并选择先完成Windows路径验收，Linux产品探针继续待交付。
- 56当前验证：302917ms/31健康样本、11/11 wt0 HTTP200，PID27245稳定且public key/Mesh/management/DNS逐样本与已提交事务基线一致；真实LuCI daemon/CLI0.82.0、连接正常、浏览器错误0。3个运行更新库与验证r7包SHA一致；历史触发/原始重连回执不足，推广门槛未关闭。
- Jira四项P0收口：逐条需求及验收矩阵核对后，NBH-2/3/5/8说明/评论/Done41成功且GET完成，评论11236–11239；真实拓扑NOT_RUN层未提升为PASS。其余NBH-1/4/6/7/9/10转处理中，NBH-19保留处理中，评论11240–11246。
- 首轮证据：Epic附件11316/5767字节，下载SHA384813d3d13e0e5a7997c202a770789da7e3dd589af8de5a7e9eb885286043dc一致；无伪造Bitbucket关联，无已成功mutation重放。
- Windows实测：源192.168.80.163/物理接口14，目标10.10.10.55/.56:3389；采样轮源端口59465/59466，TCP及19字节RDP HYBRID=2协商通过（32ms/34ms），未发送凭据/未登录桌面。
- 初次路径实证：br-lan各1个SYN与wt0各1个SYN的源端口/目的/TCP seq一致；源NAT192.168.80.163→100.125.129.101，转发时间差1.848ms/2.940ms。26秒共4包，所有TCP载荷0、两接口内核丢0，两个tcpdump与独立guard均exit0。
- 原始证据只在目标root私有/root/nbh-lan-acceptance-20261108-c306b123，目录700/PCAP600；lan SHAa8f93a0dadd41a87b1e72c39428e03ecbfb9b4ee4b4bf147d62cbefa3c498d0b，mesh SHA479dd356d9a4e5d5f4e8e089b2dcb2110e2c17515ba73571d4a58303a3ea11a9。仅导出结构化包头/哈希，未上传或复制PCAP。
- 保护：8保护文件SHA全部OK、武汉PID12682不变、management/signal正常；r14/monitor OFF/rev5/automatic OFF/owner none保持。没有路由/ACL/计划改变、agent重启/重连、故障注入或真实消息。
- Jira路径补证：NBH-19附件11317/3591字节，下载SHA697236441e5b4f82a47b315f066d0e9a3a5f036aecbe057aab0762a1d8c31cca一致；NBH-19/1说明PUT204、评论11247/11248 HTTP201、GET处理中确认。最终24项：17完成，7处理中。
- 边界：此PASS仅对应本轮Windows来源两条RDP正向与初次路径；没有生成或续期Linux产品attestation。Linux候选192.168.58.34/.110自然路由均走自身wt0，不冒充LAN执行器；按本人选择继续欠验收。其它方向、A23负向ACL、真实收件和56历史门槛保留TODO.md。
- 收尾：临时只读LuCI session已撤销、隔离页和Jira页已关闭；56五分钟观察临时文件与本地采样控制脚本清除，目标私有包头证据保留。未执行代码修改、提交、发布或其它节点部署。
- 原始非秘密结果：local://nbh-node56-observation-summary.json、nbh-node56-ui.json、nbh-real-lan-rdp.json、nbh-remaining-acceptance-report.json、nbh-jira-mutation-receipts.json、nbh-syn-path-report.json、nbh-syn-capture-receipt.json、nbh-syn-post-state.json、nbh-path-jira-final.json；长期可核对Jira附件11316/11317与各评论。

## [完成] 武汉LAN单节点兼容性修复与r14试装（2026-11-07）

- 原始目标：按本人要求，先在本机可经本地网络访问的设备（武汉网关）测试新包，确保NetBird异常时仍能连接修复。
- 授权边界：仅武汉网关r9插件单节点试装与非破坏性巡检验收；本次单节点试装为原推广暂停门禁的明确有限例外，不放行其他节点、agent升级、自动恢复、重启/重连、故障注入或真实告警。
- 验收1：实际证明本机到武汉LAN管理地址的通道不经NetBird，严格主机密钥验证成功；准备目标机私有配置/身份备份与匹配r7回退包。
- 验收2：从r9失败开始修复并构建新候选；最终r14主包/已有语言包边界及目标依赖核实，实际LuCI/RPC/后台巡检通过；agent进程/身份/DNS/自定义init/网络配置保持，自动恢复及更新开关不变。
- 验收3：记录真实观察、失败及回退证据，LAN探针未配置仍UNKNOWN；不把此次试装当NBH-19真实LAN/ACL完成。
- 当前状态：本轮兼容性修复及武汉单节点试装完成，现安装0.2.0-r14。新巡检短时启用并验证后恢复OFF，owner=none、自动恢复OFF；不放行其他节点或关闭NBH-19真实LAN/ACL验收。
- LAN通道已验证：本机192.168.80.163经“以太网2”直连192.168.0.0/16，SSH严格既有known_hosts成功；武汉回程192.168.80.163 dev br-lan，不依赖wt0。现场iStoreOS24.10.8/r7/daemon PID12682、management/signal=true，Mesh100.125.129.101/16，无待提交UCI。
- 依赖子项：ucode-mod-socket缺失且原生import失败；已刷新现有签名验证全部通过的软件源，后续仅安装匹配依赖、不升级ucode或系统。GitHub公开API限流403，已定位既有本地r7回退包，不重复调用API。
- r9主包试装opkg exit0，但实际出现Agent updater: Module does not export mkdtemp；源runner.uc静态import fs.mkdtemp不受现场ucode支持，健康巡检RPC未注册。此为功能验收失败，不能以opkg成功判通过；不启用巡检或自动恢复，先回退r7。
- 安装后安全检查：PID12682/start_ticks3112未变，management/signal=true、Mesh100.125.129.101/16；8个既有保护路径SHA全部OK（binary/init/root watchdog/netbird与netbird_bin/network/firewall/resolver）。新socket模块来自现有签名源且import成功，未升级ucode或系统。
- 目标私有恢复目录/root/netbird-r9-trial-20261107（700），before.tar.gz（600）已验证tar可读；r7/r9包与已交付SHA一致并落目标。r7回退SHA3edaa759b2f446523cb797d33ac15fe6e20a9b003104a3717941c2512575bfd2；r9为67f676121c252b0bff12968830fb5fcff56bd13ef4c4b672eb90844b4c0dca26。未安装原先不存在的语言包。
- 实际回退：opkg --force-downgrade安装已验证r7 exit0；原生get_status返回ok=true，luci.netbird对象存在，健康服务无注册残留。r7的30个常驻payload文件全部匹配；另3个uci-defaults安装后自动删除，首轮33项校验因此exit1，不作为payload损坏，也不伪造全部33项通过。
- 回退后保护：8路径SHA全部OK，netbird/netbird_bin的uci export逐字cmp=0，default.json和active_profile.json与目标私有备份cmp=0；PID12682/start_ticks3112未变，management/signal=true、Mesh地址不变，LAN回程仍br-lan。新加socket依赖在确认仅自身可删除后移除，未升级其他包。
- UI边界：实际浏览器可达武汉LuCI登录页，但无既有登录会话，未读取/索取密码；没有宣称r9页面或后台巡检通过。仅原生r7 RPC与联网状态验证通过，无agent重启、重连、恢复动作或真实通知。
- 回退警告如实保留：opkg称旧netbird/netbird_bin conffile保留并写-opkg候选；缺省netbird_health文件在降级时给missing conffile警告，命令仍exit0。不删除/覆盖既有用户配置；最终原UCI字节比对通过。
- 原始证据：local://wuhan-r9-install-result.json、wuhan-r9-postinstall.json、wuhan-r9-rollback-result.json、wuhan-r9-rollback-check.json、wuhan-r9-final-runtime.json；目标root私有备份保留待后续复测，不导出身份材料。其他节点未操作，NBH-19未关闭。
- 本人继续授权：修复旧ucode兼容性，复用既有隔离验证与SDK构建新候选包，再沿LAN通道在武汉单节点复测；保留原agent/网络/恢复/告警边界。先修runner临时目录原语，检查其他实际不兼容项，不升级系统规避。
- 实现进展：runner改用有界读取内核随机UUID及mkdir0700独占认领，拒绝既有路径；未改独立截止/进程组drain/孤儿清理。永久回归覆盖命令目录私有及执行后删除；测试夹具不再依赖fs.mkdtemp，版本提升r10，不覆盖冻结r9。
- 原生证据：实际武汉ucode/原生模块与所需非秘密动态库复制进自有network-none/cap-drop/init-reaper容器；旧runtime无mkdtemp但23项runner通过，25.12同23项与完整health入口exit0。旧runtime真实health API import及get_summary返回正常NO_RESULT。初版夹具无init reaper且假设stat命令导致烟测失败，已记录修正，不冒充产品回归通过。
- r10失败记录：主IPK208985字节/SHA6c05c9df5497618049f5df41e47cb6d0aea32b5b6d7df3ec84cb4167c6cf752f；opkg exit0但init/uci-defaults CRLF执行报错，不能交付。原因在本轮暂存器仅按扩展名归一化，不是业务源修复失效；冻结r9及r10原件不覆盖。
- r10安全回退：opkg r10→r7 exit0，8保护SHA全部OK、PID12682不变、management/signal=true。/root/netbird-r10-trial-20261107私有备份与r7包保留。后续包须先检查真实payload中shebang无CRLF并在自有隔离原生apk/procd/rpcd运行，不把构建成功当安装成功。
- r11权限缺陷：私有暂存器未写目录条目，umask077使SDK源目录700并进入包；现场ubusd仍在但uid81读/etc/passwd被/etc700阻止，strace仅记录连接/文件元数据，不采集业务载荷。按验证r7目录755恢复20个受影响路径后ubus立即恢复，启动原rpcd，未重启网关或agent；新scripts/package-input.py显式755目录/644文件/755 shebang及全量文本LF，已用真实包元数据和非root uid81 ubusd烟测证明修正。
- r12包安装与真实LuCI/后台已跑通：新schema1/唯一node wuhan-r12-trial/rev1产生；但collection为GENERATION_UNAVAILABLE，进一步只读定位rules CAPABILITY_MISSING及firewall PARSE_ERROR。自动恢复始终OFF、owner=none、无目标探测和真实消息；测试后独立巡检暂时关闭。
- r13修复：原生ip6表家族不再被纯字母正则误拒绝（使用正式family枚举）；实际iproute2 JSON suppress_prefixlen归一到既有suppress_prefixlength，冲突双拼写拒绝，不丢选择器。新增回归已分别RED复现，再GREEN：parser35/collector19，完整health入口exit0；未以Connected或UNKNOWN伪造业务正常。
- UI验证：短期只读session进入隔离浏览器，不读取浏览器凭据或修改rpcd账号；首轮夹具缺基础uci读权限有Access denied，最终补齐仅luci配置读取后，r14页面新鲜证据/未验证LAN/OFF恢复均实见、浏览器errors为空；临时session撤销且页关闭。
- 最终wire修复：旧iproute2的not:null按presence-only true保留反选，错误字符串/其他null字段仍拒绝；r14新增回归先RED后GREEN，parser36、collector19、runner23及完整health入口exit0，实际旧runtime解析武汉5条规则成功。
- 构建：r14双官方SDK均exit0；实际APK主/中文升级、procd/RPC与唯一节点新run发布exit0；uid81 ubusd/rootclient连接通过，82个已安装常驻文件与IPK字节全匹配，22个包目录755及shebang LF通过。
- 武汉实际采集：complete=true、reason=null，agent/rules/routes/links/firewall全ok；新node wuhan-r14-trial/rev4/schema1真实发布。无批准业务/LAN路径，总览UNKNOWN，不以Connected或本机PASS冒充端到端。
- 浏览器关闭后后台run由473638182推进473698190，验证独立调度；试跑后monitor OFF/rev5，原生health服务注册已观察清空，automatic OFF，owner=none且无真实投递。
- 生产保护：8保护SHA全部OK，netbird/netbird_bin导出cmp=0，default/active_profile JSON均与目标私有备份cmp=0；PID12682/start_ticks3112及management/signal/Mesh地址保持，LAN回程br-lan；watchdog/updater监护运行，原agent更新配置未变。
- 主IPK：208986字节，SHA256 4e7e241cfb2e32b66f6c2a8152a72437b940c261f407fa4cd4460b0a630f3b81；仅安装原有主包，未新增现场语言包。APK仍UNTRUSTED，未公开发布/commit/push。
- 本地交付：C:/Users/25321/AppData/Local/Temp/nbh-r14-release-zp6pz76c，四包/manifest/归一化package-input.tar及原始验证JSON；输入SHA在manifest，旧r9/r10/r11等原件未覆盖。
- 回退：目标/root/netbird-r12-trial-20261107保留已验证r7及r14包；配置/身份私有备份/root/netbird-r11-trial-20261107/before.tar.gz（600）。未导出秘密或复制身份。
- 清理：三个随机命名自有容器核验ID/镜像后停止删除，私有hoststage/throwaway脚本/生成pyc清除；保留正式SDK缓存、源feed和生产私有备份，未动共享夹具或其它节点。
- 证据：docs/health/baseline.md；local://nbh-r14-health-suite.json、nbh-r14-old-wire.json、nbh-r14-package-smoke.json、nbh-r14-install.json、nbh-r14-wuhan-collection.json、nbh-r14-ui-summary.json、nbh-r14-browser-closed.json、nbh-r14-final-state.json、nbh-r14-identity-check.json、nbh-r14-final-drain.json。
- 剩余边界：本任务无剩余修复/试装项；NBH-19真实LAN/receiver ACL、其他节点推广、物理故障与APK信任等原任务继续保留TODO.md，不因本次完成而转Done。

## [完成] Jira未关闭事项与r9测试部署准入核对（2026-11-07）

- 原始目标：核对Jira仍开启的任务，判断需继续完成还是可部署新包测试；仅只读调查，不部署或修改Jira/生产配置。
- 实时证据：认证myself HTTP200；NBH全量搜索HTTP200共24项，13项完成、11项未关闭；未关闭为NBH-1 Epic、NBH-2至10九个需求Story（Backlog）及NBH-19（处理中）。
- 需求对应：Story关联的T01–T08均完成；NBH-6/7/9/10另关联未完成T09。Story仍保留建档时“尚未实现”描述，不能据此当作九项新开发，也不能只因关联任务完成自动关闭其全部验收。
- NBH-19最新评论11223 HTTP200核实：本地8c91eb0/Linux48项与隔离路径已交付；真实武汉LAN到两台RDP/其他方向、receiver ACL/A23及真实收件仍NOT_RUN，继续保留未完成。
- 部署判断：r9可进入隔离测试机的候选包测试，不必等P1实网验收全部完成；docs/health/release-r9.md记录双SDK成功及25.12实际APK生命周期，24.10 IPK实际安装仍NOT_RUN、APK签名UNTRUSTED。现网56及后续推广原门禁不变，本次没有核验56实际定时升级及业务通过。
- 建议下一步：先在非生产24.10测试机补r9 IPK安装/升级与真实LuCI验收，自动恢复关闭、无真实告警；现网单节点试装须明确目标、独立恢复通道和验收范围，先满足或由本人明确调整既有门禁。NBH-19真实环境验收独立推进，Story按证据逐项收口，不为清看板而改Done。
- 原始只读需求与关联快照：local://nbh-jira-open-readiness.json；本次未重跑已成功构建/验收，不代表重新核验包文件或现网健康。查询页已关闭，无剩余调查阻塞；部署和真实验收仍待后续任务。

## [完成] NBH-24/E05隔离重启矩阵与r9本地交付（2026-11-07）

- 原始目标1：保留冻结A01–A24，归并A25–A31并新增A32；逐项记录boot/PID/engine/规则事件/前后快照/采集空窗，不把P1未测当P0通过。
- 原始目标2：隔离复现整机、仅网络、agent重启、运行中删原生规则、Connected早于结构恢复和多个恢复器；因果已证实/同窗/未知分开，source bind不替代真实LAN路径。
- 原始目标3：本地commit/version bump、新主/中文IPK/APK、明确范围bundle/hash及实际恢复验证；不覆盖冻结r8、不push/远程CI/发布/生产故障。
- 代码：7414037bea0c04d7722574200857e422497aa2d6，8文件；Makefile release9，新增两个永久原生回归入口及network-recovery.uc，更新验收/基线/交付/changelog。用户README和账本未入提交。
- A32整机：无NIC独立OpenWrt25.12.2/QEMU TCG，真实boot ffd92b9e-c966-4c9c-8eb3-ea0f184e4bd4→f448ac36-aacd-4b0c-a18e-e2d70635bc2d；临时105/110/12100消失，153秒空窗且跨boot单调时长null，before/after永久入口exit0。
- 仅网络：原生netifd restart同窗丢临时规则，boot/fixture PID2770不变；原生事件不识别具体deleter，产品保持cause_undetermined。
- 真实agent：仅复用开发宿主公开static NetBird0.77.0二进制，不读宿主身份；guest未注册、loopback-only management，实际PID2960/start128469→3062/start128837，同boot且management/signal=false，rules/routes相等。异步stop观察修正后完整入口exit0，engine UNKNOWN。
- 删规则/Connected：控制器明确删105/110而boot/PID3245不变，实际from+iif forward FAIL；先恢复query rule仍FAIL，补route后PASS但总体UNKNOWN，绝不声明真实LAN恢复。
- 多恢复器：复用当前原生manual/watchdog/settings/updater一次down/up、一次charge、立即重试零effects，以及E04 guards/one-shot证据；未重复生产操作。
- SDK：24.10.5/25.12.2固定feeds，以nobody及私有ncurses实际build exit0，四个主/中文新r9包；宿主不装包，SDK私钥不读/不交付，APK实际验签UNTRUSTED且未换key。
- 包生命周期：25.12原生主/中文注册安装、r9→r8回退、r8→r9升级、卸载exit0；43个health文件owned/source-equal，health revision1/owner none与automatic OFF保持，实际12100与custom init保护成立。
- 保留负面证据：最小旧netbird配置首次补默认项使原七文件hash一项不同，但既有service_enabled/desired_connected仍0；之后七文件byte-hash保持。旧fixture cache不是新包run，错误getter envelope检查不曾写配置。
- 新包实际发布：退休旧cache后r9 supervisor新生成node=e05-packaged-smoke/schema1/overall UNKNOWN，当前严格AJV valid=true/errors=null；手动bootstrap rpcd原生HUP与离线world helper联网未验边界已写文档。
- 恢复：bundle范围953e4b2e760fe436b80330f600dd29a9e3bfc8d9..7414037bea0c04d7722574200857e422497aa2d6，288423字节，SHA256 e10dd06af2810acbeaf8b53dffee648657aebc4bcca2aec497f05b7f27b4a626；verify与新repo实际base+bundle fetch/checkout通过，恢复package输入SHA与实际SDK输入一致。
- 本地交付：C:/Users/25321/AppData/Local/Temp/nbh-e05-release-8fpugk5b.zip，1236894字节，SHA256 6610b5796c04e7944c4eaff817777c519dfa755af3fb81bf08e6993723b4b261；含四新包/四r8回退包/bundle/文档/脱敏证据，CRC与manifest全部hash通过，r8原件未改。
- Jira：报告11314与实际ZIP11315均HTTP200，评论11234 HTTP201，transition41 HTTP204，GET完成10001；随后从Jira实际下载ZIP确认同大小/同SHA，不得重发任何成功mutation。
- 清理：真实离线agent退出已观察；3个精确ID核验的自有容器停/删，guest关机后含生成身份的raw盘已删，临时Git恢复repo已清。私有profile与全部agent/CLI日志从未导出，共享T07和生产未动。
- 证据：local://nbh-e05-evidence.txt、native-progress.json、kernel-evidence.json、offline-agent-final-evidence.json、packaged-native-run.json、delivery-receipt.json、jira-receipt.json、remote-delivery-check.json；docs/health/release-r9.md与acceptance.md记录分层边界。
- 剩余边界：24.10 IPK runtime、物理断电、真实connected engine/LAN/receiver ACL/生产通知接收NOT_RUN；T09仍处理中，node56/DC与APK trust门禁不变，无Bitbucket匹配关联或虚假远程commit链接。

## [完成] NBH-23/E04可选受控自动恢复（2026-11-07）

- 原始目标：默认关闭、独立ACL/原生actor/显式确认，仅新鲜已批准同代结构与Connected证据准入；复用受管restart和共享owner，有限持续异常票、事件一次尝试/冷却与失败封存，不接管未协调恢复器。
- 交付：本地412befd，21文件；独立automatic policy/store/runtime/api与LuCI/RPC/ACL、持久失败告警及永久回归，未push；E05本地7414037/新r9包依赖已清。
- 验证：完整native suite exit0，policy34/budget26/alert8；独立core review复现源样本时长/A→B→A缺陷并修复，复审与surface review NO BLOCKERS。
- 动作边界：7类自动worker guard均零effects；真实supervisor→host→worker等待67244ms，三源周期跨60秒后只执行一次隔离recorder，原生后检UNKNOWN/POST_CHECK_INCOMPLETE而非恢复；持续故障/重建supervisor不重试，只有一个owner-none抑制失败事件。
- UI/权限：真实LuCI默认OFF、未勾确认不可提交、Cancel/health Save不启用；独立确认开/关/reload保持，零即时restart，readonly HTTP写入-32002。post-login/reload产品错误空，所有自有UI/relay/容器已清。
- 不可变证据：local://nbh-e04-native-progress.json，34593实际字节，SHA256 63d26f14fb8539f8d6b6963a965d997186cdec97a04ce7e1679de9d282edc61e；原附件11313/评论11232保留，不重传。
- Jira最终：E05完成后追加依赖解除评论11235 HTTP201，transition41 HTTP204且GET完成10001；实际r9交付引用NBH-24附件11315，完整收据local://nbh-e04-closeout-jira-receipt.json，不重发。
- 剩余边界：前置Connected/结构为显式fixture，restart是隔离recorder；不等于真实VPN/LAN恢复或生产通知。T09真实路径、生产启用、node56/DC、APK签名信任保持独立门禁；用户README未改。

## [完成] NBH-22/E03恢复仲裁与既有watchdog共存（2026-11-07）

- 原始目标：统一luci-watchdog、更新、设置与用户动作的owner/维护/互斥/冷却/预算/审计；外部未协调恢复器显式CONFLICT，禁止新增自动恢复，旧脚本迁移另批。
- 交付：本地09a1ba6，33文件；未push，用户README/账本未入提交，无Bitbucket匹配关联。
- 验证：完整health、owner63/journal35及旧updater/binary-app/timeout/TERM通过；native竞争一个down/up和一个charge，first-install旧组drain/无额外600秒等待、后台真实actor及logout失败保身份通过。
- 审查：非隔离首次安装、迟到重复rollback、stop/procd未知仍删身份均真实RED→GREEN；两项定点复审NO BLOCKERS。
- Jira：附件11311 HTTP200、评论11229 HTTP201、完成transition41 HTTP204，GET确认完成；不得重发。
- 证据：local://nbh-e03-evidence.txt、containment-progress.json、core-review-2.txt、identity-review-2.txt；aggregate实际CRLF字节91895，SHA256 f25c1ab494153cb2f18a3695eb36e75d5340708f6bf300f3d670ffb357b1c723，附件另标LF序列化SHA。
- 边界：A29仅隔离native层PASS；无生产故障/重启/通知/脚本迁移/真实VPN-LAN/物理D态断电/SDK重建/发布，node56/DC与APK trust不变。

## [完成] NBH-21/E02受管agent手动恢复（2026-11-07）

- 原始目标：诊断后独立权限与显式确认、一次受管restart、原生主体与前后脱敏证据、断连续查不重放；真实规则/选路/业务判定，不把命令0或缺LAN当恢复。
- 交付：本地e95e0e0；E03的09a1ba6已清依赖，未push/无Bitbucket关联。
- 验证：A27原生HTTP/LuCI确认/取消/重复一次/保存ID续查与分权；A28实际隔离kernel缺rule/WAN在restart0后仍FAILED/POST_CHECK_FAILED且LAN UNKNOWN。
- 安全：独立claim相对总截止、SIGSTOP过期不迟执行、settings续用、owner/job/verdict/journal与定点核心/授权审查通过。
- Jira：附件11312 HTTP200、评论11230 HTTP201、完成transition41 HTTP204，GET确认完成；不得重发。
- 证据：local://nbh-e02-evidence.txt、action-progress.json、browser-evidence.json；原aggregate64614字节，SHA256 6f8883c935ae6efc3986f46d44f32a12b4c7821b3b515ab965123228bd61273a。
- 边界：原生浏览器/进程及实际kernel惰性agent层，不是生产VPN/LAN恢复或上线许可；E04/E05和T09真实验收仍在TODO.md。

### E02/E03开发过程原始记录（最终结论以上述交付为准）

- E02原始目标：诊断后一键受管agent重启；依赖E01/E03/NBH15/16。立即检查与有副作用恢复严格分开，不把E03依赖缺口伪装成可用恢复。
- E02权限与确认：展示证据/影响/操作范围；独立RPC写权限、CSRF、参数白名单及显式确认，只调用既有受管agent restart，禁止任意命令和自动重试。
- E02审计与续查：执行前保存脱敏快照、真实操作者、job ID及时间；断连后能查询结果，保存前后证据。
- E02结果判定：按原生规则/路由/实际选路/代表业务，而非返回0或PID变化；无真实LAN探针保持未验证。
- E02验收A27：未授权、取消确认、重复点击均不得执行；正常确认恰好一次，前后证据可追踪。
- E02验收A28：restart0但路由/业务未恢复显示失败或部分恢复且保留错误；LAN无证据不得绿。
- E02依赖E03契约：统一动作owner/互斥/维护锁/冷却/重启预算/审计；覆盖luci-watchdog、ztn-watchdog、更新、设置与用户动作。用户脚本不静默改写，外部未协调恢复器必须明确冲突并禁新增自动恢复。
- E02依赖验收边界：A29并发最多一个有效动作；锁超时/崩溃/时钟回退无死锁风暴。维护、认证失效、主动断开禁止新增自动恢复；真实旧脚本迁移仍需独立授权。作为E02前置安全机制实现，不提前声称E03全项完成。
- E02范围/下一步：仅本仓库与自有隔离环境，不生产重启/部署/故障/通知；读取E03共享仲裁要求及既有受管重启/RPC/ACL/UI路径，制定接口后实现、原生故障与浏览器验证、独立审查及同步Jira。
- E02实现接口决定：独立prepare_recovery/start_recovery/get_recovery_job；确认绑定原生认证主体、boot、配置版本及单调截止，一次持久claim先于worker启动，重复提交只续查同job。
- E02仲裁实现顺序：先提取统一action gate并复用/tmp/nb-binop.lock标记，迁移既有二进制/生命周期与设置入口；内核锁负责崩溃释放，root私有审计与重启预算先写后执行，未知执行结果不重放。
- E02证据复用决定：复用export.uc现有字段白名单脱敏，不保存restart原始stdout/stderr；结果要求新鲜同boot/配置的原生路径与业务证据，命令退出码单独保留，LAN缺测不转成功。
- E02前置已实现（未提交）：新增lib/action_lock.uc并迁移netbird.uc二进制/生命周期/更新guard，复用旧目录标记；PID起始时间+boot识别、内核非阻塞锁、首次检测owner死亡后600秒单调孤儿隔离，未知外部内容拒绝接管。
- E02原生证据：自有隔离OpenWrt中action-lock 32断言通过；真实owner SIGKILL后禁止新动作，虚拟单调截止退休通过；实际exec描述符检验证明a继承、ae关闭，未将内核释放当子进程停止证明。
- E02既有回归：test-timeout.sh与test-binary-and-app-update.sh实际exit0，覆盖旧后端查询/超时、来源往返/失败链接/卡住daemon、CDN与包边界。初轮timeout夹具因Windows CRLF失败，修正仅传输归一化后通过，原失败保留。
- E02仍未完成：设置入口原子仲裁、操作者/预算/持久审计、确认RPC与worker/UI及A27/A28/A29完整验收均待实现；上述锁切片不等于一键恢复交付，不改Jira Done，不生产操作。
- E02设置仲裁实现中：新增私有action-worker.uc；settings reload转入共享锁，runner新增固定settings/restart动作与独立120s/20s预算，原采集20s边界不变，公开invoked/cleanup_confirmed供不确定清理保留marker。
- E02设置烟测未通过：隔离夹具先补齐UCI文件与/var/lock；发现原生ucode无setenv，已改固定子shell标志。实际设置执行至start后卡住，40秒宿主超时；递归rc.common与仅source既有reload_service两种均未成功，不把“去递归”当已修根因。
- E02设置调查证据：卡住父/子ash的SigBlk=0000000000010000，netbird子进程僵尸；runner既有回归实际exit0，独立嵌套命令替换也成功，简单ucode锁前后信号mask为0。下一步定位实际procd/捕获输出路径的信号继承与等待，不绕过错误或伪造成功。
- E02设置根因已实证：原生ucode system子进程继承阻塞SIGCHLD，libc fs.popen同路径mask=0；runner改严格单引号参数的popen，保留独立guard截止与整组清理。真正旧system变体在新增有sleep的bounded命令替换用例RED，当前18项GREEN；初次RED夹具误把writefile第三参当mode导致截断，已修夹具后取得真实RED。
- E02设置原生路径已通过：竞争owner期间零agent命令并延期；放行后start/down/up各一次；up退出9原样非零返回且marker清除。为自有惰性agent/init脚本，不是真实NetBird恢复或A27/A28全验收。两个曾超时容器后续精确inspect均不存在。
- E02锁最后校正：原生writefile第三参是字节上限；owner改open(wx,0600)，32项再次通过。证据local://nbh-e02-action-progress.json（10985字节，SHA256 c07bf69ca900b767e60a380da31e77cd9a057a9cf20aa9376c66fa6651cfaed1）；下一步持久预算/审计、原生session操作者、确认RPC、worker和真实LuCI。
- E02动作账本实现决定：共享owner内先原子预留再执行；审计只保存固定字段，不存session或原始输出。恢复默认60秒冷却、每3600秒最多3次；失败和未知执行不退款；boot变化保守重新锚定一次，单调回退拒绝，不靠墙钟清预算。
- E02设置兼容边界：明确配置应用/关闭服务不能被恢复预算阻断；设置仍经过共享互斥与执行前审计，计入后续恢复额度但自身不按恢复限额拒绝。否则短间隔Save&Apply或用户关闭会保存UCI却不执行，违反既有功能。此决定不授权生产操作。
- E02账本切片已原生通过（仍未提交）：新增health/action-journal.uc，settings worker先预留后命令再固定字段结案；25项覆盖冷却/额度/失败不退款/进程重建/boot重锚/单调回退/损坏及symlink拒绝。真实设置夹具通过执行前后审计、退出9原样传播、短间隔配置与明确关闭不受恢复额度阻断、预审计损坏时零命令。
- E02原生主体归因已定位：rpcd handler内同步session.get无法取得主体；改按官方示例返回ubus.defer并在回调request.reply，真实原生登录后取得root（code0），SID仅同进程使用，不打印/落盘。尚未验证uhttpd新ACL/CSRF，不把此探针当A27通过。
- E02最新证据：local://nbh-e02-action-progress.json更新为12565字节，SHA256 eb9a1145cb4a7ead5bce3c6a0a383bf0abfed06571be8f03baf0fc0a8c591006；账本烟测源local://nbh-e02-journal-smoke.uc。下一步真正确认/claim/job/worker与RPC/UI；全health套件及A27/A28/A29完整验收仍未完成。
- E02确认/job切片（未提交）：新增health/recovery-jobs.uc，复用export.evidence白名单；审批绑定服务端actor/boot/revision/120秒单调期限，claim先持久发布queued，重复提交只返回原job，begin只准一次，90秒无回执或换boot标UNKNOWN且不重放，最多保留2个终态job。
- E02原生新增26项断言全部通过：取消/主体错配/版本错配零claim、重复提交/worker/结案拒绝、进程重建不重放、过期/并发/boot中断/单调回退/损坏状态拒绝、既有脱敏和原始命令输出不落盘。该切片尚未接RPC/UI或执行restart，不代表A27/A28完成；断电持久性还需执行前sync屏障。
- E02后端已原生跑通（未提交）：独立recover ACL、原生异步session归因、prepare/start/query严格参数、固定restart worker、动作owner/预算/执行前sync屏障及真实cycle前后证据；设置入口亦补sync，原生五场景仍通过。已有ztn脚本或运行中未协调watchdog明确CONFLICT，不改写/关闭用户脚本。
- E02新增原生证据：15项恢复判定边界通过；无SID/无效SID拒绝，有效主体进入配置验证；实际RPC取消零执行、确认restart一次、重复请求同job、发起连接关闭后完成并保留前后证据。无批准路径实际结果UNKNOWN/NO_APPROVED_PATH；不是VPN或LAN恢复证明。
- E02重复确认竞态已RED→GREEN：worker短期持有存储锁时原先返回RECOVERY_BUSY；get改为读取原子已发布快照，不争写锁，超期/换boot仅投影UNKNOWN；begin的持久事务仍拒绝重放。真实native链路已通过，完整浏览器/HTTP ACL/A28实际故障路径与E03仍待完成。
- E02最新隔离证据：local://nbh-e02-action-progress.json为14463字节，SHA256 3b43422a1954f4dba6aea9176920992669fd43f60d06d8f5d32b8bc904e923bd；全部本轮容器--rm退出，未操作生产/未push/未更改Jira完成状态。下一步LuCI确认/断连续查及原生HTTP分权、共享仲裁剩余接入。
- E02新增真实验收：LuCI复选确认/取消零执行/确认一次/保存ID重载通过；原生HTTP只读角色可读summary但prepare/start/query均拒绝，cookie-only缺有效body SID拒绝，授权重复确认仍只有一次restart。原生NET_ADMIN A28证明restart0后缺规则/WAN实际选路FAIL及LAN UNKNOWN；不是实际VPN。
- E02显式设置续查已实际通过：在restart内合成用户disable并排队settings.pending，结果UNKNOWN/SETTINGS_APPLICATION_PENDING；已有真实updater monitor在owner释放后按原流程执行stop/disable并留下settings审计，未丢应用。完整health套件+action-lock32/job26/verdict15/journal25已exit0；首轮因夹具未安装绝对路径schema失败，补齐真实运行时后通过，非产品回归。
- E02独立审查：授权/UI审查无阻塞；核心审查提出两项尚未复现的阻塞推理：runner把SIGKILL投递成功当cleanup_confirmed；worker在begin后长期暂停可能过期后迟执行。先补原生RED/最小修复独立总截止与执行前job状态校验，再回归，不提交或转Done。审查local://nbh-e02-core-review.txt与nbh-e02-auth-review.txt；浏览器证据local://nbh-e02-browser-evidence.json。
- E02两项审查阻塞已有原生RED→GREEN：未reap的真实组leader证明SIGKILL返回0后进程组仍存在；runner改有界确认组消失，18项回归通过。真实旧worker在begin后SIGSTOP、私有job单调年龄虚拟推进过90秒并持久UNKNOWN后，恢复仍执行restart；新worker执行前复核active状态后零执行。
- E02新增独立总截止：RPC只派发recovery-host并传原claim.created_ms+45000；独立guard先arm后执行真实worker，子命令继承同绝对截止不续期。原生真实worker在owner前SIGSTOP，700ms缩短夹具截止将其终止且零restart；过期派发零invoked。不是90秒真实等待/物理D态注入，均仅自有隔离夹具。
- E02修复后验证：完整原生health套件、action-lock32/job26/verdict15/journal25均exit0；真实kernel A28及取消/重复/发起连接断开/一次restart/前后证据再次通过，结果FAILED/POST_CHECK_FAILED。聚合证据52596字节，SHA256 d768574ef3ac53ff46a93f0fd8850103915dd83bb74ed9f1802b0e949e983c9a；核心修复定点复审cmp-15c407696a579fb8待结果，未提交/未转Done。
- E02本地实现提交e95e0e0（21文件，未push）；仅显式暂存本次源码/测试/基线文档/CHANGELOG，用户README与任务账本未入提交。核心定点复审local://nbh-e02-core-review-2.txt无阻塞；更新后的统一入口实际包含action-lock32并exit0，两项旧回归新隔离运行均exit0。接下来落实E03依赖后统一核对E02/E03状态，不停在提交边界。
- E03接续范围：将既有luci-watchdog/auth停止/意图写入、更新、设置与新增恢复纳入相同owner/预算/审计；外部ztn脚本只识别冲突及提供明确协调接口，未经本人另批不改写/停用生产脚本。维护、认证失效、主动断开禁止新增自动恢复；仅本仓库/自有隔离A29并发、崩溃、时钟与设置续用验收，不生产写入。
- Jira衔接已成功，禁止重发：E02代码进度评论11227 HTTP201；E03开始transition HTTP204及评论11228 HTTP201。E02/E03均未Done；E02等待既有E03任务清依赖，不以源码完成替代全局共存验收。会话todo已标E02 blocked并启动E03。
- E02最终本地证据为local://nbh-e02-action-progress.json，64614字节，SHA256 6f8883c935ae6efc3986f46d44f32a12b4c7821b3b515ab965123228bd61273a；已有浏览器证据与两轮核心/授权审查均保存，未重复发附件或完成状态。继续E03→解锁E02→E04→E05及统一Jira附件/状态核对。
- E03原生阻塞证据：旧shell.with_timeout让父命令1秒超时退出124，但其后台子进程2秒后仍写入标记（orphan_wrote=true）；仅持有父进程owner不能证明后续无写入。先复用既有独立guard/进程组drain到旧有界入口，再做watchdog/全局预算接入；不以kill返回0当清理完成。
- E03旧入口进程组改造已得到原生RED→GREEN：同场景超时仍124且无延迟写入，原始stderr/stdout与exit9保真，持有owner时正常完成释放标记；runner22/action-lock32断言通过，旧timeout实际回归exit0。首次旧回归调用漏传源码目录，未执行到产品检查；纠正参数后的真实通过与失败均存local://nbh-e03-containment-progress.json。
- E03进程组发布/回收已修正：独立短publication lease串行化命令组发布和owner退休，旧owner/released owner不能延迟执行；活组即使超过600秒仍隔离，组消失后遵循既有单调600秒orphan fence。原生真实pre-arm owner SIGKILL与armed owner/helper SIGKILL均无延迟写入并可回收；额外覆盖发布后旧helper迟到清理与时钟倒退，action-lock49断言通过。
- E03本轮兼容性：完整health --unit、旧timeout、binary/app升级回归均exit0，stdout/stderr/exit码保持；根证据local://nbh-e03-containment-progress.json。新增崩溃fixture首次因BusyBox不支持sleep 0.01退出，改用ucode毫秒sleep后实际场景通过；保留两次结果，不把fixture失败记为产品故障。
- E03另一个真实RED→GREEN：desired_connected=0的过期watchdog请求仍执行helper enable/start各两次及CLI up两次；现_do_up在拿到共享owner后、任何helper/CLI副作用前重新读取desired/service_enabled。desired0/service1及desired1/service0均无helper/CLI写入，原意图不变；永久边界回归及不预装源码的独立timeout脚本均exit0，未触碰生产。
- E03 watchdog现已改走root-only watchdog_step：所有adopt/清错/auth停止/up均在共享owner内重读状态与意图；旧caller=watchdog公开约定已清除。exit-node自动恢复亦在同锁内复核显式断开/服务关闭；未改写外部ztn脚本。
- E03协调能力由新脚本真实调用服务器后签发私有receipt，绑定procd实例PID/start/boot与实际argv；单独新init参数、缺失/0644 receipt、旧进程start均不能获协调认可。真实procd启动的Connected采样未覆盖desired0。
- E03新永久原生test-watchdog-ownership.sh通过：root RPC recover=true下的停止/禁用/NeedsLogin/fatal-auth边界、恰好一次owned down及缺失意图adopt均实测。迁移后的独立timeout与实际watchdog TERM回归均exit0；首次module加载方式错误及fixture恢复receipt权限错误保留在原始证据，均已修正。
- E03全局账本新增control（不消耗恢复额度/冷却）与独立handler结案，仍不伪造CLI exit/drain或健康结果；35项永久journal边界通过并接入统一入口。settings仍按原契约消耗后续额度，不因其自身频繁应用或明确关闭被恢复配额拒绝。
- E03更新恢复纳入共享kernel owner：仅在原持久事务/中断恢复进程组已drain后，以boot/PID/start精确匹配私有marker接管；不按空PID或旧action ID猜清理。63项owner断言通过，包含真正存活命令组拒绝、绑定错误/未知外部内容拒绝和无额外600秒等待；旧核心安装/失败回滚/SIGKILL/boot/调度原生脚本exit0。
- E03原生主体统一为actor.uc异步session.get；既有健康恢复仍拒绝无SID，旧root自动化只接受ubusd自身ACL user=root而非客户端字段。实际原生root/无效SID不回退/伪actor不生效/有效session主体均通过；SID特殊参数不需另加RPC schema，rpcd源码与原生调用均已证实。
- E03实际procd/RPC新增全额度回归已永久通过：watchdog与manual reconnect在helper/CLI前拒绝，显式do_down仍恰好一次并记录UNKNOWN健康与真实handler结果；第二次stop归因native-operator。原生发现watchdog把配额拒绝投影为attempted及ucode前向函数引用错误，均修正后通过，失败证据保留。
- E03夹具/运行记录：首次单独owner回归遇合法单数字namespace PID被旧夹具拒绝，修正后63断言通过；另一次Eval超时杀死Python kernel，精确自有容器已不存在。Python现重建，仅保留本轮新harness与结果；旧E02/E03完整证据仍在local artifact，不重新消耗Jira成功操作。
- E03完整原生health套件（含journal35/owner63）、更新核心全部安装/回滚/崩溃/boot矩阵、旧timeout及TERM均exit0；新永久A29原生证明manual/watchdog/settings/updater竞争只有一组down/up及一个恢复charge，立即重试零命令。满额度config关闭、持有真实owner时合作取消、独立first-install恢复亦通过；不代表生产/D态/物理断电验收。
- E03后台主体已实测：真实native session启动来源切换及后台非活动官方二进制更新，审计均为operator-worker，活动custom字节不变。源worker不接收SID；scheduler固定worker传递经过验证的非秘密actor；控制取消仅发布flag并独立control审计，不能借此执行恢复或抢占owner。
- E03首次安装遗留writer已有原生RED→GREEN：旧had_target/was_running条件漏drain，迟写在已恢复后出现；改为所有中断事务都确认旧组消失。新test-recovery-arbitration.sh与test-worker-actors.sh保留实际效果回归；错误cwd、help被夹具误计副作用及broker未ready的失败均已定位并保留。
- E03首轮独立审查local://nbh-e03-core-review.txt与nbh-e03-auth-review.txt发现三个真实风险；锁后事务重验、首次无旧target隔离、local-only logout stop/drain均已复现并修正。核心与身份定点复审local://nbh-e03-core-review-2.txt和nbh-e03-identity-review-2.txt均NO BLOCKERS。
- E03审查待定/不采纳依据：settings免拒绝但计后续额度是既有已记录兼容契约，不按审查建议改成静默延期；_apply_pending_settings派生独立worker而非继承control额度。maintenance_state在已持自身marker时不是unknown，损坏/无phase事务已拒绝；既有显式opt-in integrate-watchdog不得误当本轮擅自改生产脚本，未调用、未改用户脚本。
- E03审查核心两项已原生RED→GREEN：无旧target的非隔离安装原先成功，现全部安装必须setsid worker且拒绝时无事务/target写入；迟到recovery在首个恢复删除快照后原先重复rollback报backup缺失，现owner内重读并绑定事务，终态journal SHA不变。扩展test-agent-update.sh完整矩阵exit0，证据已入containment-progress。
- E03 logout两种真实RED均修正：stop退出9和procd不可观察原先删身份并报成功，现与stop0/仍存活daemon一起保留身份/desired0、零start/restart、handler_failed及UNKNOWN健康。首轮effects误报实为只读init running，不是重启；断言已只计真实生命周期动作。
- E03集成回归完成：health全套及updater/binary-app/timeout/TERM/watchdog/worker actors均exit0；合成first-install补齐真实UUID契约，logout破坏性procd测试独立成test-logout-drain.sh后，原生arbitration与logout均exit0。所有失败原始证据保留，未篡改产品契约迁就夹具。
- E03文档已更新contracts/baseline/acceptance/CHANGELOG，A27–A29明确仅隔离层PASS；用户README未动。下一步显式源码本地提交、Jira必要附件/状态收尾，解锁E02后继续E04/E05；不push、不部署，不以本地验收通过放行node56/DC。

## [完成] NBH-20/E01网络重建完整性与有界收敛（2026-11-07）

- 原始目标：事件监听与周期补漏；网络重启去抖、有限启动宽限/收敛等待；规则链/前缀/from+iif与代表业务全部就绪才正常，五态分开且参数有界，不硬编码布局或臆断disabled根因。
- 交付：本地dcc7577，22文件；共享代际发布栅栏、失败/no-worker截止、缓存及分页失效、单调浏览器等待、严格Schema与配置向后兼容；未push或重新打包冻结r8。
- A25/A26：隔离内核实际rule/route/from+iif从WAN失败到9911/mesh7；规则先恢复不提前正常，实际6秒超过5秒截止后故障，缺业务证明仍不ready。Connected/进程/防火墙为明确夹具，不是真实NetBird/武汉LAN验收。
- 原生验证：完整health套件exit0，convergence17/scheduler18/config43/cache21/alerts31；真实RTNL seq2不延截止，worker和job-allocation失败都在截止复查，实际cycle发布锁遇新事件不投告警票；真实发布AJV严格通过。
- 浏览器：真实LuCI/CGI/uhttpd/rpcd/ubus与独立monitor展示UNKNOWN/完整分母/配置界限；五态共享组件和500ms墙钟回退下自主到期通过，过期等待横幅消失、红色事实保留，认证后无应用JS错误。
- 审查及原件：首轮/复审问题均修正；最终定点core和cache/UI审查无阻塞。local://nbh-e01-native-progress.json、nbh-e01-evidence.txt及nbh-e01-*-review*.txt，既有contracts/baseline/acceptance和CHANGELOG已更新。
- Jira：启动评论11224保持；证据附件11310、完成评论11225，transition41 HTTP204。未重复既有写入；无Bitbucket虚假关联。
- 范围/清理：自有容器全部移除，UI代理/隧道停止且浏览器登出关闭；共享T07夹具、用户README与生产未修改，不发真实通知，不解node56/DC门禁；T09真实路径/ACL欠项仍保留父任务，继续E02→E05。

## [完成] NBH-18/T08隔离验收与版本化本地交付（2026-11-07）

- 原始目标：A01–A24完整分母、资源/安全/并发/时间跳变/孤儿回归、新版本实际生命周期、SDK包/哈希/兼容性/ACL/Schema/迁移/错误码/回退包及明确范围源bundle；真实拓扑未测明确NOT_RUN，保留全部生产门禁。
- 交付：本地3d182dd666d3915506d6bac457886bf6fb3d93cb，0.2.0-r8；两实际SDK exit0，APK/IPK各主包+中文，另有公开r7两格式回退包。docs/health/acceptance.md、performance.md、release-r8.md与baseline.md记录原件层级/签名/迁移/权限及未测边界；未push/发布/部署。
- 原生证据：完整24项中21隔离层PASS，A03/A08/A23 NOT_RUN；实际内核from/iif RED→GREEN但engine仍UNKNOWN；64路径+16目标/401检查/1904ms/峰值10.645MiB、并发排他、64KiB输出、20秒截止及孤儿无迟写。五独立容器旧updater/watchdog/timeout/迁移回归均exit0，原始legacy-regression.txt保留。
- 新SDK生命周期：fresh install→运行→公开r7回退→r8升级→卸载及主包/中文配对成功；28健康文件包所有权/源码一致、实际run严格AJV通过。默认monitor=false/目标空/owner=central且无sink；既有配置rev1保留；七保护比较/实际12100保持、无agent init动作。所有T08自有容器已删除，既有共享夹具未修改。
- 资产：C:/Users/25321/AppData/Local/Temp/nbh-t08-r8-delivery.zip，899942B，SHA256=7fb9a00f08e10db805ac4cc5161151442932c608ed336971169590c3ce9fd3e9；源bundle范围953e4b2..3d182dd，verify通过，SHA256=7a9e0b551847688380964deb4b98820ed6f677db27da200b92a0ca48ca3ff2cd。SDK私密工作区保留供后续授权隔离构建复用；不含用户README或私钥。
- 限制：新APK真实verify仍UNTRUSTED，未改信任根。完整编译stdout及初期原始哈希缓冲随控制内核退出丢失，成功工具断言与保留原件明确区分，不伪造重建。24.10运行/最低硬件/真实engine/LAN/ACL/通知接收/物理重启NOT_RUN；node56/DC门禁不变。
- Jira一次提交：附件11308 HTTP200、评论11220 HTTP201、完成transition41 HTTP204；不得重复。父任务及T09/E01–E05继续TODO.md。

## [完成] NBH-17/T07低噪声通知与observer状态（2026-11-07）

- 原始目标1：默认连续3失败/2恢复，首次异常立即留证；同故障周期去重和上游聚合，主备退化不误报全站断联。
- 原始目标2：健康与排队/提交/accepted/rejected/unknown分离，有限退避/限频；不承诺外部exactly-once或将HTTP接受当接收端送达。
- 原始目标3：central/local/none唯一所有者，新配置默认central但监控关闭；保留既有显式所有者、无自动接管/本地兜底。
- 原始目标4：每轮observer正常/异常明确刷新，恢复清空旧failure；维护暂停保留事件，通知失败不篡改业务健康。
- 原始目标5：独立权限测试通知，不在安装/升级/启用时发测试；秘密仅后端私密TLS配置。
- 交付：本地4b3ee2b，18文件+745/-42，未push/发布；文档contracts/baseline/Schema/CHANGELOG已更新。用户README及任务账本未纳入代码提交。
- 原生验证：完整run.sh通过，含5模型场景及alerts27/runtime24/export19；真实procd/RPC/严格实际run Schema、2589字节脱敏导出通过。实际LuCI11原回归及4项observer正常/异常/XSS/恢复/过期验证通过。
- 真实隔离TLS：503拒绝、200接受但receipt=false、4秒超时unknown；curl60证书不匹配/7拒连无HTTP，恰好4条预期请求。跨revision共享限频与4项staging后最终意图检查均通过；无真实Gotify。
- 审查闭环：配置竞态、维护事件丢失、失败/恢复乱序均RED→GREEN；首异常持久化故障在healthy与disabled前置态均修复为exit4/latest字节保留，重试留证。32事件/丢弃计数、3次提醒、8次退避上限及未知已提交不重放已验证。
- 安全边界：7个保护哈希不变，原fixture revision14/owner none保留；临时TLS CA哈希恢复、sink/监听/地址/代理/HTTP/UI登录及隧道清理。退出255为已验证自有代理清理结果，不重跑。
- Jira：附件11307（4771字节，NBH-17-T07-4b3ee2b-evidence.txt）HTTP200、评论11218 HTTP201、完成transition41 HTTP204，均已成功，不重复写入。原始证据local://nbh-t07-evidence.txt。
- NOT_RUN：生产修改/真实通知或接收端回执/生产故障/SDK发布/推广；T08至E05继续父任务TODO.md，56门槛及DC NOT_RUN不变。

## [完成] NBH-16/T06 LuCI巡检页面与Status摘要（2026-11-06）

- 原始目标1：服务→NetBird→健康巡检和既有Status摘要/链接；网页只读缓存，后端独立调度。
- 原始目标2：结构/节点业务/LAN/外部观察/新鲜度独立，问题列表保留完整分母，Connected不覆盖FAIL。
- 原始目标3：规则/路由/from/iif/mark/来源/协议分层、事件时间线与空窗，缺证据UNKNOWN、无伪造归因。
- 原始目标4：独立权限的立即检查、导出、暂停恢复、配置和测试通知；无自动修复，关网页不取消，多次点击合并。
- 原始目标5：移动端、文本安全、非纯颜色状态和离线旧成功失效；仅本地开发/隔离验证，不授权生产故障或真实通知。
- 交付：本地92a37b5，未push/发布；9个文件，README用户修改未入提交。Jira附件11306（4665字节）、评论11216、完成transition41 HTTP204；写入各一次，不重复。
- 原生验收：真实LuCI CGI/bootstrap/uhttpd/Chromium页面与Status摘要；390px宽无横向溢出。CAS暂停10→11/恢复12/保存13；7项检查完成，双击仅1个start请求；queued job关两网页后done，恢复配置revision14后无浏览器仍有新鲜周期run。
- 下载/权限：实际4317字节下载SHA256=9112b233eadf988c4eb37b7844f79bcc70ba512d3779511644d1003b9da5da07匹配界面；通知NOTIFICATION_NOT_CONFIGURED。真实health-read仅5读方法/无legacy，菜单只有健康页、6按钮及编辑器disabled；5项实际HTTP写入均-32002拒绝。
- 回归：tests/health/ui-browser.mjs在真实页面11/11 PASS，含A01/A02/A06/A09/A10/A19、101项末页FAIL、元数据/分页代际竞争、缺页、挂起RPC过期；这些是显式合成缓存，不冒充真实LAN/生产故障。
- RED→GREEN：展开证据被轮询折叠、RPC挂起旧绿态、E字符串解析恶意img、旧summary混入已过期checks、瞬时配置读取失败禁用重试；两次独立审查与原生复现/修复已记录。旧helper的E安全注释不能当证明，新健康界面使用TextNode/textContent。
- 清理：7项身份/init/watchdog/NetBird/network/firewall哈希不变；shadow逐字恢复并删备份，health配置恢复；两浏览器、所有自建会话/登录段、容器HTTP夹具已移除。仅自建proxy PID2003522主动TERM后exit255（用户已报告，不重跑）；隧道停止API超时已报告，随后proc状态证明exited。生产与node56/DC门槛未改。
- 证据：docs/health/baseline.md、contracts.md、CHANGELOG.md、local://nbh-t06-evidence.txt；后续T07–E05与Jira总进度仍在TODO.md。

## [完成] NBH-15/T05独立UCI、RPC、ACL与导出（2026-11-06）

- 原始目标：14项顺序开发第五项；实现独立UCI与9个健康RPC、只读缓存/完整分母异步合并/游标分页/CAS/opaque导出、5类分权、后端凭据引用与脱敏、SSRF/注入/路径/解析IP/重定向校验；不写agent/network/firewall，不借只读权限探测或恢复。后续T06–E05保留TODO.md。
- 交付：本地9f90407，未push/发布；canonical Schema随包安装，默认关闭。原生HTTP角色及跨角色/匿名/legacy越权拒绝，实际CAS重载与8路同job/7合并，完整7项UNKNOWN不缩分母；导出SHA/字节独立验证。
- 审查修复：每页重判boot/年龄/revision，保留冻结total/order与原证据；通知退出回调补派新revision排队请求，unknown不重放；30秒执行租约回收孤儿而非等10分钟，迟到完成不可覆盖。均有原生RED/GREEN，实际杀死隔离owner后1秒拒绝/31秒接受新revision。
- 统一回归exit0：model22+5场景、runner16/parser33/collector17/evaluator29/lookup18/scheduler12/storage16/maintenance6/boundary8/probe17/config25/settings7/jobs21/pages17/cache16/export18/notification16；UCI测试独立且不改安装态配置。
- HTTPS：真实200接受、302拒绝、exit28/4008ms未知、立即重复不重发；恢复原CA后exit60/72ms未增加接收计数。accepted不是接收确认。私有接收器共11条固定测试消息；无生产通知。
- 包验收：仅夹具版r9源码组装APK（非SDK/发布/签名信任），SHA256为2b434511f5839a97c144c394720eb8edec74d5a5e0b374d5541a8da1788aac07；28必要文件包所有权、27静态文件哈希匹配。实际升级/降级/旧包卸载及当前包直接卸载无健康worker，7保存哨兵不变；已恢复隔离r9用于后续开发。
- 清理：原CA已恢复并核对SHA；仅移除测试lo地址/私密sink/宿主TLS目录/5登录与会话，停止自建uhttpd。TLS受管SSH在主动终止服务器后报exit255，属清理结果，不重启。生产与node56门槛/DC NOT_RUN未变。
- Jira：完成transition41 HTTP204；评论11214 HTTP201；附件11305 HTTP200（NBH-15-T05-9f90407-evidence.txt）；既有进度评论11213未重复。完整证据见docs/health/contracts.md、docs/health/baseline.md、local://nbh-t05-evidence.txt。

## [完成] NBH-14/T04独立后台巡检与维护共存（2026-11-06）

- 原始目标：14项顺序开发的第四项；父任务及T05–E05继续保留TODO.md。
- 交付：本地92e106c，未push/发布；默认关闭procd/uloop服务、60秒周期/30–3600可配、20秒继承截止、单活/点击合并/事件去抖、只读代际维护、五类无凭据探针、私有tmp原子有界状态；既有聚合模型/Schema保持LAN分母。
- 统一回归exit0：model22+5场景、runner16、parser33、collector17、evaluator29、lookup18、scheduler12、storage14、maintenance6、boundary8、probe13通过；独立审查与guard/嵌套截止/lease/历史增长修复均有原生验证。
- 原生运行：真实procd启动/SIGKILL恢复/有界停止；卡死时rpcd5ms响应；20秒截止、owner崩溃无延迟写入、短任务20次点击仅一轮；真实TCP/HTTP/HTTPS/IPv4 ICMP/RDP，缺LAN/engine/overrun证据明确UNKNOWN/事件空窗。
- A21实际APK降级RED复现旧r7不清理新服务，修复自身入口移除时仅注销自己的procd注册；实际降级及apk del GREEN，七项身份哨兵/init/watchdog/UCI/network/firewall哈希均不变，诊断worker/guard为0。
- 包边界：源码验收包由官方ImageBuilder host apk3.0.5低权组装，不冒充完整SDK构建或可信签名；测试版r8未发布，仓库包版本仍r7。SDK镜像900秒超时不补拉；仅容器补齐匹配6.12.74离线依赖，不升级kernel/加载宿主模块。
- Jira：完成HTTP204，评论11212，证据附件11304；无真实Bitbucket关联，不伪造链接。完整证据docs/health/baseline.md、local://nbh-t04-evidence.txt。
- 边界：身份为公开惰性哨兵，未验证真实VPN/LAN业务、物理断电或真实engine重连；无生产部署/故障/告警，56门槛和DC限制不变。保留所有后续父任务。

## [完成] NBH-13/T03规则路由与LAN判定引擎（2026-11-06）

- 原始目标：14项顺序开发的第三项；父任务及T04–E05留在TODO.md。
- 交付：本地fa76bb9，未push；批准IPv4规则链/路由/例外、真实from/iif/mark查询、代际证据绑定、主备与LAN分层、未知归因。
- 验证：model22/runner12/parser33/collector15/evaluator29/lookup18及5模型场景通过；实际隔离内核A01规则与转发FAIL、A02转发PASS且原生漂移warning、A04等价布局PASS。18个实际结果通过Schema；独立审查3问题RED/GREEN。
- 边界：真实peer选择/LAN业务未验证；签名UNTRUSTED依赖仅用于已删除的隔离namespace，不声称可信签名。测试容器僵尸耗尽已通过隔离重启解决，未放宽资源上限；生产未改。
- Jira：完成HTTP204，评论11208、附件11303；未发现真实Bitbucket关联，不伪造链接。详细证据docs/health/baseline.md和local://nbh-t03-evidence.txt。

## [完成] NBH-12/T02只读采集适配器（2026-11-06）

- 原始目标：按顺序开发14项中的第二项，完整父任务仍在TODO.md。
- 交付：本地提交f7f8f75；固定argv有界执行、agent/peer/IPv4规则和全表路由/接口/nft表清单、受限文本回退、白名单脱敏、进程start_ticks及前后代际比较。
- 验证：隔离原生runner12/parser26/collector12，加T01模型22和5场景全通过。真实脱敏0.78.1/0.82.0样本；A01/A04合成采集保留缺规则与等价布局语义；实际缺工具collect()返回未知，30ms，无stderr。
- 独立审查：三轮审查收敛；未知语义丢失、重复/错误字段、任意失败回退、双流预算及iproute2退出255均有RED/GREEN；具体边界见docs/health/baseline.md与contracts.md。
- Jira：评论11204进度、11205交付；附件11302；NBH-12完成HTTP204，NBH-13处理中HTTP204。无真实Bitbucket关联，不伪造链接。
- 边界：未push/部署/生产改动；IPv4首版范围；端点比较非原子快照，nft表清单非防火墙健康，采集验收非后续判定/UI/真实业务验收。下一项NBH-13。

## [完成] NBH-11/T01基线、Schema与健康模型（2026-11-06）

- 原始目标：按NBH-11至NBH-24顺序开发，当前仅完成第一项；剩余父任务留在TODO.md。
- 交付：本地提交68867a8；独立健康配置/结果JSON Schema、意图保留与五视角聚合、A01/A02/A04/A10/A24合成夹具、合法/非法示例、真实ucode测试入口及错误码文档。
- 验证：隔离OpenWrt25.12.2原生22项断言与5场景通过；实际原生输出通过Schema验证；4个非法配置均拒绝。独立审查发现意图severity/排除被观测覆盖，先复现exit254，再修复通过；nullable时间加上界。
- 证据：docs/health/baseline.md、docs/health/contracts.md；Jira评论11203、附件11300（早期18断言）/11301（独立审查后22断言），NBH-11完成HTTP204，NBH-12处理中HTTP204。
- 边界：未push/发布/部署；保留用户README修改；Bitbucket未找到真实关联，不伪造链接。四节点仅只读盘点，DC按原安全门NOT_RUN；合成模型通过不代表采集/判定/UI或生产验收。首次实现前未捕获行为RED，已明确记录，不补造证据。

## [完成] Jira 访问与 netbird-luci 开发任务获取（2026-11-06）

- 原始目标：核实当前是否能够访问 Jira，并获取其中关于 netbird-luci 的开发任务。
- 范围：只读查询；未修改 Jira 事项、代码、路由器或部署配置，未提取浏览器凭据。
- 访问证据：从 Bitbucket 已链接应用发现 https://jira.mellivora.com.cn；初始未登录，myself 返回401。通过页面“使用Zitadel登录”复用现有SSO后，GET /rest/api/2/myself 返回200。
- 获取证据：GET /rest/api/2/search，JQL `project = NBH ORDER BY key ASC`，返回200、total=24，完整返回24条；全部Backlog、未分配。
- 项目：NBH，NetBird · LuCI 健康巡检；Epic NBH-1（v1.0基线 + v1.1网络重建与恢复增补）；功能故事NBH-2–NBH-10共9条。
- 开发任务：NBH-11–NBH-19对应T01–T09；NBH-20–NBH-24对应E01–E05；共14条。详情链接统一为 https://jira.mellivora.com.cn/browse/<编号>。
- 任务范围：Schema与状态机、采集适配器、规则/路由/LAN判定、后台调度、UCI/RPC/ACL、LuCI页面、告警、隔离验收发布、集中汇总/LAN探针、网络重建复检、手动恢复、恢复仲裁、可选自动恢复及A25–A32回归。
- 验收边界：Jira状态及需求描述不是代码实现证据；本次仅获取任务，不授权开发、生产部署、故障注入或真实通知。无剩余查询阻塞。

# 原生功能对齐全表（RN mobile → native）

基线：RN 侧为冻结的 `mobile/`；原生侧以**当前工作树**为准——main HEAD `4ae6ab8`，本阶段功能提交（`732c176` … `4ae6ab8`，含推送客户端 `61384a2`、工程侧 `c561e83`）均已落库；树上未提交的只剩 markdown 汉字间距（`ChatMarkdownView.swift` + `ChatMessageCell.swift` 挂钩 + `ChatMarkdownTests`）与设置子页两处样式微调（`FolderPicker` / `LocationSettings`，样式项不进表）。这张表只列**功能项**：按钮、长按、滑动、菜单、空态动作、错误态重试、开关、输入校验；内距圆角字号不进表，那是布局对照文档的活。

**表的使用规矩**：行号是「参考位置」，会随提交漂移，接单方必须自己从源文重新定位；凡判「缺失」的行都给出原生**确实没有**的落点，不靠「没搜到代码」推断，且落点要**正反两边都搜过**——RN 的概念词（如 blockquote / hr）与原生的可能命名（如 quote / rule）各查一遍（`:104` 的教训，见复核记录）。CI 红时在行末标**「测试失败」**：功能已实现、测试未过，与「缺失」不是一个概念，不改判定值。**表随提交走**：main 每落一笔功能提交，即复核对应行、改判定、行末标提交号；复核记录见文末。

判定值：**一致**（两端都在且行为相同）/ **半实现**（功能在但少一角）/ **缺失**（原生没有）。另有「**原生超集**」标记：RN 没有而原生多出的入口，不算缺口。

文件名先纠正一处：RN 的壳是 `nav/Drawer.tsx` + `nav/ShellB.tsx`，没有 `SheetB.tsx`；`nav/sheet.tsx` 的 SheetHeader / confirmDanger 对应原生导航栏与 UIAlertController 确认弹窗，逐屏核过都一致，不单列。

共 **173 行**：一致 150 · 半实现 16 · 缺失 5 · 原生超集 2。

## 汇总：每屏缺口数

| 屏 | 行数 | 一致 | 半实现 | 缺失 |
|---|---|---|---|---|
| Chat.tsx（聊天主屏） | 25 | 16 | 7 | 2 |
| chat/composer.tsx（输入框） | 10 | 9 | 0 | 1 |
| chat/items.tsx（消息行） | 17 | 12 | 5 | 0 |
| chat/markdown.tsx（Markdown 渲染） | 7 | 7 | 0 | 0 |
| chat/view.tsx（DeepView 卡片） | 14 | 12 | 2 | 0 |
| chat/dock.tsx（待办坞） | 7 | 7 | 0 | 0 |
| TeamList.tsx（团队列表） | 7 | 6 | 0 | 0 |
| NeedsYou.tsx（等你处理） | 4 | 4 | 0 | 0 |
| Pair.tsx（配对） | 6 | 6 | 0 | 0 |
| Settings.tsx（设置根） | 7 | 6 | 0 | 0 |
| settings-pages.tsx（设置子页） | 22 | 21 | 0 | 1 |
| side.tsx（侧问） | 6 | 6 | 0 | 0 |
| manage.tsx（Bot/群管理） | 22 | 21 | 1 | 0 |
| model-menu.tsx（模型单） | 3 | 1 | 1 | 1 |
| nav/Drawer.tsx + ShellB.tsx（壳与抽屉） | 16 | 16 | 0 | 0 |
| **合计** | **173** | **150** | **16** | **5** |

## Chat.tsx（聊天主屏）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 冷启动预读上次对话（prefetchChat） | Chat.tsx:59-65 | 恢复定选已接（`b993b2a`，见 nav 段冷启恢复两行）；**页预读未跟**：启动不预填 ChatPageCache，进对话仍即时加载 | 半实现 |
| 每对话最新页缓存（16 条 LRU、5 分钟过期） | Chat.tsx:51-52,96-102,171-173 | ChatPageCache.swift:41-63 | 一致 |
| 15 秒兜底轮询 | Chat.tsx:24,161-168 | ChatViewController.swift:725-733 | 一致 |
| 跨切对话的外发箱 outbox | Chat.tsx:67-79 | ChatViewController.swift:53,1384-1391 | 一致 |
| 发送幂等去重（known 集合比对） | Chat.tsx:82-84,320-326 | ChatViewController.swift:92-104 | 一致 |
| 上滑分页加载更早（cursor） | Chat.tsx:177-191 | ChatViewController.swift:896-935 | 一致 |
| 列表锚定（老页加载不跳位） | Chat.tsx:383 | ChatViewController.swift:920-936（老页有锚定；新消息到达无锚定） | 半实现 |
| 「最新消息」回底按钮（离底 >600 出现） | Chat.tsx:390-396 | ChatViewController.swift:464-467,1558-1560 | 一致 |
| 流式回复气泡（按 attemptId 累积、断线清空） | Chat.tsx:580-596 | ChatStream.swift:18-38；ChatViewController.swift:109-111,664 | 一致 |
| 停止回合 stop-chat / stop-room-work | Chat.tsx:313-316 | ChatViewController.swift:1715-1728 | 一致 |
| 空对话展示块（头像+名字+角色） | Chat.tsx:445-455 | ChatViewController.swift:469-482（仅一行文字） | 半实现 |
| 读取失败空态 + 重试 | Chat.tsx:361-365 | ChatViewController.swift:469-474（retryLoadButton） | 一致 |
| bot/not-found 识别（对话被删后不硬报错） | Chat.tsx:142,359-360 | 确实没有：读会话失败仅走重试空态，无 not-found 分支 | 缺失 |
| message 事件乐观上屏 | Chat.tsx:252-261 | ChatViewController.swift:748-766（仅触发重读） | 半实现 |
| 进对话即记已读 markSeen | Chat.tsx:239,259 | ChatViewController.swift:1030-1032（读成功后才记） | 半实现 |
| 断线恢复后立即补读 | Chat.tsx:241-245 | ChatViewController.swift:712-733 | 一致 |
| 时间戳规则（同 Bot 折到末条、user 各带、群隐藏） | Chat.tsx:331,459-467 | ChatViewController.swift:115-123；ChatMessageCell.swift:200-206 | 一致 |
| 触觉反馈（发送、答题成功、卡展开） | Chat.tsx:289；dock.tsx:35,87,130 | PendingDockView.swift:292（答题/审批成功 notificationSuccess；发送与 dock 展开未跟） | 半实现 · `61384a2` |
| 附件入口按 send-images 能力门控 | Chat.tsx:407 | 未实现（加号恒可点，老电脑上发送才失败） | 缺失 |
| 键盘监听与避让 | Chat.tsx:211-217,352 | ChatViewController.swift:239-240,1509-1570 | 一致 |
| 文件文本阅读器（file-text → 可选中页） | Chat.tsx:219-230,408-418 | ChatViewController.swift:225-231；TextReaderViewController.swift:15-36 | 一致 |
| 群目标条（点开阶段清单、进度分段） | Chat.tsx:469-507 | RoomGoalView.swift:53-135 | 一致 |
| 电脑使用卡（拒绝/本次/总是 + 停止） | Chat.tsx:509-542 | ComputerUseView.swift:56-93；ChatViewController.swift:1737-1751 | 一致 |
| Bot 受阻修复卡（补 key / 充值 ↗ / 换模型） | Chat.tsx:544-575 | BotBlockedView.swift:56-102；ChatViewController.swift:1486-1494 | 一致 |
| 布局偏好跟随（flat 布局、宽度滑杆 50–100%） | Chat.tsx:205-206,264-271；items.tsx:266-268,303-313 | 宽度滑杆窄屏 RN **同样忽略**（`narrow = chatWidth < 520` 固定 0.93/0.86，与原生 `da4ec32` 一致，iPhone 上非缺口）；「正文宽度」手机端也不读。缺 **flat 跟随**：RN 在 flat 下 Bot 行 `alignSelf: stretch` + `bg=p.main`（**去气泡底**）、群聊整列跳过 22pt 头像/彩名/Admin 行（`:268` 的 `inRoom && !flat`），原生恒气泡布局 | 半实现（复核收窄） |

## chat/composer.tsx（输入框）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 静止胶囊 / 编辑卡两态 + 高度回调 | composer.tsx:26-38,74-92 | NativeComposerView.swift:162-233 | 一致 |
| 发送键三态（可发实色 / 空灰 / 运行中变停止） | composer.tsx:130-132 | NativeComposerView.swift:249-262 | 一致 |
| 单输入框跨态保焦点 | composer.tsx:161-172 | NativeComposerView.swift:52-58 | 一致 |
| 多行增高、约半屏封顶后内滚 | composer.tsx:78-81,168 | NativeComposerView.swift:195-233 | 一致 |
| 加号多选照片 | composer.tsx:62-73 | ChatViewController.swift:1706-1713 | 一致 |
| 缩略图条 + 单张移除 | composer.tsx:147-159 | NativeComposerView.swift:296-314 | 一致 |
| 照片压缩（长边 2048 / JPEG 0.82） | composer.tsx:15-24 | NativeComposerView.swift:283-292 | 一致 |
| 选图失败提示 pickError | composer.tsx:64-72,135 | 确实没有：选图失败走系统静默，无应用内提示文案 | 缺失 |
| 键盘期间输入框贴 12pt | composer.tsx:86,113-114 | ChatViewController.swift:1509-1540 | 一致 |
| 切对话清草稿（RN 靠重挂丢弃） | ShellB.tsx:219（key 重建） | NativeComposerView.swift:274-281（clear()） | 一致 |

## chat/items.tsx（消息行）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 文件行（名/类型/KB，点开 file-text） | items.tsx:89-97 | ChatMessageCell.swift:258-270（仅文件名可点；「扩展名 · KB」副行缺，items.tsx:94） | 半实现 |
| 「查看完整消息」长文链接 | items.tsx:98-102 | ChatTimeline.swift:152-156 | 一致 |
| 步骤行（工具清单、失败标注、点按展开） | items.tsx:474-516 | ChatTimeline.swift:162-177；ChatViewController.swift:1813（expandedSteps 切换） | 一致 |
| 相邻步骤行折叠成一行汇总 | Chat.tsx:425-443 | 端上无需折叠：宿主 parts.js:1928-1970 的 stepsItems/applySteps 按 turn 合成**单条** steps item（tools 合并、ms 合计），端上收不到相邻 steps 行；RN 端 foldSteps 为防御性代码、实际无事可合，Chat.tsx:343 三元 `row.key : row.key` 双枝同值属死代码。原生 stepSummary/stepDetails（ChatTimeline.swift:162-177）+ expandedSteps 与 RN openSteps 一一对应 | 一致（复核改判） |
| 发送中半透明、失败红字重试 / 删除 | items.tsx:232-252 | ChatMessageCell.swift:289-299 + ChatViewController 重试/删除在；**sending 态无 0.7 透明度**（items.tsx:233，cell 全程无 alpha 处理） | 半实现 |
| via {平台} 来源标签 | items.tsx:253-259 | ChatTimeline.swift（IMPlatforms 映射 + viaTagText，与时钟同排）+ ChatMessageCell.swift:62,104-114,283-288（ViaTagLabel） | 一致 · `7df694c` |
| 分隔条带日期标签 | items.tsx:111-119 | ChatTimeline.swift:230（仅固定文案「更早的对话」，无 clockLabel 日期） | 半实现 |
| settled 关闭卡（已用消息回答 / 已关闭） | items.tsx:133-146 | SettledCard.swift:32-35 + ChatMessageCell.swift:311-315（虚线 DashedPill 徽标 Answered by message / Dismissed） | 一致 · `732c176` |
| settled 卡片可点开重看（只读） | items.tsx:147-153 | ChatViewController.swift:1817（viewRecord 只读打开） | 一致 |
| settled 浏览器交接结果卡（Skipped/Returned 徽标） | items.tsx:155-180 | SettledCard.swift:40-48,77-99（handoff 四种标题；正文藏 JSON 的兜底解析；Skipped/Returned 徽标或对勾）+ ChatMessageCell.swift:316-320 | 一致 · `732c176` |
| settled DeepView 答案回显（题面+所选） | items.tsx:181-195 | SettledCard.swift:49-59,120-146（viewAnswerText 以用户所见标签拼单行）+ ChatMessageCell.swift:321-331（空 detail 回退原文） | 一致 · `732c176` |
| settled ask_user 回显（问题+字母徽标选项） | items.tsx:196-218 | SettledCard.swift:60-70,101-116（字母=选项序号、custom 答案越界取下一字母）+ ChatMessageCell.swift:332-342（22pt 强调色徽标） | 一致 · `732c176` |
| 群行成员头像 / 彩色名字 / 管理员标 | items.tsx:266-299 | 缺：原生无 22pt 头像列、无彩名、无 Admin 徽标（仅名字时用 ink3）。**注**：电脑设 flat 时 RN 自己也不画这一列（`inRoom && !flat`），此缺口只在气泡布局下成立 | 半实现 |
| 图片网格 + 点开查看器 | items.tsx:341-379 | ChatMessageCell.swift:7-49（单图 200 方、多图双列 120、6pt 间距已对齐）+ 234-254 点按进查看器；**失败占位「View it on the computer」与加载 spinner 缺**（items.tsx:368-372） | 半实现（`159c387`/`18eaf23` 对齐尺寸） |
| 图片查看器（分页滑动、计数、原图替换预览） | items.tsx:381-412 | PhotoViewController.swift:3-88；ChatViewController.swift:1797 | 一致 |
| 外发本地图即时显示 | items.tsx:229-241,331-339 | ChatMessageCell.swift:246-252 | 一致 |
| 纯图消息不带气泡 | items.tsx:229-234 | ChatMessageCell.swift photosOnly 分支：photoInsets 贴边、气泡去填充去内距（items.tsx:248 对齐） | 一致 · `7df694c` |

## chat/markdown.tsx（Markdown 渲染）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 块：标题 / 段落 / 代码 / 列表（嵌套）/ 表格 | markdown.tsx:53-154 | ChatMarkdownView.swift:9-14,220-226 | 一致 |
| 引用块 / 水平分隔线 | markdown.tsx:109-119,140-141 | ChatMarkdownView.swift:15-16（case quote / rule）、:55-59 与 :67-78 解析、:274-279 渲 1pt palette.line 分隔线、:346-355 quoteView（3pt 左竖条 + 引用内递归渲染）；测试含混合源与引用内代码块。`f9ed166` 起即在 | 一致 |
| 代码/表格横向滚动 + 右缘渐隐 | markdown.tsx:156-188 | ChatMarkdownView.swift:189-341 | 一致 |
| 行内样式 strong/em/codespan/del | markdown.tsx:207-238 | ChatMarkdownView.swift:243-253 | 一致 |
| 链接安全白名单（http/https/mailto，其余降纯文本） | markdown.tsx:219-231 | MarkdownLinkLabel.swift:22 | 一致 |
| codespan 与汉字间   间距 | markdown.tsx:190-205 | MarkdownHanSpacing（ChatMarkdownView.swift:194，三条渲染路径全挂：:293、:407 + ChatMessageCell.swift:236；测试 7 例） | 一致 · `97496cd` |
| 宽块检测（代码/表格占满泡宽） | markdown.tsx:23-27 | ChatMarkdownView.swift:205（hasWideBlock） | 一致 |

## chat/view.tsx（DeepView 卡片）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 基础节点 stack/row/text/metric/table/callout/sources/html/progress | view.tsx:89-159 | PendingViewController.swift:223-292 | 一致 |
| slider（拖动、步进取整） | view.tsx:160-174 | PendingViewController.swift:319-331 | 一致 |
| number 的 −/+ 步进按钮 | view.tsx:176-190 | PendingViewController.swift:332-357（数字键盘直输 + 规则归一） | 半实现 |
| choice（短选项分段 / 长选项堆叠） | view.tsx:192-213 | PendingViewController.swift:293-306（恒分段） | 半实现 |
| toggle | view.tsx:214-221 | PendingViewController.swift:309-318 | 一致 |
| options 单/多选 + 提交 | view.tsx:242-259 | PendingViewController.swift:358-389 | 一致 |
| confirm 双按钮 | view.tsx:225-232 | PendingViewController.swift:390-399 | 一致 |
| form 字段（含 multiline）+ 提交 | view.tsx:262-279 | PendingViewController.swift:400-433 | 一致 |
| submit 按钮 | view.tsx:236-237 | PendingViewController.swift:434-439 | 一致 |
| 公式求值（inputs/lets 作用域） | view.tsx:16-35,57-72 | DeepViewFormula.swift；PendingViewController.swift:82,160 | 一致 |
| 图表 bar/hbar/line/area/donut | view.tsx:305-383 | DeepViewChartView.swift:284-367 | 一致 |
| 图表交互（点选高亮/图例隐藏/转表格/复制 CSV） | view.tsx:307-380 | DeepViewChartView.swift:104-155,183-274 | 一致 |
| 回答携带当前 inputs | view.tsx:36-44 | PendingViewController.swift:444-456 | 一致 |
| Dismiss 关闭卡片 | view.tsx:45,50 | PendingViewController.swift:87,469-478 | 一致 |

## chat/dock.tsx（待办坞）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 手风琴卡组（点标题展开收起、首个待办自动展开） | dock.tsx:31-44,52-74 | PendingDockView.swift:104-130；ChatViewController.swift:1596-1613 | 一致 |
| 问题卡（选项、自填答案、过期提示） | dock.tsx:77-122 | PendingDockView.swift:165-180 | 一致 |
| 审批卡（拒绝 / 仅此一次 / 去电脑上答） | dock.tsx:124-155 | PendingDockView.swift:189-193 | 一致 |
| 密钥卡（允许：取消/允许；需要：输入+保存） | dock.tsx:162-203 | PendingDockView.swift:199-213 | 一致 |
| 侧问卡 btw（删除 / 消掉） | dock.tsx:206-240 | PendingDockView.swift:234-236 | 一致 |
| 浏览器交接卡（卡片 / 跳过 / 完成） | dock.tsx:242-262 | PendingDockView.swift:221-223 | 一致 |
| 运行状态行（「X 正在做…」） | dock.tsx:265-286 | WorkStatusView.swift:48-75 | 一致 |

## TeamList.tsx（团队列表）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| Main Bot 磁贴区 | TeamList.tsx:75-86 | TeamListViewController.swift 磁贴区；`63119b8` 起磁贴带 ? / 工作中绿点 / 主星（marks.tsx:69-87） | 一致 · `63119b8` |
| 置顶优先 + 最近消息排序 | TeamList.tsx:32-40 | TeamListViewController.swift:272-274 | 一致 |
| 状态预览短语（等你回答/等你批准/正在做/群内工作） | TeamList.tsx:42-65 | TeamListViewController.swift:234-301 | 一致 |
| 未读红点（seen 比较） | TeamList.tsx:88,110 | TeamListViewController.swift:474-479,606-615 | 一致 |
| 群行等待 ? 徽标 / 工作中绿点 | TeamList.tsx:118-130 | TeamListViewController.swift:517-623 | 一致 |
| 搜索过滤（大小写不敏感） | ShellB.tsx:80-85 | TeamListViewController.swift:202,222 | 一致 |
| 无 Bot 时的空态入口（新 Bot 按钮） | —（RN 抽屉头部只有 + 按钮） | TeamListViewController.swift:316-359 | 原生超集 |

## NeedsYou.tsx（等你处理）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 五分组（问题/审批/密钥/交接/卡片）带徽标 | NeedsYou.tsx:38-44 | NeedsYouViewController.swift:106-108 | 一致 |
| 行点击直达对话（含群） | NeedsYou.tsx:66-78 | NeedsYouViewController.swift:110-118 | 一致 |
| 行内头像 + 等待标 | NeedsYou.tsx:66-71 | NeedsYouViewController.swift:253-332（44pt 头像 + marks 等待问号角标） | 一致 · `133bc63` |
| 空态「没有要等你的事」 | NeedsYou.tsx:79 | NeedsYouViewController.swift:125 | 一致 |

## Pair.tsx（配对）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 扫码配对（相机权限、被拒提示换粘贴） | Pair.tsx:45-51 | PairingScannerViewController.swift:30-70 | 一致 |
| 粘贴链接 + 按钮配对 | Pair.tsx:53-61 | PairingViewController.swift:24-29,81-92 | 一致 |
| 输入框回车即配（returnKeyType=go） | Pair.tsx:55 | PairingViewController.swift:33-34,118-124（.go + textFieldShouldReturn → submit，解析失败键盘保持） | 一致 · `61384a2` |
| dsbot://pair 深链打开即自动配 | Pair.tsx:34-38；App.tsx:104-110 | SceneDelegate.swift:28-30,51-60（冷启 urlContexts 与 openURLContexts 同走 handlePairingURLs）→ ChatViewController.swift:1242；scheme 注册在 project.yml（`c561e83`） | 一致 · `61384a2`+`c561e83` |
| 连接状态文案（等待电脑/已连接/失败重试） | Pair.tsx:47-63 | PairingViewController.swift:65-79 | 一致 |
| busy 防重入 | Pair.tsx:20-24 | PairingViewController.swift:85 | 一致 |

## Settings.tsx（设置根）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| Computers 行（显示当前电脑名） | Settings.tsx:74 | NativeSettingsViewController.swift:48-51,99-101 | 一致 |
| 外观三选（系统/浅/深） | Settings.tsx:75-76 | NativeSettingsViewController.swift:51-54,102-113 | 一致 |
| 语言三选（跟随系统/中文/英文） | Settings.tsx:77-78 | NativeSettingsViewController.swift:64-67,119-130 | 一致 |
| 应用内横幅开关 | Settings.tsx:79 | NativeSettingsViewController.swift:56-63,153-155 | 一致 |
| 推送通知开关（真推送：权限申请、token 上报、点击/冷启路由；RN 无此功能） | —（RN 无推送） | NativeSettingsViewController.swift:69,71,173-175 + PushCenter.swift + AppDelegate.swift:12,26-28；工程侧 entitlements/scheme 在 `c561e83`。验收单见 `docs/qa/native-push-acceptance.md` | 原生超集 · `61384a2` |
| 八个团队页入口（模型/连接器/能力/用量/密钥/位置/更新/关于） | Settings.tsx:83-90 | NativeSettingsViewController.swift:68-92,131-149 | 一致 |
| 配色跟随电脑偏好（prefs.theme/accent） | App.tsx:47；tokens palette() | DesignTokens.swift:287-304（ThemeStore） | 一致 |

## settings-pages.tsx（设置子页）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 服务商列表展开 + key 状态 | settings-pages.tsx:124-146 | ProviderSettingsViewController.swift:71 | 一致 |
| 替换 key / 清除 key | settings-pages.tsx:138-145 | ProviderSettingsViewController.swift:106,131 | 一致 |
| 移除服务商（确认弹窗） | settings-pages.tsx:160-165 | ProviderSettingsViewController.swift:162-166 | 一致 |
| 已知服务商添加（选 + 可选 key） | settings-pages.tsx:177-198 | ProviderSettingsViewController.swift:138-147 | 一致 |
| 自定义服务商（ID/名/URL/key） | settings-pages.tsx:199-222 | CustomProviderViewController.swift:48-52,203 | 一致 |
| 按 URL 发现模型（Find models） | settings-pages.tsx:205,219 | CustomProviderViewController.swift:93,154-173 | 一致 |
| 模型多选 | settings-pages.tsx:212 | CustomProviderViewController.swift:183-186 | 一致 |
| 连接器：连接/断开/重试 | settings-pages.tsx:278-280 | ConnectorSettingsViewController.swift:76-107 | 一致 |
| 连接器 token 输入弹窗 | settings-pages.tsx:284-288 | ConnectorSettingsViewController.swift:94-107 | 一致 |
| 「在 {name} 创建 token」外链 | settings-pages.tsx:285 | 确实没有：连接器 token 弹窗无外链入口 | 缺失 |
| 能力列表 + 状态行 | settings-pages.tsx:355-369 | CapabilitiesViewController.swift:57-93 | 一致 |
| 能力编辑器（按类型出字段） | settings-pages.tsx:380-434 | CapabilitiesViewController.swift:130-186 | 一致 |
| 能力批准 / 删除 | settings-pages.tsx:368-369 | CapabilitiesViewController.swift:86-90,207-209 | 一致 |
| Bot 能力附加开关 | manage.tsx:385-388 | CapabilitiesViewController.swift:249-315 | 一致 |
| 团队用量（Tokens in/out、按 Bot、按模型） | settings-pages.tsx:459-467 | UsageViewController.swift:86-106 | 一致 |
| 位置：团队工作区改选 | settings-pages.tsx:486 | LocationSettingsViewController.swift:23-24；FolderPickerViewController.swift:114 | 一致 |
| 更新检查 + 版本行 | settings-pages.tsx:534,537 | UpdatesSettingsViewController.swift:71-72,124 | 一致 |
| 安装更新（DS Bot / DSH，确认弹窗） | settings-pages.tsx:536,541 | UpdatesSettingsViewController.swift:125-127 | 一致 |
| 更新说明 What is new | settings-pages.tsx:535 | UpdatesSettingsViewController.swift:73 | 一致 |
| 诊断日志查看 / 复制 | settings-pages.tsx:544-556 | UpdatesSettingsViewController.swift:77-80,155,198-212 | 一致 |
| 清除诊断（确认） | settings-pages.tsx:557 | UpdatesSettingsViewController.swift:85 | 一致 |
| 关于（版本行、LICENSE 与仓库外链） | settings-pages.tsx:577-584 | AboutViewController.swift:50-68 | 一致 |

## side.tsx（侧问）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 侧问卡列表 + 条数 + 空态 | side.tsx:83-96 | SideChatViewController.swift:223-243 | 一致 |
| 关闭当前侧问（side-close） | side.tsx:75-79 | SideChatViewController.swift:163 | 一致 |
| 回答中可取消（side-cancel） | side.tsx:104-108 | SideChatViewController.swift:205,259-260 | 一致 |
| 失败 / 已取消文案 | side.tsx:111-112 | SideChatViewController.swift:248-249 | 一致 |
| 发送（side-new + side-ask，空文禁发） | side.tsx:36-51 | SideChatViewController.swift:181-189 | 一致 |
| 回答期间 1.5 秒加速轮询 | side.tsx:54-58 | SideChatViewController.swift:112-121 | 一致 |

## manage.tsx（Bot/群管理）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| Bot 详情页（模型/权限/文件夹/说明/记忆/用量/排程） | manage.tsx:213-254 | ConversationDetailsViewController.swift:152-164 | 一致 |
| 详情页模型行直接弹模型单 | manage.tsx:233（ModelMenu） | ConversationDetailsViewController.swift:129-130（跳编辑页再选） | 半实现 |
| Browser 标签页 | manage.tsx:227-229 | ConversationDetailsViewController.swift:163,141-146 | 一致 |
| 权限预设分段（含 Full access 红字） | manage.tsx:268-293 | ConversationDetailsViewController.swift:172-185 | 一致 |
| 编辑入口（齿轮） | manage.tsx:218 | ConversationDetailsViewController.swift:36,193 | 一致 |
| Bot 编辑：名字/标签/形状/颜色 | manage.tsx:414-424 | BotEditorViewController.swift:75-91,160-169 | 一致 |
| Bot 编辑：头像照片上传 / 移除 | manage.tsx:426-428 | BotEditorViewController.swift：PHPicker 单选 .images；Upload/Remove photo 各 44pt（无照片时移除键隐藏）；移除后 avatar 只留 shape（RN 同款）；`avatarBase` 让延迟保存叠加在本会话已写的头像上（形状改选后不复活旧照片），BotEditorAvatarTests 4 例 | 一致 · `ac2e140` |
| Bot 编辑：说明多行 | manage.tsx:433-434 | BotEditorViewController.swift:80 | 一致 |
| Bot 编辑：Private / Main 开关 | manage.tsx:436-444 | BotEditorViewController.swift:100-104,263 | 一致 |
| Bot 编辑：复制 / 删除（确认） | manage.tsx:448-449 | BotEditorViewController.swift:295-313 | 一致 |
| 新建 Bot 重名校验（clash 禁创建） | manage.tsx:488-495 | BotEditorViewController.swift：nameClash 对 state.bots 大小写不敏感比对（空名按「New Bot」算）、editingChanged 实时提示「Another Bot has this name.」、命中即禁用保存键；仅新建路径启用，编辑既有 Bot 不拦 | 一致 · `ac2e140` |
| 新建群（≥2 成员 + 管理员） | manage.tsx:659-714 | GroupEditorViewController.swift:188-198 | 一致 |
| 群详情（公告/成员列表/谁回答/记忆入口） | manage.tsx:545-591 | ConversationDetailsViewController.swift:207-214 | 一致 |
| 群设置（名/公告/模式/成员勾选/管理员移交/删除） | manage.tsx:596-657 | GroupEditorViewController.swift:207-234 | 一致 |
| 记忆问答（memory-ask） | manage.tsx:745-758 | MemoryViewController.swift:121-131 | 一致 |
| 记忆条目列表 + 移除（确认） | manage.tsx:760-778 | MemoryViewController.swift:144-155 | 一致 |
| 记忆条目新增 / 编辑弹窗（memory-add/edit） | manage.tsx:741,782-796 | MemoryViewController.swift:189-243 | 一致 |
| 排程：四种时制 + 校验 + 删除 | manage.tsx:803-923 | SchedulesViewController.swift:158-338 | 一致 |
| 文件夹选择（最近/上级/截断提示/回写） | manage.tsx:927-960 | FolderPickerViewController.swift:36-120 | 一致 |
| 电脑列表（指纹、切换、忘记、新增） | manage.tsx:1013-1050 | ComputersViewController.swift:23-85 | 一致 |
| 密钥添加 / 删除 | manage.tsx:1070-1091 | SecretsSettingsViewController.swift:81-105 | 一致 |
| Bot 浏览器页（截帧 + 完成/跳过/接管/归还/停止 + 2s 刷新） | manage.tsx:1133-1177 | BrowserHandoffViewController.swift:21-167 | 一致 |

## model-menu.tsx（模型单）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 模型分组列表 + 默认标记 + providers 入口 | model-menu.tsx:146-165,233-237 | BotEditorViewController.swift:176-206（在编辑页内；显示 ref、无 providers 入口） | 半实现 |
| 思考档选择 + 恢复默认（efforts 远端拉取） | model-menu.tsx:47-143 | BotEditorViewController.swift:184-225 | 一致 |
| 未选模型时的引导文案 | model-menu.tsx:221 | 确实没有：编辑页模型区无未选引导分支 | 缺失 |

## nav/Drawer.tsx + ShellB.tsx（壳与抽屉）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 左缘右滑开抽屉（24pt 边缘带） | Drawer.tsx:63-69 | ChatViewController.swift:1042-1054 | 一致 |
| 面板跟手拖拽、过半/快甩收起 | Drawer.tsx:70-74 | TeamDrawerTransition.swift:73-103 | 一致 |
| 点遮罩关闭 | Drawer.tsx:90 | TeamDrawerTransition.swift:127 | 一致 |
| 开抽屉先收键盘 | Drawer.tsx:29,67 | ChatViewController.swift:1017 | 一致 |
| 硬件返回先关抽屉 | Drawer.tsx:49-55 | 不适用（iOS 无硬件返回） | 一致 |
| 顶栏菜单键 + 未读待办红点 | ShellB.tsx:148-150 | ChatViewController.swift:1609（showsDot） | 一致 |
| 标题胶囊点开 Bot/群详情 | ShellB.tsx:155,205 | ChatViewController.swift:1080-1089 | 一致 |
| 侧问按钮（仅 Bot 会话出现） | ShellB.tsx:157-161 | ChatViewController.swift:132-135 | 一致 |
| 重连状态提示 + 重试入口 | ShellB.tsx:163-179 | ChatViewController.swift:337-342,666-676 | 一致 |
| 通知横幅（8 秒自动消、点开对话、跳过当前对话、受横幅开关控制） | ShellB.tsx:274-311 | ChatViewController.swift:752,795（同套 guard：开关/kind/当前对话跳过/8 秒/点击路由）+ NoticeOverlay.swift window 级（设置 sheet 盖不住） | 一致 · `61384a2` |
| 「等你处理 · N」行 | ShellB.tsx:88-96 | TeamListViewController.swift:470,486 | 一致 |
| 搜索开关 + 搜索框 | ShellB.tsx:73-85 | TeamListViewController.swift:174,217 | 一致 |
| New 弹层（创建 Bot / 创建群） | ShellB.tsx:100-114 | TeamListViewController.swift showCreate → NewChatSheetController（底部 scrim 卡；创建先关抽屉再导航，对应 ShellB.tsx:51） | 一致 · `91f42c2` |
| 齿轮设置入口 | ShellB.tsx:117-121 | TeamListViewController.swift:154-155,181 | 一致 |
| 冷启动恢复上次对话 | ShellB.tsx:31,190-191,348-357 | 每次切换保存（`2d8d235`）+ 首个团队 state 时 restore(stillKnown:) 一次定选（ChatViewController restoredLastChat），名字由团队数组回填 | 一致 · `b993b2a` |
| 上次对话已删时回退主 Bot | ShellB.tsx:199-204,218 | restore 判团队无此目标即自清存（LastChatStore.restore），selectedTarget 保持 nil 落回主 Bot 兜底 | 一致 · `b993b2a` |

---

## ui/marks.tsx（角色头像 / 角色标记）

出处：`mobile/src/ui/marks.tsx`（`Mark` / `Members`），形状与配色在宿主侧 `ds-bot/src/client/characters.js`（`lookOf` / `characterMarkup` / `MAIN_LOOK` / `shapeOf`）。注意这条跨两棵源码树：RN 只负责画，**「长什么样」由宿主决定**，所以判据必须落到「同一个角色画出来是同一个东西」。

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 角色头像渲染（Bot 画角色、房间画成员簇） | marks.tsx:1-118；characters.js（lookOf/shapeOf） | `CharacterPaint.swift:215` `MarkView` + `CharacterMarks`（`d85550a`）；接线 `36eb011`：顶栏 28pt、空对话块 64pt、NeedsYou 44pt、抽屉磁贴 52pt/行 36pt（ChatViewController:30、EmptyChatView:10、NeedsYouViewController:299、TeamListViewController:516/741） | 一致（四处）；**群行 22pt 未接**：数据已备（`45328e2` `RoomRowData`），渲染待 Canvas（`ChatMessageCell`），见 `items.tsx:286` |
| 房间无已知成员 | marks.tsx `Members` 空数组 | `MarkView` 两个子视图都隐藏，不画空环；`HeaderMark.choose` 返回 `(nil, [])` | 一致 |

## 玻璃层（跨屏基建）

| 功能项 | RN 出处 | 原生现状 | 判定 |
|---|---|---|---|
| 玻璃层的命中测试 | —（RN 玻璃是 view，不吞子控件触摸） | `UIVisualEffectView` 会把落在自己身上的触摸吃掉，压在它下面的按钮点不中；`332fb9c` 让玻璃把触摸透给控件，不再盖住整条顶栏 | 一致（原生特有坑，RN 无对应） |
| 输入框玻璃自成形 | —（RN 用 border-radius + 背景，不存在父层裁切） | `229f796`：玻璃边不能靠父视图 `clipsToBounds` 切——圆角会被切出硬边、材质也失真；改为 `UIVisualEffectView` 自带形状（`cornerConfiguration`） | 一致（原生特有实现，无 RN 对照） |

## 备注：读表时容易误判的三处

1. **「半实现」不等于坏**：number 节点用数字键盘直输代替 −/+ 步进、choice 恒用分段、模型单藏在编辑页里，功能都到得了，形态不同。是否算过关是产品判断，表只记事实。
2. **重连那套没进这张表**：LinkSession 的退避 / 断线判定 / 回前台探活是网络层，已由 `docs/qa/ios-reconnect-checks.md` 与 `docs/native-behaviour-gaps.md` 覆盖，此处不重复计数。
3. **原生超集一行**（团队列表空态的「新 Bot」按钮）不需要派活；RN 对应位置只有抽屉头部的 + 按钮，能力等价。

---

## 半实现分区（16 条，Warden 2026-11-19 裁定）

### A · 缺一角、用户能感知 → 进下一批（12 条）

按体感排，Warden 已派人；后两条按裁定排在本批末段。

| 体感 | 条目 | 屏 |
|---|---|---|
| 高 | 新消息到达无锚定（读历史被顶走） | Chat.tsx |
| 高 | 群行成员头像 / 彩色名字 / 管理员标 | chat/items.tsx |
| 高 | 图片网格失败占位「View it on the computer」+ 加载 spinner | chat/items.tsx |
| 高 | flat 布局跟随（电脑设 flat 时 Bot 行通栏） | Chat.tsx |
| 中 | 文件行「扩展名 · KB」副行 | chat/items.tsx |
| 中 | 分隔条日期标签 | chat/items.tsx |
| 中 | 模型单显示名 + providers 入口 | model-menu.tsx |
| 中 | 空对话展示块（头像 + 名字 + 角色） | Chat.tsx |
| 中 | 发送 / dock 展开的触觉 | Chat.tsx |
| 中 | message 事件乐观上屏（现仅触发重读） | Chat.tsx |
| 低（排后） | markSeen 时机（读失败时红点不清） | Chat.tsx |
| 低（排后） | 冷启动页预读（进对话有一拍加载态） | Chat.tsx |

### B · 形态差异、功能到得了 → 归档「已知差异」，不再派活（4 条）

| 条目 | 差异 | 归档理由 |
|---|---|---|
| sending 态 | RN 气泡 0.7 半透明；原生「Sending…」文字 | 信息等价，原生更明确 |
| number 节点 −/+ 步进 | RN 两个步进键；原生数字键盘直输 + 规则归一 | 目标值同样到得了 |
| choice 长选项堆叠 | RN 长选项竖排；原生恒分段 | **例外条款**：真机若见长选项被截断，拍照/描述报 Warden，升回 A |
| 详情页模型行 | RN 点行直接弹模型单；原生跳编辑页再选 | 多一跳，能力不缺 |

---

## 复核记录（表随提交走）

### 2026-11-19 · 为什么这一轮是用户先发现，而不是表先发现

用户报的三条里，**两条根本不是「缺功能」，而是「功能在、画出来的不是同一样东西」**：

1. **角色头像**：原生四处都有头像（顶栏/空对话/NeedsYou/抽屉），表上一直记「有」，直到用户看出「这是个字母，桌面画的是角色」。表从未有这一行——因为它核的是「有没有头像」。
2. **顶栏命中测试 / 输入框玻璃**：两处都能点、都显示，缺陷是「玻璃盖住了点击」「玻璃边被父层切掉」。这两类只在真机上、只以「点了没反应/边是硬的」形式出现，表里同样没有落点。

**根因**：这张表此前只核「有没有这个功能」，没核「画的是不是同一样东西」。功能覆盖面能靠读代码补，视觉一致性不能——它需要把 RN 的**画法**和原生的**画法**并排比对，而表的结构里没有那一栏。

**改进规则（即刻生效）**：

- 凡**视觉类**条目，判据必须写成「与 RN 画的是同一个东西」，不能只写「有」。写行时附一句画法出处（RN 文件名 + 原生类型/方法），没有画出处的行不算核过。
- 「有按钮 / 有头像 / 有背景」不是判据，是计数器；计数器的值恒为「有」。
- 跨两棵源码树的视觉（如 `marks.tsx` 只画、`characters.js` 决定长什么样），出处两处都要写，否则复核者只能核到一半。
- 表里出现「原生特有坑」（玻璃吞触摸、父层裁切）时，也补一行：它们是用户能感知的缺陷，与 RN 缺功能同级。

- **2026-11-19 晨**：首次滚动复核，基线推至 `422900b`。覆盖 `732c176`（settled 卡三连）、`159c387`+`18eaf23`（网格尺寸）、`63119b8`（磁贴标记）、`91f42c2`（New 底卡）、`133bc63`（NeedsYou 重建）、`61384a2`（推送客户端 + 配对 go 键 + 答题震动 + 深链回调 + 横幅升 window 级）、`c561e83`（工程侧 dsbot: scheme 与 entitlements）、`7df694c`（via 标签 + 纯图行）、`411079b`+`2d8d235`（lastChat 存储与保存）、`97496cd`（codespan 汉字间距）、`b993b2a`（push env 补齐 + 冷启恢复与未选回退接线）、`422900b`（token:null 清除语义按裁定落地）。
- **`:84` 按宿主代码改判**：`parts.js:1928-1970` 按 turn 合成单条 steps item，RN 端 foldSteps 为防御性死代码（Chat.tsx:343 三元双枝同值）；原生 stepSummary/expandedSteps 与 openSteps 一一对应 → 一致。
- **`:104` 判定错误已纠正**（Warden 抓出、复核确认）：quote/rule 分支自 `f9ed166`（11-18 11:19）就在，原表判「无对应分支」属取数口径错——按 RN 词表（blockquote / hr）检索没覆盖原生命名（quote / rule）。此为「判缺失必须给出确实没有的落点」规矩的反面教材。
- **`:60` 复核收窄**（写验收判据时发现）：宽度滑杆在窄屏 RN 同样忽略（Chat.tsx:264-271 注释与 `narrow = chatWidth < 520` 自证，固定 0.93/0.86，原生 `da4ec32` 取的正是这组值）——iPhone 上非缺口；真缺的是 **flat 跟随**（Bot 行通栏）与 iPad 级宽屏（≥520pt）的滑杆跟随。缺失→半实现，Mason 该项收窄为 flat。验收判据见 `docs/qa/native-parity-gap-criteria.md`。
- **`ac2e140` 销账两行**（Warden 给的最终 sha，替代 `26f64c4`）：头像上传/移除与新建重名闸转**一致**。amend 后的版本比原版更稳——多了 `avatarBase` 合并逻辑（延迟保存叠加在本会话已写的头像上，形状改选不会复活旧照片）与 BotEditorAvatarTests 4 例，正好堵住「先改形状后保存把照片覆盖掉」这个坑。
- **半实现已分区**（Warden 裁定）：A 组 12 条进下一批（按体感排序，`markSeen` 与 `冷启动页预读` 排末段）；B 组 4 条归档「已知差异」不再派活，`choice 恒分段` 留例外条款——真机见长选项截断则升回 A。
- **自检从严 4 行**：`:36`（恢复定选已接、页预读未跟）、`:81`（文件行缺「扩展名 · KB」副行）、`:85`（sending 态无 0.7 透明度）、`:53`（发送与 dock 展开的震动未跟）。
- 判定变化合计：转**一致** 15 行（`:84 :86 :90 :91 :92 :97 :104 :108 :160 :169 :170 :233 :237 :276 :277`）；转**半实现** 5 行（`:36 :53 :60 :81 :85`）；`:94` 维持半但依据更新；新增**原生超集** 1 行（推送通知开关）。
- 剩余缺失 5 行，验收判据在 `docs/qa/native-parity-gap-criteria.md`：Mason——`bot/not-found`、`附件 send-images 门控`、`选图失败提示`、`flat 跟随`（宽度滑杆 iPhone 非缺口）；Canvas——`创建 token 外链`、`未选模型引导`。落一笔核一笔。
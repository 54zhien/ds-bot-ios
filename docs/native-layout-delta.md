# 原生与布局表的差值（逐屏对照）

对照 `docs/native-layout-map.md` 的 RN 事实；原生行号基于 `native/Sources/DSBot` @ `07e9013`。只记事实与行号，判定只分【一致】【差值】【未实现】，「原生扩展」= RN 没有而原生多出的；不含改法。

## 1. 应用级 chrome

### 头部集群
- 行 gap 8 / paddingH 16 / 底距 8 / 行内顶距 insets.top → ChatViewController:302（spacing=Glass.gap）、:348-349（16）、:350（行高 44）、:347（顶=safeArea）；底距 8 收进 Metrics.headerHeight（DesignTokens:310 = insetTop+44+8）。【一致】
- 左 44 玻璃钮 + 图标 28 + 8pt pending 点（圆心图标右上）→ ChatHeaderViews:58-59 / :66-67 / :71-72、圆心 :69-70；描边 1pt 色随主题（:88 borderColor=p.line、:89 dot=p.accent、:78-80/:92/:94-99 双通道）。【一致】
- 中段 flex:1 minWidth:0 → headerCenter 宽度上限固定 260（ChatViewController:351）。【差值：上限固定 vs 占满中段】
- 中 Pill 44：头像 28（bot 环 p.main / room 环透明）、名字 15/20/500 ink → :25（GlassPill 44）、头像 28 :360-361；头像无环设定（:326-328 仅圆角 14）；名字 15/500（:331），行高未设。【差值：头像环未实现；名字行高未设】
- 右侧 44 侧聊钮或 44 占位 → :338 / :308-310、默认藏侧聊钮 :340。【一致】
- 断连胶囊 30、仅断连出现、转圈/未连接+重试 accent → :39（高 30）、:385-387、:403-411 在线整行隐藏、:376-378 重试 caption semibold accent。【一致】；未配对时胶囊变「配对」入口（:388 文案、:393-395 动作）。【原生扩展（恢复被删导航项的入口）】
- headerShown:false / 按下 0.7 / thin + 1pt rim → ChatViewController:266、ChatHeaderViews:101、:30 ultraThin + :42 border。【一致】

### 抽屉
- 宽 min(85%,340)、右上下圆角=screenRadius → TeamDrawerTransition:28、:116-118。【一致】
- 边缘条 24 / activeOffsetX 8 / failOffsetY ±12 → ChatViewController:1237-1243（起点 ≤24、x>8、|x|>|y|）。【差值：纵向判据为比例式 |x|>|y|，非 ±12 固定】
- 过半或速度 350 开合 → 面板侧 :82-83（<-350 或过半）；边缘侧 :1245-1249（≥80pt 或 >350）。【差值：边缘侧用 80pt 固定距离，非过半】
- 边缘条常驻、enabled 切换不卸载 → :23 注释、:46-47、:61。【一致】
- scrim 0.32、随位移渐变 → :37、:80。【一致】
- 键盘先收再开 → ChatViewController:1212。【一致】
- withSpring + Reduce Motion 直落 → :93-95、:136、:161-163。【一致】
- GEAR_FADE 96 纯色渐隐 p.sidebar → :48-52、:123、DesignTokens:330。【一致】
- footer 齿轮 44+Gear 26 于 gearInset 同心、层级 列表→渐隐→齿轮 → 无 footer 齿轮；设置/新建钮在抽屉内导航栏右上（TeamListViewController:152-170、Gear 26 ink2 :156-157）。【差值：位置与层级不同】
- 抽屉容器 → 内含系统导航栏（title "DS Bot" :143、Done/设置/新建 :166-170）与 UISearchController（:171-175）。【差值：RN 无导航栏与搜索；Done/搜索为原生扩展】

## 2. 聊天页

### 骨架
- 底色 p.main → view.backgroundColor = palette.main，viewDidLoad :239 + 主题刷新 :277。【一致】
- inverted 列表 → 正向 UITableView（ChatViewController:501-510）。【差值：列表方向】
- listContent paddingV 8 paddingH 16；inverted 底距=headerHeight → 行水平 16（ChatMessageCell:99-100/:106-107）、行垂直 4（:104-105）；顶距走 contentInset.top=headerHeight（ChatViewController:464-467，goal 显示时为 0）；底距动态（:1530-1531）。【差值：顶距挂 contentInset；列表级 8pt 垂直 padding 无对应（行 4pt）】
- goal 卡 paddingTop=headerHeight、marginH 12、marginB 6、r16、1pt p.line → 位置 :482-483、边距 :496-497；marginB 无（list.top=goal.bottom :524）；RoomGoalView:65 r16、:66-67 border 1 但色=UIColor.separator、:64 底=secondarySystemBackground。【差值：卡底/线走系统色且为 CGColor 快照；marginB 6 缺】
- toLatest 右 16 底 12、GlassControl 44、离底 >600 → 阈值 :1809；位置 centerX（:578）、底=workStatus-8（:579）；样式系统钮（:569-572 secondarySystemBackground、r20、separator 描边快照）。【差值：居中 vs 右 16；非玻璃钮；系统色】
- 空态 inset24 top28% 头像 64 环 p.main、名 settingsRow600、角色 small、caption mt10 → EmptyChatView:15-16/:42-43/:81/:45/:51-52/:57-61；落位走 layoutGuide（ChatViewController:538-547）。【一致】；RN pointerEvents none 透传——原生含动作钮整块可交互（EmptyChatView:63-70）。【原生扩展（已认可）】
- 加载失败行 → :512-521 系统体/系统色、重试 mt8 :533。【差值：未走 tokens】
- 阻断卡 marginH 12、r16、1pt line、内钮 44/r20/pH16 → BotBlockedView:65-68 r16、线色 separator；边距跟随 composer 边（ChatViewController:1493-1494，休止同心时 ≠12）；钮 caption1 系统（:87-97）。【差值：线色系统快照；边距非固定 12；钮无 44/20/16】

### 消息行
- 用户右胶囊 p.user r18 内距 9×14；Bot 左无底；Bot 块级 p.bubble r18；maxWidth 100%-40 或 width% → r18 ✓（ChatMessageCell:81）、:125-128、:131、:196；内距 8/12（:109-112）；Bot 恒 clear（:131）；maxWidth 0.86（:102/:108）。【差值：内距 8/12 vs 9×14；Bot 块级无 p.bubble 底；0.86 vs 100%-40/width%】
- parts 间 partLine hairline → 无，parts 间 4pt 间距（:97）。【差值】
- 时间戳 stampOf（user 每条 / run 末条 / 房间与本地不带）→ :202-206 判据 localID/inRoom/stampFolded/stampable。【一致】
- 步骤行折叠胶囊 small、展开逐条 → :123-124 居中、:198、:136-141。【一致】
- 图片 1 张 200 / 两列 120 / GAP 6 / tile r18 hairline / 失败 tile 文案 → PhotoGridView:9-20 统一方格（宽/(100+gap)、上限 3 列）、tile r12（:162/:174）、gap=8（:11/:43）、无失败占位文案（:163-167）。【差值：无 200 单张特例；gap 8 vs 6；tile 12 vs 18；无 hairline；无失败文案】
- 文件行 small 500 ink + caption（扩展·KB）→ :183-193 系统 button、p.hover 底、r10、≥44；无副行。【差值】
- settled 卡（全宽 p.card r16 1pt line）→ 全仓无对应行类型。【未实现】
- via 平台标（11/16 r6 hover/ink3）→ 全仓无。【未实现】

### 输入框
- 休止 62 r31 同心 / 底同心 / 键盘 12 → resting 62（DesignTokens:351）、r31（NativeComposerView:50/:234）、restInset=screenR-31（DesignTokens:355-357）、边随 ChatViewController:1508-1515、键盘 -12（:1483/:1514）。【一致】
- 展开 124 起 / cap 46% / 圆角 max(26,R-16) / margin 16 / 底 12 / 文本区=card−14−media−52 内滚 → editing=124（:42）、cap 46%（:216-219）、预算与内滚（:228-235）、margin 16（ChatViewController:1511）；圆角 max(Radius.composer=22, R−16)（:251-255 + DesignTokens:361）。【差值：下限 22 vs RN 26】
- 表面 frost 12 + rim 1pt → iOS26 UIGlassEffect 无 rim（:156-158）；<26 ultraThin/thick + 1pt line rim（:160-163）。【差值：按 SDK 双路径替代单一 frost】
- editing ⇔ 聚焦||有字||附件；单 spring；Reduce Motion → :203-207、:258-262、:259。【一致】
- 发送三态 → :266-273。【一致】
- 阅读器关闭键（居中 44 r20）→ TextReaderViewController:18 右 bar item、:35 dismiss。【差值：位置与形态】
- tokens 缺口备注：composer.tsx 的 14/52/80/64/124 以私有 Layout 常量落在 NativeComposerView:34-43，未入 tokens（Warden 已裁定允许，注释注明出处）。

## 3. 团队列表
- 主 tiles 容器（gap8、margin(4,16,10,16)）→ TeamListViewController:358-360。【一致】
- tile 104 / r.card / paddingH 6 / 名 small600 / 标签 11 ink2 底 p.active r6 → :397 / :396 / :409-410 / :426 / :434-435；内容垂直居中（:407-408）。【差值：tile 无 1pt 透明描边；标签无 p.active 底 r6；paddingT10/B8 未设】
- 行 minHeight52 / 头像 32 / rowName 16-22 / rowPreview 14-20 ink2 / 未读 8 accent 右 → :571 / :574-575 / :607 / :609-610 / :597-600+:615。【一致】
- waiting 徽标 12 accent+白? 外层 16×16 透明隙 → :576-583、:620-621。【一致】
- working 8pt green → workingDot 8pt（:588-589）但全文件未赋 backgroundColor（configure 仅 :619 切 isHidden）。【差值：工作中点当前不可见】
- 空列表 mt40 small ink3 → :337 / :317-318；+ 新 Bot 钮（:321-328）。【一致 + 原生扩展（已认可）】

## 4. 待处理
- 顶距 SHEET_HEAD 66 → 无对应设定（系统 insetGrouped 默认内距）。【差值】
- 分节头（gap8 pH16 + 计数徽 20×20 tag/hover）→ titleForHeaderInSection 系统串（NeedsYouViewController:145-147）。【差值】
- 行 56 / paddingV7 pH16 / 头像 44 环 / 徽标透明隙 / 按下 p.hover → 系统 subtitle cell（:148-156）。【差值：整行为系统样式】
- 空态 mt60 → :131、small ink3 :126-127。【一致】

## 5. 侧聊
- Close 玻璃钮 44 → closeChatButton 为右 bar item（SideChatViewController:43-49，IconView close 28）。【差值：位置与形态】
- 空态 mt30 同占位文案 → :65 / :58-60 / :78。【一致】
- composer 栈 padding 8/12、发送 44 → :75 / :90-91；发送底色 view.tintColor（:87）、r22（:88）。【差值：底色非 tokens accent】
- 条目行 → 系统 subtitle cell（:231-235）+ footer 文案（:221-225）。【差值 + 原生扩展（footer）】

## 6. 设置
- 分节头 caption 11 ink3 大写 inset18 mb6 字距 0.6 上距 16 → SettingsStyle:29-36（字距未设）；头高 38 / gap 22（:49-50）。【差值：字距 0.6 缺；38/22 无 RN 换算出处】
- 卡 marginH16 r.card hairline p.line p.card 底 shadow(1) → insetGrouped 系统卡 + SettingsStyle.prepare:15-22（底 p.main、分隔线 p.line）。【差值：卡描边/阴影未设】
- 行 50 / pH16 v10 / label ink / value 右 ink2 maxW52% / chevron16 ink3 → rowHeight 50（:7/:20-21）、:54、:55-58、:59-63；value maxWidth 未设（系统布局）。【差值：maxW52% 缺】
- 分隔线 hairline 左 16 p.line → :19/:54。【一致】
- 分段（Material26、chip34 r17、选中 1.5pt accent 描边）→ 外观/语言为 value1 行 + 值（NativeSettingsViewController:52-54/:65-67）；仓内 UISegmentedControl 均为系统件（GroupEditor:13、Schedules:158/:165、Pending:296）。【差值：Material 分段未实现】
- 页头浮层 topBar + back chevron 26 ink2 → 系统导航栏 + 系统 back。【差值】
- 输入（高40 r10 1pt line pH12）→ 设置各页输入走系统 alert addTextField（Secrets:82-86、Connector:98、Provider:122/:140）。【差值：无内联输入样式】

## 7. Pair
- 标题在滚动内容、无悬浮头 → PairingViewController:11 title 在系统导航栏，:13/:16 左右 bar 按钮。【差值：标题位置】

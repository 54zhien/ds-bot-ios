# 原生布局表：RN 初版的骨架事实

来源全部是 RN 代码本身，逐条标注文件与行号；只写事实，不写实施建议。
tokens 的值以 `mobile/src/ui/tokens.ts` 为准：`glass = { control: 44, controlSmall: 40, icon: 22, iconLarge: 24, iconXL: 26, pill: 44, gap: 8, margin: 16 }`，`radius = { tag: 4, item: 6, input: 8, row: 10, card: 12, option: 12, dialog: 16, bubble: 18, composer: 22, composerLong: 18, pill: 999 }`，`COMPOSER_RESTING = 62`，`SHEET_HEAD = 66`。

## 1. 应用级 chrome（ShellB.tsx / Drawer.tsx / glass.tsx）

### 头部集群（ShellB.tsx:136-181，样式 :385-387）
- 容器 `styles.header`：absolute、top/left/right 0、zIndex 10（:385）。
- 行 `styles.headerRow`：row、alignCenter、gap 8、paddingBottom 8、paddingHorizontal 16，行内 paddingTop = insets.top（:147、:387）。
- 左：GlassControl 44，内含 SidebarIcon 28、`p.ink2`，带 `dot={pending}`（8pt accent 圆点，圆心在图标右上角，glass.tsx:156）（:148-150）。
- 中：flex:1、minWidth:0。无目标 → 空；有目标 → Pressable 包 `Pill`：GlassPill 高 44（:129），Avatar 28（bot 环 p.main / room 环 transparent，:130），名字 15/20/500 `p.ink`，超长省略（:131、:151）。
- 右：有侧聊 → GlassControl 44 + SideIcon 28（:158-160）；否则 44×44 空占位（:161）。
- 断连胶囊（:163-179）：仅在 `team !== null && !online` 出现；居中列 paddingBottom 6；GlassPill 高 30；`caption`(`p.ink3`) 文案；未断开 = 转圈(small, p.ink3)+「正在重连…」；断开 = 「未连接」+ 重试（caption 600 `p.accent`，热区 minHeight 30、hitSlop 8）。
- 键行为：`headerShown: false`（ShellB.tsx:324）；图标按下 opacity 0.7（glass.tsx:153）；玻璃 intensity thin、1pt 描边（glass.tsx:154、rimSkin）。

### 抽屉（Drawer.tsx:15-105）
- 面板：absolute、left/top/bottom 0、宽 `width`（调用处 ShellB.tsx:354 附近 = min(85%, 340)），右上下圆角 = `screenRadius`，overflow hidden（:93-104）。
- 手势：边缘条宽 24（:15），`activeOffsetX(8)`、`failOffsetY([-12,12])`（:65-66）；面板 pan `activeOffsetX(-8)`（:71）；过半宽或 |速度| > 350 决定开合（:69、:74）；边缘条常驻、用 enabled 切换不卸载（:86、:63-64 注释）。
- scrim：整屏 rgba(0,0,0,0.32)，opacity = (x+width)/width（:76、:103）。
- 键盘先收再开抽屉（:22-24、:29）。
- 打开动画 withSpring(SPRING_SHAPE)；Reduce Motion 直接落位（:36-38）。

### 抽屉 footer 齿轮（ShellB.tsx:32-33、:48-50、:116-120）
- `GEAR_FADE = 44 + 16 + 36 = 96`：纯色渐隐（`GlassFade plain`，`p.sidebar`）盖住列表底（:116）。
- 齿轮 GlassControl 44 + GearIcon 26（`p.ink2`），位置 left/bottom = `gearInset = max(16, screenRadius - 22)`（同心）（:50、:117-119）。
- 层级：列表 → 渐隐 → 齿轮（渐隐在齿轮之下压边缘，齿轮可点，:115-120 渲染顺序）。

## 2. 聊天页（Chat.tsx + items.tsx + composer.tsx）

### 屏幕骨架（Chat.tsx:350-395、样式 :599-610）
- `screen`：flex 1、底色 `p.main`（:352）；无导航栏，头部为 absolute 浮层（见上）。
- 列表：`flex: 1`（:602），inverted（:370）；`listContent` paddingVertical 8、paddingHorizontal 16（:603）；inverted 的 paddingBottom = headerHeight(insets.top)（:375）。
- goal 卡（:355-357、:607）：有 goal 才渲染，容器 paddingTop = headerHeight、zIndex 1；卡 marginHorizontal 12、marginBottom 6、圆角 16、1pt p.line。
- toLatest（:390-393、:606）：absolute right 16、bottom 12（相对输入框区），GlassControl 44 + ArrowDown 24，出现条件滚动离底 > 600（:384）。
- 空态 EmptyChat（:446-455、:605）：absolute、左右 24、top 28%、居中列、pointerEvents none；头像 64（环 p.main）、名字 settingsRow 600、角色 small ink3、caption ink3 marginTop 10。
- 加载失败（:361-365）：错误 caption ink3 + 重试 caption accent marginTop 8，居中列。
- 阻断卡（:608-609、:534-570）：marginHorizontal 12、圆角 16、1pt p.line；内按钮 minHeight 44、圆角 20、paddingHorizontal 16。

### 消息行（items.tsx:86-330、样式 :493-511）
- 不对称（:220-234、:282-291）：用户 = 右对齐胶囊，底 `p.user`、字 `p.userInk`、radius 18、padding 9×14；Bot = 左侧文本，纯文本时无底（flat 布局），带 Markdown 块时 `p.bubble` 底圆角 18、alignSelf flex-start、maxWidth 100%-40 或 prefs.width 百分比（:84-85、:291）；parts 之间 `partLine`（p.line、hairline、flex 1）（:115-117、:497）。
- 时间戳（Chat.tsx:459-467 stampOf）：user 每条带；bot/post 连续同名 run 只在最后一条带；房间与本地行一律不带（:331）。
- 步骤行：`Used N tools` 折叠胶囊，展开逐条（steps 区块），`TypeScale.small` + ink2/ink3。
- 图片网格（:341-346、:504）：1 张 200、多张两列 120 方格，GRID_GAP 6，tile 圆角 18、hairline p.line、底 p.main；失败 tile caption ink3「在电脑上查看」。
- 文件行（:91-94）：`type.small` 500 p.ink 文件名 + caption ink3（扩展名 · KB）。
- settled 卡（:137-199、:498）：全宽、p.card 底、radius 16、1pt p.line。
- via 平台标（:258、:511）：11/16、paddingH 6、圆角 6、p.hover 底 ink3 字。

### 输入框（composer.tsx:29-133、:160-190）
- 休止：高 62、圆角 31（胶囊）、左右 inset = 同心 `screenR - 31`、底 inset 同值；键盘弹起 12。
- 展开：底高 124 起按内容、cap = 46% 屏高、圆角 max(26, screenR - 16)、左右 margin 16、底 12；文本区 maxHeight = cardHeight − 14 − media(80) − 52，超出内滚；控制栏 52 预算，加号/发送 44 永不被挤出。
- 表面：BlurView intensity 12 tint default（中性 frost，:43-44）；rim 1pt。
- 状态：editing ⇔ 聚焦 || 有字 || 有附件（:82-85）；插值 height/radius/margins/inset 单 spring（SPRING_SHAPE）驱动（:100-129）。
- 发送键：可发 accent 玻璃 / 不可发 dim / 运行中方块停止（:130-132）。

### 阅读器（Chat.tsx:610）
- 关闭键：absolute 居中、minHeight 44、paddingHorizontal、圆角 20。

## 3. 团队列表（TeamList.tsx）

- 主 Bot tiles（:146-148）：行 gap 8、paddingHorizontal 16、上 4 下 10；tile 宽 104、paddingTop 10、paddingBottom 8、paddingHorizontal 6、圆角 radius.card、1pt transparent 描边；名字 small 600 ink、标签 11/15 ink2 底 p.active 圆角 6。
- 行（:149-153）：row minHeight 52、paddingVertical 6、paddingHorizontal 8、marginHorizontal 8、圆角 10、gap 10；头像 32；名字 rowName 16/22、预览 rowPreview 14/20 ink2；未读 8pt accent 点右对齐。
- 徽标（:127-130、:152-153）：waiting 12pt accent 圆 + 白 ?，外层 16×16 纯透明间隙、right/bottom = round(size*0.02)；working 8pt green。
- 空列表（:92）：small ink3 居中 marginTop 40（team===null 才显字，载入后空 = 空）。

## 4. 待处理页（NeedsYou.tsx:53-87）

- SectionList、contentContainer paddingTop = SHEET_HEAD(66)（:55）。
- 分节头（:58-67、:85-86）：row gap 8、paddingHorizontal 16、paddingTop 头部；计数徽 20×20、圆角 radius.tag、底 p.hover。
- 行（:70-72、:87）：row、alignCenter、gap 12、minHeight 56、paddingVertical 7、paddingHorizontal 16；头像 44（环 p.main、waiting/working 徽标走透明间隙）；按下 p.hover。
- 空态（:79）：small ink3 居中 marginTop 60。

## 5. 侧聊（side.tsx:76-127）

- 条目行含 Close 玻璃钮 44（:76）；无聊天时 small ink3 居中 marginTop 30（:95）；输入区 composer 栈：padding 8/12、发送 44。
- 占位与列表标签同文案「问问目前做到哪了」（:90、:127）。

## 6. 设置（Settings.tsx / settings-pages.tsx）

- 分节（Settings.tsx:48-53、:97-99）：label caption 11 ink3、paddingHorizontal 18、marginBottom 6、大写 letterSpacing 0.6；上距 16。
- 卡（:97）：marginHorizontal 16、radius.card、hairline p.line、p.card 底、shadow(1)。
- 行（:99）：row、paddingHorizontal 16、paddingVertical 10、minHeight 50、gap 10；label settingsRow ink；value 右对齐 settingsRow ink2、maxWidth 52%；chevron 16 ink3。
- 分隔线（:98）：hairline、marginLeft 16、p.line。
- 分段（:24-35、:100-102）：Material 26、p.hover 底；chip 高 34、圆角 17、选中 1.5pt accent 描边。
- 页头（settings-pages.tsx:28-33）：backBtn chevron 26 ink2、topBar 浮层。
- 输入（:192-204）：高 40、圆角 10、1pt p.line、paddingHorizontal 12、settingsRow ink、placeholder ink3。

## 7. Pair

- 无悬浮头，标题在滚动内容里（Pair.tsx；此前裁定：不做渐隐）。

---
行号对 `mobile/src/` 下文件；tokens 值见文首。此表只记录 JSX 事实，实现顺序与取舍另议。

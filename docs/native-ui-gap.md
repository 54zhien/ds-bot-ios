# 原生界面与 RN 的差距清单（真机截图得出）

来源：用户在 `deb52f4` 包上的实机截图（已配对、状态在线、无 Bot）。只记有证据的项；标「待核」的是我按代码读出来的，尚未在 RN 源码里逐条对上。

## 有截图证据的

1. **顶部状态条**：整宽灰底条，永远占一整行视觉重量。RN 里连接状态是极轻的一行（`screens/Chat.tsx` 的 status 区，待核），不该和导航栏抢注意力。
   - 已关闭：31f3913 先收敛为在线即隐；d23361c 重做为标题下方 30pt 玻璃胶囊，仅断连/重连出现。RN 侧已核：ShellB.tsx:140-179（标题下的断连 GlassPill）。
2. **导航栏左侧**：抽屉图标是蓝色线框方块，不是 RN 的原版图标（`nav/Drawer.tsx` 的入口）。
   - 已关闭：0028fca（图标按 RN glyph 路径自绘）+ 6257eb7（按钮描边上色）；d23361c 后入口为 44pt 玻璃钮。
3. **导航栏右侧**：「电脑」是文字胶囊按钮，比页面内容更跳。RN 里入口在抽屉与设置里（待核）。
   - 已关闭：d23361c——「电脑」文字胶囊随系统导航栏一并移除，右侧按 RN 为侧聊玻璃钮或 44pt 占位（sideControl/sidePlaceholder）。
4. **标题**：系统灰的「对话」，不可点。RN 里这个位置是可点的当前目标名 + 下拉切换（待核）。
   - 已关闭：d23361c——标题/headerCenter 为可点胶囊，显示当前 Bot/群名（色点头像 + 名字），点击 showDetails 打开对话详情（ChatViewController:313、:1292）；未命名时禁用。
5. **空态**：只有一句「还没有 Bot」，无引导、无创建入口。RN 的空态有主 Bot tile 与创建入口（`screens/TeamList.tsx`）。
   - 已关闭：e7d9be2（聊天/团队列表/待处理/侧聊四屏空态）+ ae723e6 接线。
6. **语言**：中文界面里输入框占位是英文 `Message`。`NativeLanguage` 只覆盖了一部分键，输入框与状态条文案要补进词典。
   - 已关闭：453252e（输入框占位走词典）；其余界面英文随后清完：9c2993d、8952db0、8837fcd、f7f3283、564910f、2966e08、7481ed4、4271187。
7. **整体层次**：没有背景、没有卡片、没有渐隐层，所有控件都是未调过的系统默认外观。
   - 基本关闭：29270c9 起逐屏改走 tokens，b40299e 接入用户主题；d23361c 悬浮玻璃头部、67e11e8 顶部渐隐、26fc43c 抽屉玻璃、9317677 输入框液态同心、fa0ea9c 起设置系列。剩 Location/FolderPicker 两页改动在本地待提交（等 main 恢复绿）。

## 结构性问题（代码层面）

- `ChatViewController.swift` 原本 1652 行，界面与数据混在一起；`c8f8aa0` 已把 `PhotoViewController`/`TextReaderViewController`/`ChatMessageCell`/`PairingViewController` 拆出。
- `DesignTokens.swift`（`29270c9`）已逐值搬 `mobile/src/ui/tokens.ts`。~~目前零引用~~ 已过时：b40299e 建 ThemeStore 后全仓取色走 `ThemeStore.palette(trait:)`；「每改一屏先换 tokens、缺的值补进 tokens」的规矩不变。
- 抽屉的玻璃与渐隐层在 RN 期定过（玻璃只用于悬浮层与控件、胶囊 1pt 描边、控件层级高于渐隐层、内容在渐隐层下），26fc43c 已照此实现。

## 顺序建议

先输入框（用户每天用、也最能体现手感）→ 团队抽屉与列表 → 聊天页导航与状态条 → 消息气泡与 Markdown 视觉 → 其余设置页。每屏一提交，编译与测试一律以 GitHub Actions 为准。

> 2026-11-18：该顺序已走完一轮（453252e → 26fc43c/73a237a → d23361c → 1eecf6e/ca90494 → fa0ea9c 起的设置系列）。后续搬迁以 `docs/native-layout-map.md` 为准。

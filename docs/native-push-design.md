# 原生真推送：客户端设计（N3）

状态：已实现，本地提交，未推送。宿主侧（APNs 发送、证书/密钥）与工程侧（entitlements、`UIBackgroundModes: remote-notification`、`aps-environment`）由 Warden 另派，本文不覆盖。

## 0. 架构一句话

宿主电脑直接向 APNs 发推送；payload **只带路由，不带正文**——`aps.alert` 是通用文案（如「{Bot 名} 有新消息」），另带 `roomId`/`botId`/`kind` 若干自定义键。手机收到后自己打开对应对话，正文走现有加密 link 拉取。正文不经过 Apple，所以 **NSE 不做**（`s2-drafts/` 的 NSE 草稿继续挂着：不进 main、不属于 RN 对齐范围）；也不引入任何第三方推送 SDK。

## 1. 权限申请时机

**唯一入口是设置页的「推送通知」开关。** 打开开关即调 `requestAuthorization`（`.alert .badge .sound`）；用户在系统弹窗点「不允许」则开关回弹、intent 落 `off`，全程静默，没有错误弹窗。启动路径**从不**主动问权限：`bootstrap()` 只在 intent 已是 `on` 时重注册。

- 落点：`native/Sources/DSBot/NativeSettingsViewController.swift`（开关行 + `changePush`）、`native/Sources/DSBot/PushCenter.swift`（`setEnabled`）。
- 存储：`UserDefaults "dsbot.push"`（`on`/`off`），与「应用内横幅」的 `dsbot.banners` 互不相干，两个开关各管各的。
- 已知边界：用户先开开关、之后去系统设置里关权限，intent 仍为 `on`，推送会继续到达但不展示。属可接受噪音，不做运行时对账。

## 2. Token 上报

- **获取**：`AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` → 十六进制串，持久化 `UserDefaults "dsbot.push.token"`，去重后只报差异。
- **上报走现有加密 link**：`BotAPI.call("push-token", payload: { token, env, bundleId }, on: session)`——三个字段对齐宿主已落地契约（`docs/host-push.md` §1，全必填）：`token` 64 位 hex，`env` 取 `{sandbox, production}`（运行时默认 `production`，In-House 只有这一种；`DSBotPushEnvironment` Info.plist 键是留给 Debug 装机的后门，`development` 映射 `sandbox`），`bundleId` 运行时取。这是 `bot` RPC 方法下的**新端点**，`api`（API_VERSION）保持原值——新旧电脑靠 **hello 能力协商**区分：只有 `hello.capabilities` 含 `"push-token"` 的宿主才会收到上报，老宿主永远听不到这个端点。
- **时机**：`ChatViewController.checkComputer` 里 hello 校验通过后调 `PushCenter.hostOnline(hello:session:)`，此刻挂 session 并补报当前 token；重连（`connect` 换新 session）先 `hostOffline()`，等新 hello 再报。token 早于 link 在线时到达的场景由持久化 + `hostOnline` 补报覆盖。
- **关即清除（Warden 已裁）**：关开关时 `push-token` 照常发一条 **`token: null`**，`env`/`bundleId` 保持必填形状——宿主第 2 批接受 null 即清除并落一行「device X 请求停止推送」日志；用户关的是明确意图，必须真停，不靠 410 慢慢失效。手机侧同时 `unregisterForRemoteNotifications()`（**关掉就是真的不注册**，下次启动 `bootstrap()` 也不注册）。过渡期：宿主第 1 批会把 null 按 `bot/invalid` 拒掉，客户端静默吞掉，本地 unregister 照样成立。
- **静默降级**：`didFailToRegister`（模拟器、没 entitlement）只留空实现；上报失败 `try?` 吞掉。拿不到 token 的每一种路径都不弹错。
- 落点：`AppDelegate.swift`、`PushCenter.swift`（`deviceToken`/`reportToken`/`hostOnline`/`hostOffline`）、`ChatViewController.swift`（`checkComputer` 挂钩、`connect` 重置）。
- `bundleId` 随 token 一起报，取值是**运行时 `Bundle.main.bundleIdentifier`**（`PushCenter.swift` 的 `reportToken`），**别让后来人改成写死常量**：这份 IPA 交付时未签名、用户重签会带进自己的 bundle id，APNs 的 `apns-topic` 必须跟着它变——宿主侧一律按客户端上报的 `bundleId` 发。原生默认包名 `io.github.fei2411.dsbot.native` 只是当前构建的值，宿主从 token 推不出这个字段。

## 3. 前台抑制

`willPresent` 恒返回 `[]`：前台永远不弹系统横幅。App 在前台时 link 在线，正文与通知本来就走加密通道进界面（应用内横幅已对齐 RN，且已提到 **window 级**——见 §6 附带项）。宿主侧应避免在「手机 link 在线」时发推送，这条属宿主职责，客户端不替它判断。

- 落点：`PushCenter.swift`（`willPresent`）、`NoticeOverlay.swift`。

## 4. 点击 / 冷启动路由

- **路由键**：payload 里 `roomId`（房）优先，否则 `botId`（Bot）；`kind` 仅供宿主侧记账，不影响落点。显示名由手机从 team state 解析，payload 不带名字。
- **路径**：`didReceive` → `PushCenter.openChat` 闭包 → `ChatViewController.openPushTarget` → `route(to:)`：若当时有 sheet 盖着（设置页等），先 `dismiss` 再 `selectTarget`，用户落在他被指到的那场对话。
- **冷启动**：delegate 必须在 `didFinishLaunching` 里装好（`bootstrap()` 在 `AppDelegate` 第一步），冷启动点击的系统投递发生在启动完成后、走同一个 `didReceive`——装晚了就丢。**事实核对**：`launchOptions[.remoteNotification]` 只携带静默推送（`content-available`），本设计不用静默推送，也不在 `didFinishLaunching` 里读它；Warden 提的「didFinishLaunchingWithOptions 里拿得到」对 alert 点击这条路径不成立，冷启动点击走的是 delegate，不是 launchOptions。这条要按 §7 的冷启动用例单独测。
- **未配对时的点击**：路由照样执行，`selectTarget` 会把聊天切到目标并显示离线/配对提示，不崩、不白屏。
- 落点：`PushCenter.swift`（`didReceive`/`route`）、`ChatViewController.swift`（`openPushTarget`/`route(to:)`）、`AppDelegate.swift`。

## 5. Badge 策略

宿主拥有数字：它在 `aps.badge` 里写未读计数（payload 仍是路由+计数，无正文）。手机只负责清零：`sceneDidBecomeActive` 时 `setBadgeCount(0)`。前台化必然经过 active，点击路由必然前台化，所以不需要在路由里再清一次。

- 落点：`SceneDelegate.swift`（`sceneDidBecomeActive`）。

## 6. 本轮附带落地（Warden 加派与此前裁定的项）

0. **`dsbot://pair` 深链**（Warden 加派；RN `Pair.tsx:34-38` + `App.tsx:104-110`）：`SceneDelegate` 接了 `scene(_:openURLContexts:)` 与冷启动 `connectionOptions.urlContexts`，两者都过同一个 `handlePairingURLs`，落进 `ChatViewController.openPairingURL` → 复用配对 sheet（成功后由既有的 pendingOffer 分支自动关 sheet，坏链接在 sheet 里解释，与 RN 把错误画进 Pair 屏同构）。**前置缺口：`project.yml` 还没注册 `CFBundleURLTypes`（`dsbot` scheme），那是工程侧文件，归 Warden；没有它 iOS 永远不会投递这个 URL，两个回调都收不到。**
0b. **配对输入框 `returnKeyType = .go`**（RN `Pair.tsx:55`）：`PairingViewController` 的 field 加了 `.go` 与 `UITextFieldDelegate`，回车即 `submit()`；解析失败键盘保持，错误就在输入框正下方。
0c. **冷启动恢复上次对话——已接线**：Mason 落了 `LastChatStore`（`native/Sources/DSBot/LastChatStore.swift`，键 `dsbot.lastChat`；`save` 已由他挂进 `selectTarget`）。我接读侧：`ChatViewController` 首次 `state` 落地、选定初始目标处调 `restore(stillKnown:)`，用 team state 判存活，失效自动清键、回退主 Bot；显示名从 team 数组回填（存值不带名）。恢复只跑一次（`restoredLastChat` 旗标），重连路径（`reconnectTarget`）优先。

1. **应用内横幅升到 window 级**（`NoticeOverlay.swift`）：passthrough 容器挂 key window 最上层，`point(inside:)` 只认横幅自身，重复调用幂等，palette 走 `ThemeStore.changed` 重取，顶距 safeArea+8，不随键盘移动。前台抑制之所以「交给已有的横幅」，前提就是这条。
2. **答题/审批成功震动**（`PendingDockView.run`）：`answer-question`/`approval-answer` 成功给一次 `notificationSuccess`，对应 RN `dock.tsx:87,130`；RN 对 reject 用 Warning，按裁定统一 Success，不撒别处。

1. **应用内横幅升到 window 级**（`NoticeOverlay.swift`）：passthrough 容器挂 key window 最上层，`point(inside:)` 只认横幅自身，重复调用幂等，palette 走 `ThemeStore.changed` 重取，顶距 safeArea+8，不随键盘移动。前台抑制之所以「交给已有的横幅」，前提就是这条。
2. **答题/审批成功震动**（`PendingDockView.run`）：`answer-question`/`approval-answer` 成功给一次 `notificationSuccess`，对应 RN `dock.tsx:87,130`；RN 对 reject 用 Warning，按裁定统一 Success，不撒别处。

## 7. 测试矩阵（macOS / 真机，放行后跑）

前置：Warden 的工程侧已加 `aps-environment` + `UIBackgroundModes: remote-notification`，宿主侧已实现 `push-token` 端点与发送。

| # | 用例 | 步骤 | 期望 |
|---|---|---|---|
| 1 | 开关即问 | 设置 → 打开「推送通知」 | 系统弹权限一次；同意后开关保持开 |
| 2 | 点「不允许」即退 | 同上，选「不允许」 | 开关回弹为关，无错误弹窗 |
| 3 | token 上报 | 同意后宿主 `push-token` 请求 | payload 带 hex token 与 `io.github.fei2411.dsbot.native` |
| 4 | 关掉真不注册 | 关闭开关 → 杀进程重开 | `registerForRemoteNotifications` 不再被调；宿主收到 `token: null` |
| 5 | 前台抑制 | 前台在线时宿主发一条 | 无系统横幅；正文照常进聊天流 |
| 6 | 点击路由 | 后台收到 → 点横幅 | 打开对应 Bot/房间对话；若设置页开着先关掉它 |
| 7 | **冷启动** | 杀进程 → 收推送 → 点横幅 | 启动后落在对应对话（delegate 在 didFinishLaunching 已装好） |
| 8 | sheet 之下 | 设置 sheet 开着时来 notice | window 级横幅可见，点击关 sheet 进对话 |
| 9 | 旧宿主 | 电脑不含 `push-token` capability | 一切照旧，无报错、无上报 |
| 10 | badge | 宿主发 `badge: 3` 后前台化 | 角标清 0，宿主下次推送重算 |

CI 侧：`ios-native.yml` compile job 会在推送后自动编译 Swift 树；`ios-native-smoke.yml` 会真机模拟器起一次主屏。**本轮本地无 macOS，编译与全部用例未跑**，以上矩阵待放行后验证。

## 8. 不做清单

- APNs 证书/.p8/Key ID 管理（宿主侧管，不在本仓库客户端）。
- NSE、`mutable-content`、推送内解密（`s2-drafts/` 草稿原样挂起：不进 main、不属于 RN 对齐范围）。
- 第三方推送 SDK。
- `project.yml`（entitlements / background modes / aps-environment）——Warden 另派。

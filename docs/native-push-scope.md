# N3 推送范围裁定：RN 侧到底有没有"真推送"

状态：初稿为只读裁定。**2026-11-19 改派：用户明确要真推送，N3 从收口升级为立项**，本文"不做 APNs"的结论被推翻；现行方案见 `docs/native-push-design.md`（宿主直发 APNs、payload 只带路由、不做 NSE）。RN 事实盘点部分仍有效。

口径：用户定调「先功能后视觉，功能一个都不能少」。因此 N3 的范围以 **RN（mobile/）现有功能**为准，RN 没有的功能不进"一个都不能少"的清单。

---

## 0. 一句话结论

**RN 侧从来没有过真推送**：没有 expo-notifications、没有 APNs 注册、没有 NSE，"通知"在这个 App 里只有三样东西——一个「In-app banners」设置开关、一条应用内横幅、答题/审批成功时的震动反馈。原生侧已实现前两样。~~N3 按"设置项 + 应用内横幅"收口即可~~（已被 2026-11-19 改派取代：真推送立项，见 `docs/native-push-design.md`）。

---

## 1. 检索方法（可复现）

以下命令在仓库根 `ds-bot-ios/` 下执行；空结果同样列在"命中"里，证明是查过而不是没查。

```sh
# 1. RN 源码里的推送痕迹（含 Haptics / banner / APNs）
grep -rniE "expo-notifications|registerForRemote|UNUserNotification|deviceToken|pushToken|apns|APNs" mobile/src mobile/App.tsx mobile/index.ts
#   命中：0 条

# 2. 通知相关的 UI 词条与横幅
grep -rniE "otification|banner|Haptics" mobile/src
#   命中：见 §2 逐条 file:line

# 3. 依赖清单
grep -E "expo-notifications|expo-haptics|expo-device" mobile/package.json
#   命中：expo-haptics 一条；expo-notifications / expo-device 为 0 条

# 4. app.json 的推送配置位
grep -nE "aps-environment|UIBackgroundModes|remote-notification" mobile/app.json
#   命中：0 条（expo.plugins 里也没有任何推送插件）

# 5. 原生侧的通知/横幅/震动
grep -rniE "banner|UNUserNotification|aps-environment|remote-notification|UIBackgroundModes" native/Sources
grep -rniE "Haptic|FeedbackGenerator|FeedbackType" native/Sources
grep -nE "entitlement|aps|background|push" native/project.yml
#   命中：见 §3；震动为 0 条；project.yml 无任何推送能力声明

# 6. 历史草稿（仓库外，与 main 无关）
ls -R ../s2-drafts
#   命中：NSE 设计稿与 plugin 草稿，从未合入 main（git -C . log 无任何 push/NSE 提交）
```

---

## 2. RN 侧有什么（mobile/，全部 file:line）

### 2.1 应用内横幅（唯一的"通知"UI）

| 环节 | 位置 | 行为 |
|---|---|---|
| 组件本体 | `mobile/src/nav/ShellB.tsx:272-313` | `NoticeBanner`，挂在 Shell 根部，壳内任何屏之上 |
| 触发条件 | `ShellB.tsx:292` | feed 事件 `notice`，且 `kind` 为 `question` 或 `approval`，且开关打开 |
| 开关读取 | `ShellB.tsx:280-286` | `readPrefs().banners !== 'off'`（默认开），并订阅 `onPrefsChange` 实时跟随设置 |
| 当前聊天跳过 | `ShellB.tsx:295-297` | 屏上正在看的聊天就是目标聊天时不弹（屏幕上已有自己的卡片） |
| 自动消失 | `ShellB.tsx:303` | 8 秒，seq 守卫防止新旧横幅互相误清 |
| 点击行为 | `ShellB.tsx:310` | `openChat(navigation, target)`，横幅清空 |

### 2.2 设置项

| 环节 | 位置 | 行为 |
|---|---|---|
| 开关行 | `mobile/src/screens/Settings.tsx:79` | 「In-app banners」Switch，读写 `prefs.banners`（`on`/`off`） |
| 存储实现 | `mobile/src/store.ts:94-106` | `readPrefs` / `writePrefs` / `onPrefsChange`，走 SecureStore 持久化 |

### 2.3 触觉反馈（与"通知"相邻，RN 里明确挂在答题/审批上）

| 位置 | 行为 |
|---|---|
| `mobile/src/screens/chat/dock.tsx:87` | 答题成功 `Haptics.notificationAsync(Success)` |
| `mobile/src/screens/chat/dock.tsx:130` | 审批 allow→Success、reject→Warning |
| `mobile/src/screens/chat/dock.tsx:35` | dock 展开 `selectionAsync` |
| `mobile/src/screens/Chat.tsx:289`、`composer.tsx:65` | 发送消息 `impactAsync(Light)` |

### 2.4 词条与负面事实

- 词条：`mobile/src/ui/i18n.ts:143` 有 `'In-app banners'` 和 `'Notifications'` 两条。**后者在全 RN 源码里没有任何 UI 引用，是死词条**，不代表功能。
- 负面事实（§1 命令 1/3/4 全空）：无 expo-notifications、无 APNs 注册、无 deviceToken、app.json 无 `UIBackgroundModes`/entitlements/推送插件。`package.json` 依赖里只有 `expo-haptics`（服务于 §2.3，不是推送库）。

---

## 3. 原生侧现在有什么（native/，全部 file:line）

### 3.1 应用内横幅：已实现

| 环节 | 位置 | 行为 |
|---|---|---|
| 控件声明 | `native/Sources/DSBot/ChatViewController.swift:108` | `noticeBanner: UIButton` |
| 事件路由 | `ChatViewController.swift:748` | feed 事件 `notice` → `showNoticeBanner(data)` |
| 布局配置 | `ChatViewController.swift:791-810` | 顶部悬浮、圆角 12、描边、safeArea+8 |
| 显示逻辑 | `ChatViewController.swift:812-839` | 同一套 guard：开关非 `off`、kind 为 `question`/`approval`、当前 `selectedTarget` 即目标时跳过；8 秒消失，generation 守卫 |
| 点击行为 | `ChatViewController.swift:841-846` | `selectTarget(target)` 跳去对应聊天，横幅清空 |

### 3.2 设置项：已实现

| 环节 | 位置 | 行为 |
|---|---|---|
| 开关行 | `native/Sources/DSBot/NativeSettingsViewController.swift:56-63` | 「In-app banners」UISwitch，读 `UserDefaults "dsbot.banners"` |
| 写入 | `NativeSettingsViewController.swift:153-154` | 开/关写 `"on"/"off"` |

### 3.3 词条与负面事实

- 词条：`native/Resources/zh.json:788` 有「应用内横幅」；`:1018` 同样有 `"Notifications": "通知"`——**native Sources 里同样没有任何引用，两侧对称的死词条**。
- 负面事实：全 `native/Sources` 无 `UIFeedbackGenerator`/任何 Haptics（§1 命令 5 第二条 0 命中）；`native/project.yml` 无 entitlements、无后台模式、无推送 capability，且 `CODE_SIGNING_ALLOWED: NO`（`native/project.yml:13`）；`AppDelegate.swift` 全文 19 行，无任何远程通知注册。

---

## 4. 差在哪

### 4.1 核心范围：原生已对齐

RN 的"通知"两件套（设置开关 + 应用内横幅）在原生侧**都已存在且语义逐点对齐**：同样的 kind 过滤、同样的开关键（`banners`/`dsbot.banners`）、同样的"正在看的聊天不弹"、同样的 8 秒、同样的点击跳转。核心范围**没有欠账**。

### 4.2 两个对齐确认项（已裁定并落地）

1. **横幅的层位置——判为缺口，已修。** 原生横幅原是 `ChatViewController.view` 的子视图，设置 sheet 一盖就被埋住。已升为 window 级 overlay（`native/Sources/DSBot/NoticeOverlay.swift`）：passthrough 容器挂 key window 最上层、`point(inside:)` 只认横幅自身、幂等挂载、`ThemeStore` 重取 palette、safeArea+8、不随键盘移动；点击先关掉挡在前面的 sheet 再进对话（`ChatViewController.route(to:)`）。
2. **通知触觉反馈——已落。** `PendingDockView.run` 在 `answer-question`/`approval-answer` 成功时给一次 `UINotificationFeedbackGenerator().notificationSuccess()`，对应 RN `dock.tsx:87,130` 两个调用点；RN 对 reject 用 Warning，按裁定统一 Success。发送/dock 的 `impactAsync/selectionAsync` 属于交互手感批次，不随 N3。

### 4.3 不构成范围的

- 两侧的 `'Notifications'` 死词条（`mobile/src/ui/i18n.ts:143`、`native/Resources/zh.json:1018`）：无功能对应，删不删都不影响"功能一个都不能少"。若 N3 收口，顺手清理即可。

### 4.4 明确不做的：APNs / NSE

RN main 从未接过任何 APNs/NSE 功能（§1 命令 1/3/4 全空），所以它不在"一个都不能少"的范围里。`../s2-drafts/` 里的 NSE 设计稿与 plugin 是 **S2 愿景草稿**（端到端加密推送，`s2-drafts/docs/2026-11-15-push-nse.md`）——**不进 main、不属于 RN 对齐范围**，别删也别合并；原地挂起，S2 立项与否另议。现行真推送方案（payload 只带路由）同样不需要它。

---

## 5. 给 Warden 的裁定选项

- **收口**：N3 = §4.1（已完成）+ §4.2 两个确认项（横幅层可见性修一次 + 一条通知震动）。做完即收口。
- **立项另算**：若要把 §4.4 的 APNs/NSE（S2 愿景）提上日程，那是独立立项，依据是 `docs/s2-push-readiness.md` 的后台与 CI 准备清单，与 N3 无关。

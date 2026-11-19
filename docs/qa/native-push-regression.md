# 推送回归风险表（`80183f0..HEAD`，九笔待推提交）

核对范围：`80183f0..2f37c91` 共 **11 笔**提交（`9198c56`…`2f37c91`）。审查开始时 origin 停在 `80183f0`、这 11 笔在本地待推；核完后 origin 已推进到 `2f37c91`，即本表覆盖的正是这批。只审推送相关代码，四项：注册/注销时机、`env` 取值、`token: null` 清除、冷启动与深链路由。

**先给最强的结论**：以下七个文件在这段区间里**零改动**（`git diff --stat` 为空）

`PushCenter.swift`、`AppDelegate.swift`、`SceneDelegate.swift`、`LastChatStore.swift`、`NoticeOverlay.swift`、`NativeSettingsViewController.swift`、`PairingViewController.swift`

所以四项里的三项（注册时机、env、null 清除）**代码层面不可能被这九笔改变**；唯一需要逐行看的是被 `ChatViewController` 改动波及的挂载点与路由顺序。逐条如下。

## 1. 注册 / 注销时机

| 检查点 | 结论 | 依据 |
|---|---|---|
| `bootstrap()` 在 `didFinishLaunching` 第一步 | 无影响 | `AppDelegate.swift:12` 未改；该文件零 diff |
| 开开关 → `requestAuthorization` → `registerForRemoteNotifications` | 无影响 | `NativeSettingsViewController.swift:175` 未改 |
| 关开关 → `unregisterForRemoteNotifications` + `reportToken(nil)` | 无影响 | `PushCenter.disable()` 未改 |
| 每次 hello 后 `hostOnline` 挂 session 并补报 | 无影响（调用点位置未变） | `ChatViewController.swift:973`；hello 块里新增的 `composer.canAttach` 在它上一行（`:971`），只写 composer 字段，不碰 PushCenter |
| `connect()` 开头 `hostOffline()` 重置 | 无影响 | `ChatViewController.swift:748`；同一块新增的 `composer.canAttach = false`（`:750`）与推送无关 |
| 是否出现重复注册/重复补报 | 无 | 全仓 `PushCenter.` 调用点共 9 处，逐个核对：`bootstrap`/`deviceToken`/`registrationFailed`/`setEnabled` 各 1，`openChat` 赋值 1，`hostOnline` 1，`hostOffline` 1，无新增调用点 |

## 2. `env` 取值

| 检查点 | 结论 | 依据 |
|---|---|---|
| `DSBotPushEnvironment` 映射与默认 `production` | 无影响 | `PushCenter.environment` 未改（文件零 diff） |
| 是否有新代码改 `Info.plist` / bundle id | 无 | 九笔只动 Swift 源码与测试，未碰 `project.yml`、`Support/` |

## 3. `token: null` 清除路径

| 检查点 | 结论 | 依据 |
|---|---|---|
| 关开关是否仍发一条 `token: null` | 无影响 | `PushCenter.disable()` 未改 |
| 是否有第二个调用点会在别的时机发 null | 无 | `reportToken(nil)` 全仓唯一调用点在 `disable()` |

## 4. 冷启动与深链路由

| 检查点 | 结论 | 依据 |
|---|---|---|
| 冷启动点击（delegate 在 `didFinishLaunching` 装好） | 无影响 | `AppDelegate` 零 diff |
| `dsbot://pair` 热启与冷启两条回调 | 无影响 | `SceneDelegate` 零 diff；`handlePairingURLs` 未改 |
| 推送点击 → `openPushTarget` → `route(to:)` → `selectTarget` | 无影响 | `openPushTarget`/`route(to:)`/`openPairingURL` 均不在 `80183f0..HEAD` 的 diff 里 |
| `selectTarget` 被改动后的副作用 | 无害，且更正确 | 新增两处：开头 `scrollOffsets.keep`（`:1523`）、`autoSelectedTarget = false`（`:1531`）。`LastChatStore.save(target)` 仍在原位置且全仓仅此一处（`:1528`），不会重复写 |
| 恢复路径与推送点击的先后 | 两条次序都正确 | 推送先到：`selectTarget` 置 `selectedTarget`，首次 state 落地时恢复块因 `selectedTarget != nil` 跳过（`:1070`）；恢复先到：随后推送点击经 `selectTarget` 覆盖。两种次序都不会回退到主 Bot |
| 恢复块的改动 | 增强，非风险 | 恢复成功时新增 `autoSelectedTarget = true`（`:1076`）；配合 `:277-284` 的 `onTargetInvalid`，被删的恢复目标会回退主 Bot。`autoSelectedTarget` 在回落时置 false，不会二次触发（`:281`） |

## 需要记进验收单的行为变化（不是缺陷）

- **点进一个已被删除的会话**：`route(to:)` → `selectTarget` 把 `autoSelectedTarget` 置 false，随后 `refreshLatest` 收到 `bot/not-found` 时只置 `gone`、清 `LastChatStore`，`onTargetInvalid` 因非自动选择而提前返回（`:1206-1208`）。结果是**用户停在一个空会话上，不自动跳往主 Bot**。这是 `c17173c` 明确写下的设计（读者自己点的目标不挪动），与推送无关，但真机验收若从推送点进已删会话会看到空会话，应记作预期而非故障。
- `bot/not-found` 时清 `dsbot.lastChat`（`:1204`）：下次冷启动不会落回该会话，回退主 Bot——与 RN `ShellB.tsx:194` 一致。

## 附带（非推送，但属我此前落地的一项）

- `PendingDockView.run` 的震动从「统一 Success」细化为 `answer-question → .success` / `approval-answer → allow?.success:.warning`（`PendingDockView.swift:294-301`），与 RN `dock.tsx:87,130` 逐点一致，`switch` 保证每次只响一记，无重复触发。

## 结论

四项逐条核过：**注册/注销时机、`env` 取值、`token: null` 清除三者在代码层面未被这九笔触及（相关文件零 diff），冷启动与深链路由的入口与顺序未被绕开或重复触发**。唯一需要写进验收单的是「点进已删会话停在空会话」这条既有设计，避免验收时误判。

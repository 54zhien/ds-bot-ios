# 原生推送：可执行验证清单

配套 `docs/native-push-design.md` §7。标准：拿着本文，不需要问任何人，一条条打勾。模拟器组（A）今天就能跑；真机组（B）等 Relay 的发送器（宿主第 2 批）落地后执行；C 组是反例与边界，防止后来人踩回旧坑。

**通用前提**

- 模拟器：`xcrun simctl boot "iPhone 16"`，Xcode 打开 `native/` 生成的工程，跑 DSBot scheme（未签名 IPA 装不进模拟器，必须 Xcode 构建）。包名 `io.github.fei2411.dsbot.native`。
- 配对（模拟器无摄像头）：设置 → 配对 → 把电脑显示的 `dsbot://pair?...` 链接整段粘进输入框 → Connect。
- A 组推送注入不经过 APNs（`xcrun simctl push` 是本地注入），不需要 entitlement、不需要宿主发送器。
- 需要真实目标时，用已配对团队里已知存在的 Bot/房间 id 替换 `<BOT_ID>` / `<ROOM_ID>`，Bot 名替换 `<BOT_NAME>`。
- B 组前提：宿主第 2 批发送器已上线（`push.config` 配好 `[P8_PATH]`/`[APNS_KEY_ID]`/`[TEAM_ID]`）；手机装的是企业证书重签包（aps-environment=production）；宿主 token 存储在 `D:\DSBotData\bot\phone.json` 的 `push.tokens` 下。

---

## A 组：模拟器（`xcrun simctl push`）

**payload 文件**（三个都要就先建好，后续用例直接引用）：

```sh
cat > push-bot.json <<'EOF'
{ "aps": { "alert": { "title": "<BOT_NAME>", "body": "有新消息" }, "sound": "default" }, "botId": "<BOT_ID>", "kind": "message" }
EOF
cat > push-room.json <<'EOF'
{ "aps": { "alert": { "title": "<BOT_NAME>", "body": "有新消息" }, "sound": "default" }, "roomId": "<ROOM_ID>", "kind": "message" }
EOF
cat > push-badge.json <<'EOF'
{ "aps": { "alert": { "title": "<BOT_NAME>", "body": "有新消息" }, "sound": "default", "badge": 3 }, "botId": "<BOT_ID>", "kind": "message" }
EOF
```

- [ ] **A1 权限即问**
  前提：app 已装，从未开过推送开关。
  步骤：设置 → 「推送通知」开关打开。
  期望：系统权限弹窗出现且只出现一次；同意后开关保持开。
  失败信号：无弹窗但开关保持开（注册路径没走权限）；弹窗重复出现。

- [ ] **A2 点「不允许」即退**
  前提：同 A1（或先重装/还原系统推送权限为「未询问」）。
  步骤：开关打开 → 系统弹窗选「不允许」。
  期望：开关回弹为关；全程无任何错误弹窗。
  失败信号：开关保持开；出现报错 UI。之后想再开：去 iOS 设置 → 通知 → 允许，再回来打开开关——这条路径也应正常。

- [ ] **A3 前台抑制**
  前提：app 在前台（配对完成，停在任意聊天）。
  步骤：`xcrun simctl push booted io.github.fei2411.dsbot.native push-bot.json`
  期望：屏幕上**不出现**系统横幅；消息本体随后经加密链路进聊天流。
  失败信号：系统横幅弹出（willPresent 没有生效）。

- [ ] **A4 点击路由**
  前提：app 在前台但当前停在**别的**聊天（不是 payload 指的那个）。
  步骤：`xcrun simctl push booted io.github.fei2411.dsbot.native push-room.json` → 手动点横幅。
  期望：落在 payload 指定的房间会话，标题是团队里该房间的名字。
  失败信号：落在主 Bot；标题显示的是 id 不是名字。

- [ ] **A5 冷启动点击（重点用例）**
  前提：payload 指定的会话不是主 Bot。
  步骤：`xcrun simctl terminate booted io.github.fei2411.dsbot.native` → `xcrun simctl push booted io.github.fei2411.dsbot.native push-bot.json` → 点横幅。
  期望：app 冷启动后**直接落在 payload 指定的会话**，不是主 Bot、不是上次对话。
  失败信号：冷启动落在默认/主 Bot（delegate 装晚了，或路由没跑）。
  ⚠️ 原理注记：点击走的是 `didReceive`（delegate 在 didFinishLaunching 装好即收）；**`launchOptions[.remoteNotification]` 只载静默推送、本方案不用**——别从 launchOptions 里"修"路由，见 C1。

- [ ] **A6 横幅盖在 sheet 之上（重点用例）**
  前提：与宿主在线；宿主侧让一个 Bot 发起会触发 question/approval 的动作。
  步骤：打开设置 sheet → 宿主侧触发 question/approval → 8 秒内观察屏幕 → 点横幅。
  期望：应用内横幅浮在设置 sheet 之上可见；点击后设置 sheet 关闭、落到对应会话。
  失败信号：横幅被 sheet 埋住看不见；点击后 sheet 不关或落错会话。

- [ ] **A7 badge 清零**
  前提：回到桌面。
  步骤：`xcrun simctl push booted io.github.fei2411.dsbot.native push-badge.json` → 看图标角标 → 点开 app。
  期望：图标显示 3；app 前台化后角标归 0。
  失败信号：角标不出现（注入失败/未显示）；前台化后角标残留。

- [ ] **A8 关掉真不注册（模拟器可见部分）**
  前提：推送已开。
  步骤：关「推送通知」→ `xcrun simctl terminate booted io.github.fei2411.dsbot.native` → 重新打开 app。
  期望：开关保持关；无报错。完整判据（宿主侧 token 停用）见 B3。

## B 组：真机 + 宿主发送器（等 Relay 第 2 批）

- [ ] **B1 token 上报三字段（重点用例）**
  前提：重签包装机，开关打开并同意；与宿主完成配对且链路在线。
  步骤：等 10 秒 → 读 `D:\DSBotData\bot\phone.json`。
  期望：`push.tokens` 下本机 `d-` 键的记录为 `{ "token": <64位hex小写>, "env": "production", "bundleId": "io.github.fei2411.dsbot.native", "updatedAt": … }`。
  失败信号：无记录（上报没到/被拒）；token 大写或长度不对；env 缺失或不是 production；bundleId 写成了别的。

- [ ] **B2 前台在线不重推 + 60 秒去重**
  前提：手机与宿主链路在线。
  步骤：宿主侧对同一会话 60 秒内连续产生两条 notice → 观察手机与宿主日志。
  期望：手机只有链路内的实时 feed（无系统横幅，A3 的延伸）；宿主侧对离线才会推的场景才调用 APNs，同会话 60 秒内只发一条。
  失败信号：前台手机弹系统横幅；宿主对在线设备也发了推送；同会话 60 秒发了两条。

- [ ] **B3 关开关即宿主清除（重点用例，按 Warden 裁定）**
  前提：B1 已通过；宿主**第 2 批**（`token: null` 清除语义）已上线。
  步骤：手机关「推送通知」→ 杀进程重开 → 读宿主日志与 `D:\\DSBotData\\bot\\phone.json` → 宿主侧触发一条离线 notice。
  期望：宿主日志有一行「device X 请求停止推送」；`phone.json` 里本机 token 记录消失；后续 notice 对本机不再调 APNs；手机侧不注册、永远无横幅。
  失败信号：记录残留；日志无停推行；宿主仍对本机调 APNs；手机仍显示横幅（unregister 没生效）。
  过渡注记：宿主只到第 1 批时，null 会被 `bot/invalid` 拒掉且客户端静默吞掉——此时本条只判「手机不显示、宿主不重试」，清除判据等第 2 批。

- [ ] **B4 坏 token：410 之后不再重试（重点用例）**
  前提：B1 已通过；能改宿主 `phone.json`。
  步骤：手动把本机 token 改成乱码（如 64 个 `z`）→ 宿主侧触发一条离线 notice → 看宿主日志。
  期望：APNs 回 `400 BadDeviceToken`（乱码非 hex）或 `410 Unregistered`（已注销 token）→ 宿主删该 token 记录、落一行日志、**不再重试**；手机无感。
  失败信号：宿主无限重试或循环风暴；宿主崩溃；日志刷屏（超过一行）。

- [ ] **B5 老宿主降级**
  前提：一台仍在线但不带 `push-token` capability 的宿主（老版本 DS-Bot）。
  步骤：手机与老宿主完成配对并在线 → 开推送开关。
  期望：一切照旧——聊天、横幅、审批全正常；宿主永远收不到 push-token 调用；手机无报错。
  失败信号：任何报错 UI；上报调用发出去并被拒后弹了错误。

## C 组：反例与边界（防回坑）

- [ ] **C1 launchOptions 差异（原理用例，不执行也算过）**
  事实：冷启动**点击** alert 推送走 `UNUserNotificationCenterDelegate.didReceive`——delegate 在 `didFinishLaunching` 第一步装好（`PushCenter.bootstrap`），启动完成后投递，所以拿得到；`launchOptions[.remoteNotification]` 只在**静默推送**（`content-available`）唤醒时有值，本方案不发也不读静默推送。
  防坑：后来人看到"冷启动 launchOptions 里拿得到"的旧说法别信；A5 打勾即证明点击路径正确。修路由永远在 `didReceive`。

- [ ] **C2 静默推送无行为（负用例）**
  前提：任意状态。
  步骤：`cat > push-silent.json <<'EOF'` `{ "aps": { "content-available": 1 } }` `EOF` → `xcrun simctl push booted io.github.fei2411.dsbot.native push-silent.json`。
  期望：无横幅、无路由、无崩溃——本方案对静默推送没有行为（包里也没有 NSE）。
  失败信号：任何弹窗或路由发生（说明有人往 payload 里塞了路由且走了错误路径）。

---

## 执行记录

| 组 | 应跑 | 通过 | 未过 | 未执行 | 备注 |
|---|---|---|---|---|---|
| A | 8 | | | | |
| B | 5 | | | | 等 Relay 第 2 批 |
| C | 2 | | | | C1 可只读 |

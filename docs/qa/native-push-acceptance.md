# 真推送验收单（宿主直发 APNs · payload 只带路由）

适用对象：**包含 `61384a2` + `c561e83` + `422900b` 的下一个 native 构建**。客户端推送已落 main（`61384a2`：`PushCenter` + 设置开关 + window 级横幅 + 深链回调；`137f7e7` 线程修正；`b993b2a`：`push-token` 三字段补齐 env、冷启恢复接线；`422900b`：关开关即按裁定发 `token: null` 清除）。工程侧 `c561e83`（`DSBot.entitlements` + `dsbot:` scheme + push mode 门控）也在 main。**宿主发送器（第二批）未交付**，真机 B 组等它落地。

分工：执行步骤以 **`docs/qa/native-push-cases.md`** 为准——它的 A 组（模拟器 `xcrun simctl push` 本地注入，不经 APNs）今天就能跑，B 组真机、C 组反例。本单是真机**放行口径**，条目与 cases 同号对齐（标「= cases XX」），cases 没有的本单补齐。

口径：RN 从未有过真推送（`docs/native-push-scope.md` §1 检索为证），这是原生超集功能，判定基准是 `docs/native-push-design.md`（客户端）与 `docs/host-push.md`（宿主契约），不与 RN 对齐。行号会漂，按文件 + 函数定位。

**宿主门控前提**：宿主只对「无活跃 link 连接」的设备发（`host-push.md` §3）。每个真机用例先退后台 / 杀进程 / 断网，再让宿主触发，收不到不先算 bug。

**本单全部条目「需真机，未执行」；cases A 组（模拟器）未跑，跑了也不折抵真机结论。**

## 0. 前置核对（不占真机，勾不上 B 组全堵）

- [ ] **P0.1 entitlements 随包**：`c561e83` 已声明 `aps-environment` 与 `UIBackgroundModes: remote-notification`；核法：解包**重签后**的 .ipa 看 embedded entitlements 两项仍在（重签别剥掉）。`ee97d85` 出包文档带重签 entitlements 说明。
- [ ] **P0.2 宿主发送器就绪**：`push-token` 端点与 token 存储（`host-push.md` §1-2）已落宿主仓；发送器第二批（§3-4）已交付，`push.config`（.p8 路径 / KeyID / TeamID）已配。核法：宿主日志 + `phone.json` 的 `push` 字段。
- [ ] **P0.3 上报三字段 + null 清除语义**：`b993b2a` 补 env（PushCenter 读 `DSBotPushEnvironment`，默认 production、development 映射 sandbox）；`422900b` 按 Warden 裁定，关开关即发 `token: null`（null = 「本机停止」清除，env/bundleId 同报）。核法：开关同意后读 `phone.json`，本机记录 `{token 64位hex小写, env, bundleId}` 三字段齐全、bundleId 是重签后的运行时值（= cases B1）。
- [ ] **P0.4 apns-topic 跟随重签**：宿主按客户端上报的 bundleId 发（`host-push.md` §4），核法并入 P0.3。

## A. 必过（坏一个退回）

- [ ] **A1 开关即问**（= cases A1）｜设置 → 打开「推送通知」（默认关）｜系统权限弹窗一次，同意后开关保持开（`PushCenter.setEnabled`）｜
- [ ] **A2 拒绝即退**（= cases A2）｜同路点「不允许」｜开关回弹为关、全程静默无错误弹窗；之后去系统设置允许再开，路径也正常｜
- [ ] **A3 前台不弹系统横幅**（= cases A3 真机版）｜手机保持前台、断开与宿主的 link（关 Wi-Fi 或宿主下线）→ 宿主触发一条 notice｜**屏幕无任何系统横幅**（`PushCenter.willPresent` 恒 `[]`）；恢复网络后正文照常进聊天流｜
- [ ] **A4 关掉真不注册**（= cases A8 + B3）｜关开关 → 杀进程 → 冷启 → 宿主触发一条离线 notice｜手机不再调 `registerForRemoteNotifications`（bootstrap 只在 on 时注册）、无横幅无报错；关时客户端按裁定上报 `token: null` 清除（`422900b`，env/bundleId 同报），宿主按新契约判：日志一行停止推送、`phone.json` 记录消失、不再对本机调 APNs（cases B3 直接按此判，不等第二批）｜**第 1 批宿主下 null 被 64-hex 校验拒掉、客户端静默吞，本条判过渡态**：手机不注册不显示、宿主拒收不重试｜
- [ ] **A5 后台点击路由**（= cases A4 真机版）｜退后台（等 link 掉线，约半分钟到一分钟）→ 宿主发带 `botId` 的 → 点横幅；再发带 `roomId` 的 → 点横幅｜分别落到对应 Bot / 房间；`roomId` 优先（`PushCenter.didReceive`）；sheet 开着先关再落｜
- [ ] **A6 window 级应用内横幅**（= cases A6）｜前台在线，设置 sheet 开着，宿主触发 question/approval｜横幅浮在 sheet 之上可见（`NoticeOverlay.swift`），点击关 sheet 进对话｜
- [ ] **A7 冷启动路由**（= cases A5 真机版，重点）｜杀进程 → 宿主发 → 点横幅｜启动完成后直接落在目标对话（delegate 在 `didFinishLaunching` 第一步装好；冷启动点击走 `didReceive`，**不读 launchOptions**——它只带静默推送，本设计不用，见 cases C1）｜
- [x] ~~**A8 badge 清零**（= cases A7）~~ —— **不适用：Warden 2026-11-19 裁定本轮不做**（`f4afdf3`）。宿主不写 `aps.badge`、payload 不带计数：RN 从未有 badge，本轮是功能对齐不是超集；计数属内容层，塞进 payload 等于在「正文不出本机」上开口；合并窗口内的累加需要新语义。`SceneDelegate` 的 `setBadgeCount(0)` 保留为空转清零点，下一轮真做 badge 时正好用得上。**本条不计入通过数**。
- [ ] **A9 坏 token 失效**（= cases B4）｜把 `phone.json` 本机 token 改成乱码 → 宿主触发离线 notice｜APNs 回 `400 BadDeviceToken` 或 `410 Unregistered` → 宿主删记录、落一行日志、**不重试**；手机无感。另两路：重签/重装后旧 token 不再到达、新 token 覆盖恢复；`phone-remove` 后不再被唤醒｜
- [ ] **A10 旧宿主兼容**（= cases B5）｜拿不含 `push-token` capability 的旧电脑连一次｜无上报、无报错、聊天一切照旧（`PushCenter.hostOnline` 门控）｜
- [ ] **A11 未配对点击不崩**（cases 无对应，本单独有）｜未配对状态收到残留推送并点击｜路由照走，页面落到目标并显示离线/配对提示，不崩不白屏（`native-push-design.md` §4）｜

## B. 观察（不阻塞，但必须给结论：通过（可接受）/ 不通过（需改））

- [ ] **B1 去重窗口体感**（= cases B2）｜同一会话 60 秒连发两条 notice｜只到一条推送，第二条仅进 App（`host-push.md` §3 去重）｜结论：
- [ ] **B2 宿主「link 在线不发」门控**（并入 cases B2）｜手机前台在线时宿主产生 notice｜不推系统通知、正文实时进界面；仍推则记「宿主门控未生效」，找 Signal｜结论：
- [ ] **B3 payload 只带路由**（cases 无对应，本单独有）｜收到的任意一条通知｜文案只有「{Bot/群名} 有新消息」+ default 声；**出现正文片段即宿主违约（正文出了本机），最高优先级上报**｜结论：
- [ ] **B4 深链独立验证**（`c561e83` 已注册 scheme）｜Safari 打开 `dsbot://pair?…` 配对链接｜自动弹配对并提交（SceneDelegate 双回调 → `openPairingURL`）｜与推送无耦合，失败单独报，不占本单结论｜
- [ ] **B5 深色与锁屏观感**｜锁屏与通知中心各看一条｜浅深两色文案可读、无截断｜结论：

## 已知行为（别当 bug 报）

1. **系统权限关了但 App 开关仍开**：推送继续到达但不展示，App 不做运行时对账（`native-push-design.md` §1 已知边界）。
2. **关开关时宿主还在第 1 批**：`token: null` 被 64-hex 校验拒掉、客户端静默；宿主旧 token 记录留存，直到第二批清除语义、`phone-remove`、身份重生成或发送器 410 兜底——期间宿主可能对死 token 发送、APNs 拒收，手机无感。
3. **模拟器**：APNs 真注册必失败（`didFailToRegister` 静默）——不代表链路坏；模拟器验证走 cases A 组的 `simctl push` 本地注入。
4. **默认装完收不到通知是预期**：开关默认关 + 宿主发送器未上。先开开关、核 P0，再谈收不到。
5. **冷启动点击不读 launchOptions**（cases C1）：后来人别从 launchOptions 里「修」路由；修路由永远在 `didReceive`。静默推送无行为（cases C2）。
6. **本轮没有角标（badge）**：宿主不发 `aps.badge`、payload 不带计数（`f4afdf3` 裁定）。看到「点完通知角标还在/根本没有角标」都不算缺陷；`setBadgeCount(0)` 只是预留的清零点。
7. **从推送点进一个已被删除的会话 → 停在一个空聊天页，不自动跳主 Bot**（预期，别当 bug 报）。场景：通知发出后宿主侧把那个 Bot/房间删了，手机点开这条残留通知。落地路径 `openPushTarget` → `route(to:)` → `selectTarget`，后者无条件把 `autoSelectedTarget` 置 false（`ChatViewController.selectTarget`，「读者自己点的目标不挪动」，`c17173c`）；随后的读拿到 `bot/not-found`，只置 `gone` 并清 `LastChatStore`，`onTargetInvalid` 因非自动选择提前返回。**看到的是**：标题是该目标名、正文「No messages yet」、没有重试按钮的空聊天页。两条推论也不是缺陷：`dsbot.lastChat` 已被清，**下次冷启动回退主 Bot**；这条与「手点进入已删会话」表现完全一致（两条入口同一条路）。真正会回退主 Bot 的只有「冷启动自动恢复的目标被删」——那条走 `autoSelectedTarget = true` 的恢复链。

## 出问题怎么报

- 手机侧：长按聊天页标题 0.6 秒 → 「诊断信息」→ 复制（密钥自动打码）+ 记录时间点、横幅文案、点击后落在哪个屏。
- 宿主侧：`rt.warn` 一行一条的发送日志（含 APNs 状态码）+ `phone.json` 的 token 记录（贴前抹掉 token 前缀）。

## 汇总

- 必过通过 __ / **10**（badge 那条已裁定不适用，不计入）；阻断项：____；观察结论：____
- **本单全部条目当前状态：需真机，未执行；cases A 组（模拟器）亦未跑。**
- 放行三选一：☐ 放行 ☐ 有条件放行（条件：____）☐ 退回（指到：Signal 客户端 / 宿主发送器第二批 / 工程侧重签）

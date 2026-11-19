# Host 侧真推送：契约与实现记录

状态：**第 1、2 批均已落地（端点 + token 存储 + 发送器 + 触发钩子 + 配置入口）**，宿主仓改动未提交。客户端由 Signal 负责，双方以本文为契约；客户端落点 `native/Sources/DSBot/PushCenter.swift`（`b993b2a` + `422900b`）。

裁定背景（Warden）：宿主直接打 APNs（`api.push.apple.com`，HTTP/2 + ES256 JWT），不引第三方服务；payload 只带路由「{Bot 名} 有新消息」+ `botId`/`roomId`/`kind`，**正文不出本机**。

与既有文档的关系：`docs/native-push-scope.md` 的「不做 APNs」结论已被 2026-11-19 改派推翻；`docs/s2-push-readiness.md` 的 NSE 端到端加密推送仍挂起——本轮 payload 无密文，NSE 无活干，那个方向独立立项另行裁定。

---

## 0. 用户落地：四步（照着做）

这一节给操作的人看，不需要读代码。开做之前确认三件事：

- 有 Apple Developer Program 会员资格（推送密钥只对会员开放）；
- 手机上装的是**带推送权限的签名包**（`aps-environment` entitlement），不是模拟器——模拟器收不到真推送；
- 手机已经和这台电脑配对成功（App 能连上、能收发消息）。

### 第 1 步 先退出 DS Bot

托盘图标右键 → 退出（窗口关掉不算，进程还在）。`phone.json` 是宿主启动时读进内存、之后整份写回的，**它开着的时候改文件会被覆盖**，所以配密钥这整段都要在关闭状态下做。命令也会检查，宿主在跑就直接拒写——那时你回到这一步。

### 第 2 步 拿到三样东西（一次性，约 5 分钟）

打开 [developer.apple.com](https://developer.apple.com/account) → Certificates, Identifiers & Profiles → **Keys** → 右上角 ＋：

1. Key Name 随便填（例如 `DS Bot Push`），勾上 **Apple Push Notifications service (APNs)**，Continue → Register。
2. 下载 `AuthKey_XXXXXXXXXX.p8`。**这个文件只给一次**，关掉页面就再也拿不到；丢了只能删掉这个 Key 重建一个。
3. 记下两串 10 位字符：

| 占位符 | 在哪 | 例子 |
|---|---|---|
| `[APNS_KEY_ID]` | 文件名 `AuthKey_` 后面那 10 位，Keys 列表里也能看到 | `ABC1234567` |
| `[TEAM_ID]` | 同一页右上角 **Membership details** 里的 Team ID | `TEAM123456` |

把 `.p8` 放到仓库外面，例如 `C:\keys\`——`D:\DSBotWorkspace` 下的东西会被提交、被打包，密钥不许进去。下面用 `[P8_PATH]` 代指它的完整路径（例：`C:\keys\AuthKey_ABC1234567.p8`）。

### 第 3 步 一条命令写进配置

**DS Bot 必须是关着的**（第 1 步）；它开着这条命令会直接拒绝，不写文件。

```powershell
node "D:\DSBotWorkspace\DS Bot iOS\ds-bot-ios\scripts\apns-config.mjs" --key "[P8_PATH]" --key-id [APNS_KEY_ID] --team-id [TEAM_ID]
```

成功时打印（路径按本机实际显示）：

```
configured push in D:\DSBotData\bot\phone.json
  key path   C:\keys\AuthKey_ABC1234567.p8
  key id     ABC1234567
  team id    TEAM123456
  topic      (each phone names its own bundle id)
  sound      default
backup     D:\DSBotData\bot\phone.json.bak-20261119-084235
next       start DS Bot, then turn push on in the phone app
```

然后**启动 DS Bot**。

几件事说清楚：

- 脚本做的正是桌面端设置面板将来会调的 `phone-push-set` 的同一件事（同一个 `push.config` 形状、同一套校验），只是那个面板还没做出来。
- 它先验 `.p8` 能不能当 EC 私钥读出来、Key ID / Team ID 是不是 10 位；过不了就报错退出，**不改文件**。每次写之前都先备份（`phone.json.bak-本地时间`）。
- DS Bot 还开着它会直接拒绝——不是多事，是那一下的写入会被宿主的内存副本覆盖掉。
- 不写 `--topic` 也行：手机注册时会报自己的 bundle id（重签换了包名也跟得上），宿主用那个。要固定再加 `--topic io.github.fei2411.dsbot.native`。
- 不想要提示音：加 `--sound none`（照收，不出声）。
- 提示 `node 不是内部或外部命令`：把 `.p8` 路径、Key ID、Team ID 三个值发给你在这台电脑上的 Bot，让它代跑这一条。
- 一句实话：这条命令验过「宿主开着 → 拒绝写入」和「替身数据 → 写入成功」，但「真的把 DS Bot 退出 + 写到真实 `phone.json`」这一下还没发生过（写它的过程里宿主一直开着）。跑出任何看不懂的报错，把整段输出发给 Bot，不要自己手改 `phone.json`。

### 第 4 步 验证（3 分钟）

1. **手机**：DS Bot App → 设置 → 打开「推送通知」→ 系统弹窗选「允许」。
2. **电脑**确认配置和注册都在：

```powershell
node "D:\DSBotWorkspace\DS Bot iOS\ds-bot-ios\scripts\apns-config.mjs" --check
```

应看到 `push configured` 和 `tokens live`，并有一行形如

```
             d-3f9c2a71b4  production  io.github.fei2411.dsbot.native  live
```

（`DS Bot running: running` 也正常，`--check` 只读文件。手机还没注册过时这里是 `tokens none: turn push on in the phone app`。）

3. **把 App 从后台彻底划掉**（上滑结束进程）。这一步不能省：App 在后台还可能连着中继，宿主判定「在线」就不推——前台收得到的消息不重复打扰，这是设计。
4. **电脑上**随便给一个 Bot 发句话，等它回完。手机应弹出「{Bot 名或群名} 有新消息」，点开进对应会话。

### 没收到？按顺序查

```powershell
Get-Content "$env:APPDATA\DS Bot\logs\main.log" -Tail 300 | Select-String "ds-bot: push"
```

| 日志里看到 | 意思 | 怎么办 |
|---|---|---|
| `push skipped: no key configured` | 宿主没读到配置 | 第 3 步没跑成，或跑完没重启 DS Bot |
| `push to d-… failed: 403 InvalidProviderToken` | Key ID / Team ID 写错，或 `.p8` 与 Key ID 不是一对（一个 Key 一个 p8） | 回第 2 步核对；用 `--check` 看存进去的路径 |
| `push to d-… failed: 400 BadDeviceToken` | 环境不配对：本项目交付的 In-House 包是 `production`，Xcode 直装的 Debug 包把 `Info.plist` 的 `DSBotPushEnvironment` 设为 `development` 时是 `sandbox`（§9）；也可能 token 来自旧安装 | 对一下 `--check` 那行的 env；手机重装或重开推送开关会重新注册 |
| `push to d-… failed: 400 DeviceTokenNotForTopic` / `BadTopic` | token 对，topic（bundle id）不对 | 重开推送开关让它按当前包名重报 |
| `push token of d-… was retired by APNs (410 …)` | 这个 token 已失效，宿主标废、不再用 | 手机重开一次推送开关会注册新 token |
| `push to d-… failed: 403 ExpiredProviderToken` | 电脑系统时间偏差太大 | 校准系统时间后再试 |
| 没有任何 `push` 行 | 没走到发送：手机还连着（第 4 步・3），或这条 notice 落在 60 秒合并窗口里 | 彻底划掉 App 再试；换一个 Bot，或等一分钟（同设备・同会话・同 kind 一分钟只推一条；群里一轮的 `group` 与 `done` 算同一族，只响一次） |

`question` / `approval` 两类不合并——等人处理的东西宁可响两次，不可吞一次。群里一轮的 `group`（发言）和 `done`（收工）合成一条，不连响两次。

### 关掉推送

- 手机上关掉「推送通知」开关就够了：App 会发一次 `token: null`，宿主删掉这台设备的记录、留一行审计日志，之后不再推。
- 要收回这台电脑的发送资格（例如换密钥）：先退出 DS Bot，跑

```powershell
node "D:\DSBotWorkspace\DS Bot iOS\ds-bot-ios\scripts\apns-config.mjs" --clear
```

再启动 DS Bot，就回到「没配密钥」的静默状态（日志每个配置纪元只打一行 skip，不会刷屏）。

---

## 1. 端点契约 `push-token`

**调用路径**：App 在 link 就绪后走现有 `rpc('bot', { endpoint: 'push-token', payload })`，Noise 端到端加密，与 `state`/`notices` 同一条隧道。**不新增任何控制帧**，`link/` 零改动。

**能力发现**：`CAPABILITIES` 追加 `push-token`（`ds-bot/src/host/mobile.js:53`），`API_VERSION` 保持 1（`mobile.js:23`，机制见 `:20-22` 注释）。App 只在 `hello.capabilities` 里看到才调用。

**入参——三字段必填，注册与清除同形**（`422900b` 的 `reportToken` 恒发三字段）：

| 字段 | 规则 |
|---|---|
| `token` | 64 位 hex（大小写均可，宿主转小写存储）**或 `null`** |
| `env` | `'sandbox'` \| `'production'`，必填。App 侧由 Info.plist `DSBotPushEnvironment` 映射（`development`→`sandbox`，缺省 `production`） |
| `bundleId` | 非空、≤256 字符。取**运行时** `Bundle.main.bundleIdentifier`（重签会换，宿主不能猜，`native-push-design.md` §2） |

**身份不从 payload 来**：设备 ID 取隧道认证结果（`HostLink` 分发的 `{deviceId, signal}`），`callBot` 在 `phone.js:102` 拦截。已配对手机无法冒充另一台的 deviceId。

**行为**：

- `token` 为 64-hex → 按 deviceId **覆盖**存储，永不追加。
- `token: null` → **清除该设备的记录**（关推送开关是明确意图，不能等 410 慢慢失效）。清除动作落一行审计日志（`rt.warn`，`phone.js` pushToken 内）；无记录可清时同样回 `ok`，但不再多打日志。
- 校验失败 → `{ ok: false, error: { code: 'bot/invalid', message, details: {} } }`；成功 → `{ ok: true, value: { env, bundleId } }` / 清除回 `{ ok: true, value: { removed: true } }`。

**App 侧时机（Signal）**：冷启动拿到 token、`hostOnline` 能力确认后各报一次；token 变化再报；`setEnabled(false)` 即发 `token: null` 并 `unregisterForRemoteNotifications()`。

## 2. Token 与凭据存储（已实现）

都在 `phone.json`（`rt.home`，本机 `D:\DSBotData\bot\phone.json`），复用原子写（tmp + rename，mode 0600）：

```json
"push": {
  "tokens": {
    "d-xxxx": { "token": "64hex小写", "env": "production", "bundleId": "io.github.fei2411.dsbot.native",
                 "updatedAt": 1730000000000, "unregisteredAt": null }
  },
  "config": { "keyPath": "[P8_PATH]", "keyId": "[APNS_KEY_ID]", "teamId": "[TEAM_ID]",
               "topic": "[APNS_TOPIC]", "sound": "default" }
}
```

token 生命周期：注册覆盖；`phone-remove` 连删；host 身份重生成清空 tokens（保 config）；APNs 410/`BadDeviceToken`/`Unregistered` → `unregisteredAt` 标废（不是删除，`phoneView` 能看到「已失效」）；`token: null` 清除。畸形 `push` 字段读入时重置（`phone.js:35-36`）。

**配置入口 `phone-push-set`**（电脑侧端点，`channel.js` case + `phone.js` phoneEndpoint）：`{ keyPath, keyId, teamId, topic?, sound? }`。`keyPath` 指向 `.p8`（宿主把它 `resolve` 成绝对路径并**当场 `createPrivateKey` 试读**，读不动当场报错，不留到第一条推送）；`keyId`/`teamId` 各 10 位（存大写）；`topic` 可选（每 token 的 `bundleId` 优先，这只是兜底）；`sound` `'default'|'none'`（none = 静音推送）；`keyPath: ''` 整体清除配置。`.p8` 文件本体永远在仓库外。

**`phoneView` 增字段**（旧 UI 自动忽略）：`push: { configured, topic?, sound }`，每台手机 `push: 'live' | 'unregistered' | null`。

桌面面板还没做出来之前，用户侧的配置入口是 `scripts/apns-config.mjs`（§0 第 3 步）：它落的就是上面的 `push.config`，同一套 `.p8` 验读、同样把 Key ID / Team ID 转大写、同样要求 DS Bot 未运行（它持有内存副本）。面板做出来后直接调 `phone-push-set`，文件形状不变，脚本可留作无界面机器的备用。

## 3. 何时发、怎么去重（已实现）

**触发点**：`mobile.js` 的 `addNotice` 尾部 `rt.pushNotice?.(notice)`（`publishFeed` 之后，fire-and-forget，推送永不阻塞 notice 本身）。

**门控（`push.js`，逐设备）**：有 token 记录、未标废、且**不在 `link.connectedDevices()` 里**——前台连着的手机已实时收到 notice feed 事件，推送是第二声铃，不发。判据复用现有连接表，不另建一套。

**去重/合并**：键 `(deviceId|botId|roomId|kind)`，60 秒窗口内每设备每会话只发一条；**`kind=question`/`approval` 不合并**——等人处理的东西宁可响两次不可吞一次。`done` 与 `group` 归一族（`push.js` 的 `family()`）：群里一轮先写 `group`、收工再写 `done`，对人来说是同一条消息，窗口内只响一次；一对一只有 `message`，不受影响。进程内存 Map，重启清零。**不重试**：一条 notice 一发，失败就失败，下一条 notice 自然再试。

**payload**（路由 only，正文不出本机）：

```json
{ "aps": { "alert": { "title": "<Bot 名或群名>", "body": "有新消息" }, "sound": "default" },
  "botId": "b2", "roomId": "r1|null", "kind": "message|group|done|question|view|approval" }
```

`kind` 对齐 `NOTICE_KINDS`（`mobile.js:54`）；`sound` 由 `phone-push-set` 的 `sound: none` 关掉。App 点通知后走既有 `notices` 端点读真内容。

## 4. 发送器（已实现）

- **零新依赖**：`node:http2` + `node:crypto`（`ds-bot/src/host/push.js`）。
- **JWT**：header `{alg: ES256, kid: [APNS_KEY_ID]}`，claims `{iss: [TEAM_ID], iat}`；ES256 要 **raw r||s**（P1363）签名，不是 OpenSSL 默认的 DER——代码用 `sign('sha256', …, { dsaEncoding: 'ieee-p1363' })` 直接拿对格式，测试用公钥验签锁死这条。JWT 复用、`iat` 超 15 分钟刷新（Apple 上限 20 分钟，留余量）。
- **端点按 token 的 env 选**：production → `https://api.push.apple.com:443`，sandbox → `https://api.sandbox.push.apple.com:443`；环境不配对回 `400 BadDeviceToken`（`s2-push-readiness.md` §2.3）。
- **`apns-topic`** = 该 token 自己的 `bundleId`（重签后包名会变），`config.topic` 只兜底。
- **每批一次 h2 session**：同 env 的目标共享，发完 `close()`；连接失败记一行日志、本批放弃。
- **失败处理**：`:status 410` 或 reason `BadDeviceToken`/`Unregistered` → 标废（`unregisteredAt`）+ 一行日志，该 token 永不再试；`DeviceTokenNotForTopic` 等**不**标废（那是配置错，删 token 会误伤）；其余 4xx/5xx 只记日志。
- **没配密钥是常态不是故障**：静默跳过，每个配置纪元只打一行 `push skipped: no key configured`。
- 测试注入口：`rt.pushTransport(origin)` 替换 h2 连接、`rt.pushClock()` 替换时钟，只在测试里使用。

## 5. 兼容性

| 组合 | 结果 |
|---|---|
| 新 host + 旧 App | App 从不调用 `push-token`；`hello.capabilities` 多一项被忽略 |
| 旧 host + 新 App | capabilities 里没有，App 跳过注册；`422900b` 的 `hostOnline` 门控保证不白调 |
| 新 host + 旧 `phone.json` | `read()` 把缺失/畸形的 `push` 规范化为 `{tokens:{}}`（`phone.js:35-36`） |
| 旧 host + 新 `phone.json` | 旧代码只规范化 `devices`，对未知字段无感知 |
| `phoneView` 新增字段 | 纯增量，旧 UI 忽略 |
| link 协议 | 零改动：不加控制帧、不动握手、不动 counter |

## 6. 验收

**已实测（本机，Node 24.14.1，`test/push.test.js` 四用例全绿）**：

1. `buildJwt`：ES256 raw 签名（64 字节）+ kid/iss 位置 + 公钥验签通过。
2. 端点端到端（真中继 + 真 Noise 隧道）：注册落盘小写化、重注册**覆盖不追加**、`token: null` 清除 + 审计行恰一条、七种坏参（含缺 env、null 配坏 env/bundleId）回 `bot/invalid` 且不动已存值、`phone-remove` 连删。
3. `phone-push-set`：坏 p8/坏 keyId/坏 teamId/坏 sound 当场拒；好配置落盘（keyId/teamId 转大写）；`keyPath: ''` 整体清除。
4. 触发链端到端（注入 mock APNs）：离线手机收到、在线手机零打扰；sandbox token 走 sandbox origin；payload 逐字段断言；60 秒窗口合并、`group`/`done` 同族只响一次、question 绕过合并、窗口过期再响；410 → 标废 + 一行日志 + 永不再发；无密钥静默 + 一行 skip。
5. `scripts/apns-config.mjs`（§0 的用户命令，本机 2026-11-19 实测）：写入的形状与 `phone-push-set` 一致（绝对路径、Key ID / Team ID 转大写、`sound` 归一）；重复写覆盖并各留一份 `bak-本地时间`；四种坏参（短 Key ID、带空格的 Team ID、文件不存在、非密钥内容）全部 exit 1 且目标文件未被改动；`--check` 只读、`--clear` 删配置；DS Bot 运行中（探测 `host-port.json` 的端口）直接拒写。

连同 `phone`/`mobile`/`remote` 四文件 **46/46**；全仓套件与本机 61 个预存环境性失败基线**零差异**（比对命令见交付报告）。

**未验证（如实）**：真机 APNs 投递（需 `[P8_PATH]`/`[TEAM_ID]` 与签名包，对应 `docs/qa/native-push-cases.md` 的 5 个真机用例）；模拟器 8 个用例（Signal 侧执行）；用户真实 `phone.json` 的写入迁移（`--check` 已在真实文件上只读跑过，写入要等用户按 §0 填密钥那一步）。§0 的命令没有在「DS Bot 已退出」的真实状态下跑过——那会杀掉本 Bot 所在的宿主，改用替身 `APPDATA` 验证了同一条写入路径。

## 7. 改动清单（宿主仓 `ds-bot/`，未提交）

| 文件 | 改动 |
|---|---|
| `src/host/mobile.js:53,183-185` | `CAPABILITIES` += `push-token`；`addNotice` 尾挂 `rt.pushNotice?.(notice)` |
| `src/host/phone.js` | `read()` 规范化 `push`；`identity()` 重置 tokens；`pushToken()` 三必填 + null 清除 + 审计行；`callBot` 拦截（deviceId 取隧道）；`phone-remove` 删 token；**新增** `phone-push-set` case（p8 当场验读）；`phoneView` 增 `push` 与 `phones[].push`；`rt.pushState` 桥 |
| `src/host/push.js` | **新文件**：ES256 JWT（P1363）、env→origin、批发送、410 标废回调、去重、无密钥静默 |
| `src/host/channel.js` | case 列表 += `phone-push-set`（1 行） |
| `index.js` | import + `MODULES` 插入 `push`（不注册任何 listener/effect，`install.test.js` 的注册顺序快照不受影响） |
| `test/push.test.js` | **新文件**，4 用例 |
| `test/phone.test.js:60` | `phoneView` deepEqual 补 `push` 键 |

没碰：`link/`、`mobile/`（iOS 客户端）、`.github/`。

本仓（`ds-bot-ios`）另新增 `scripts/apns-config.mjs`：§0 的配密钥命令（写 / `--check` / `--clear`），不进宿主交付面；桌面面板做出来后由 `phone-push-set` 接管，文件形状不变。

## 8. 对齐记录

- **对齐**：payload 键名 `botId`/`roomId`/`kind` 与 `PushCenter.didReceive` 逐字核对一致；`aps.sound: default` 可关；token 恒 lowercase 存储；`env` 三必填按 Warden 终裁（我中途按旧版客户端实现放过一次「env 缺省 production」，已改回必填——`b993b2a` 后客户端恒发 env）。
- **badge：已裁定本轮不做**（Warden，见 `native-push-design.md` §5）。宿主不写 `aps.badge`、payload 无计数；`SceneDelegate` 的 `setBadgeCount(0)` 保留为空转的清零点；`native-push-cases.md` 的 A7 标为「不适用」。下一轮若做，最小实现仍是每设备读游标 + 合并窗口内累加，语义届时再定。

## 9. 客户端侧同一条契约（Signal 抄录）

同一套字段的客户端说法，防止两边各写一份、后来人只读一边。实现见 `native/Sources/DSBot/PushCenter.swift`，设计见 `docs/native-push-design.md` §2。

**`push-token` 请求体（客户端恒发三字段）**

| 字段 | 客户端怎么取值 |
|---|---|
| `token` | APNs 回调 `didRegisterForRemoteNotificationsWithDeviceToken` 的十六进制小写串；**`null` = 本机停止推送**（用户关开关），此时 `env`/`bundleId` 照发，保持校验形状一致 |
| `env` | 默认 `production`（本项目交付全是 In-House）；`Info.plist` 的 `DSBotPushEnvironment` 为 Debug 装机留的后门，值 `development`/`sandbox` 映射为 `sandbox` |
| `bundleId` | 运行时 `Bundle.main.bundleIdentifier`。**绝不写死**：交付的 IPA 未签名、用户重签会带进自己的 bundle id，`apns-topic` 必须跟着变，宿主按上报值发 |

**调用时机**：只在 `hello.capabilities` 含 `push-token` 时发（老宿主永远收不到，`API_VERSION` 不动）；token 变化即发；开开关即发；关开关发 `null`。全部 fire-and-forget，失败静默降级为「没有推送」，不弹任何错误。

**客户端不做**：不写 `aps.badge`、不读静默推送、不管 `.p8` 与 topic 配置（宿主侧），也没有 NSE。

**一句提醒**：这条契约是两仓唯一接口，改任何一侧的字段名或必填性，两边都要对着读一遍再落——`env` 那次缺口（客户端只发两字段、宿主三必填）就是只信文档不读对端校验的后果。

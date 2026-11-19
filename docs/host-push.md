# Host 侧真推送：契约与实现记录

状态：**第 1、2 批均已落地（端点 + token 存储 + 发送器 + 触发钩子 + 配置入口）**，宿主仓改动未提交。客户端由 Signal 负责，双方以本文为契约；客户端落点 `native/Sources/DSBot/PushCenter.swift`（`b993b2a` + `422900b`）。

裁定背景（Warden）：宿主直接打 APNs（`api.push.apple.com`，HTTP/2 + ES256 JWT），不引第三方服务；payload 只带路由「{Bot 名} 有新消息」+ `botId`/`roomId`/`kind`，**正文不出本机**。

与既有文档的关系：`docs/native-push-scope.md` 的「不做 APNs」结论已被 2026-11-19 改派推翻；`docs/s2-push-readiness.md` 的 NSE 端到端加密推送仍挂起——本轮 payload 无密文，NSE 无活干，那个方向独立立项另行裁定。

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

## 3. 何时发、怎么去重（已实现）

**触发点**：`mobile.js` 的 `addNotice` 尾部 `rt.pushNotice?.(notice)`（`publishFeed` 之后，fire-and-forget，推送永不阻塞 notice 本身）。

**门控（`push.js`，逐设备）**：有 token 记录、未标废、且**不在 `link.connectedDevices()` 里**——前台连着的手机已实时收到 notice feed 事件，推送是第二声铃，不发。判据复用现有连接表，不另建一套。

**去重/合并**：键 `(deviceId|botId|roomId|kind)`，60 秒窗口内每设备每会话只发一条；**`kind=question`/`approval` 不合并**——等人处理的东西宁可响两次不可吞一次。进程内存 Map，重启清零。**不重试**：一条 notice 一发，失败就失败，下一条 notice 自然再试。

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
4. 触发链端到端（注入 mock APNs）：离线手机收到、在线手机零打扰；sandbox token 走 sandbox origin；payload 逐字段断言；60 秒窗口合并、question 绕过合并、窗口过期再响；410 → 标废 + 一行日志 + 永不再发；无密钥静默 + 一行 skip。

连同 `phone`/`mobile`/`remote` 四文件 **46/46**；全仓套件与本机 61 个预存环境性失败基线**零差异**（比对命令见交付报告）。

**未验证（如实）**：真机 APNs 投递（需 `[P8_PATH]`/`[TEAM_ID]` 与签名包，对应 `docs/qa/native-push-cases.md` 的 5 个真机用例）；模拟器 8 个用例（Signal 侧执行）；用户真实 `phone.json` 现场迁移（逻辑被 `read()` 覆盖，没拿真文件跑过）。

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

## 8. 对齐记录与一个开放分歧

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

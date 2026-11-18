# 原生行为对照：RN mobile → native（聊天）

基线 commit：`f7f3283`（main）。只读清单，未改任何代码。
范围：`mobile/src/screens/Chat.tsx`、`mobile/src/screens/chat/*`、`mobile/src/team/link.ts`、`chat-cache.ts`、`optimistic.ts`、`seen.ts`、`nav/ShellB.tsx` 对照 `native/Sources/DSBot/ChatViewController.swift`、`ChatStream.swift`、`ChatTimeline.swift`、`LinkSession.swift`。
不在范围：视觉、材质、动效（见 `native-ui-gap.md`）。

## 摘要

| 优先级 | 条数 | 含义 |
| --- | --- | --- |
| P0 | 2 | 会发错消息 / 消息发不出去 |
| P1 | 4 | 每次用都感觉得到 |
| P2 | 10 | 打磨 |
| 已对齐 | 8 | 逐条列在最后，附证据 |

两个 P0 都只有一类触发路径：**切目标后的草稿**、**后台回来后的第一次发送**。其余是手感与提示。

---

## P0

### G-01 切换 Bot / 群组时，输入框草稿会带过去

- **RN**：`nav/ShellB.tsx:219` 给 `ChatView` 传 `key={computer:kind:id}`，切目标等于重建组件，`Composer` 的草稿状态随之丢弃。
- **原生**：全页只有一个 `NativeComposerView` 实例（`ChatViewController.swift:1123` 起），`selectTarget`（`ChatViewController.swift:1093-1119`）只清列表与选中态，**不碰输入框**；全仓没有 `composer.clear()`，`restoreDraft` 只在发送失败时用（`:1299`、`:1302`）。
- **影响**：在 A 里打了一半的话，切到 B 还留在输入框里，按发送就发给了 B。
- **优先级**：P0

### G-02 回到前台不探活，半开连接要等 RPC 超时才失败

- **RN**：`team/link.ts:241-246` 监听 `AppState`，`active` 时先 `clientRef.current?.probe()` 再 `poll()`；`onClose` 一路把 `online` 置假（`:223-228`）。
- **原生**：没有任何前后台观察者——`Sources/DSBot` 里 `willEnterForeground` / `didBecomeActive` / `probe` 均无命中；链路只在 socket 关闭时才转 offline（`LinkSession.swift:216-238`）。`RpcClient` 的默认超时 30 000 ms（`RpcClient.swift:9`），轮询 15 s（`ChatViewController.swift:695-703`）。
- **影响**：切出去再回来发消息，气泡停在「Sending…」最长 30 秒才变红，期间状态条仍显示「在线」。
- **优先级**：P0

---

## P1

### G-03 每个对话的最新一页没有缓存，切回来是白屏等读

- **RN**：`createChatCache` 存最近 16 个对话的页（`team/chat-cache.ts:12-26`，`Chat.tsx:51-52`），离开时写入（`Chat.tsx:171-173`），再进入先用缓存渲染（`Chat.tsx:154-158`）。
- **原生**：无缓存；`selectTarget` 直接清空 `olderRows`/`latestRows`/`rows`（`:1093-1119`）再整页读（`:823-846`）。
- **影响**：每换一次对话都先空一下再出消息，网慢时明显。
- **优先级**：P1

### G-04 滚动只做了「贴底跟随」，没有 RN 的 maintainVisibleContentPosition

- **RN**：倒序 FlatList + `maintainVisibleContentPosition`（`Chat.tsx:383`），`onScroll` 维护 `awayFromLatest`（`:384`），只有贴底时才自动跟（`:390-396`）。
- **原生**：`rebuildRows` 每次 `list.reloadData()`（`:83-111`），`refreshLatest` 只在贴底时滚到底（`:833`、`:847-850`）；往上翻时靠 `contentOffset` 保持，但整表 reload 后行高变化会漂。
- **影响**：翻历史时新消息到达，列表会跳一下或停偏，回头要手动找位置。
- **优先级**：P1

### G-05 错误文案不映射，屏幕上出现英文技术串

- **RN**：`errorText` 把 `NOT_PAIRED` / `HOST_OFFLINE` / `SERVER_UNREACHABLE` 翻成人话（`team/link.ts:276-282`），`localized` 把 `TRANSPORT_CLOSED` 变成 offline（`:287-292`）。
- **原生**：状态条直接 `showLinkError(error.localizedDescription)`（`:657-662`），空态也直接 `loadError = error.localizedDescription`（`:855`）；`TransportError.description` 是 `code: message`（`Frames.swift:55-58`），即 `invalidFrame: …`、`notPaired: …`。
- **影响**：断线、未配对、宿主离线时，用户看到的是英文错误码而不是下一步该做什么。
- **优先级**：P1

### G-06 hello 版本检查失败时直接断链，用户看不出「去更新电脑」

- **RN**：`hello.api === null` 时只 `setError('Update DS Bot on the computer to use this phone.')`、`setLinked(false)`，链路保留（`team/link.ts:203-209`）。
- **原生**：`checkComputer` 里 hello 失败就 `session.disconnect()`（`:664-693`，断开在 `:668-672`），状态条转「离线」。
- **影响**：电脑上的 DS Bot 太旧时，手机显示「离线」，用户会去查网络而不是更新电脑。
- **优先级**：P1

---

## P2

### G-07 `message` 事件不做乐观追加，整页重读后才出现
- **RN**：收到 `message` 先把 `data.item` 追加进列表再 `refresh`（`Chat.tsx:252-261`）。
- **原生**：`handleFeed` 对 `message` 只触发 `refreshLatest`（`:539-563`，判断在 `:558-562`）。
- **影响**：对方消息比 RN 晚一个往返才出现。
- **优先级**：P2

### G-08 `notices` 的 `reset` 被忽略
- **RN**：`notices({boot, since: 0})` 回来 `reset === true` 就立刻 `poll()`（`team/link.ts:218-222`）。
- **原生**：调用但不看返回值（`:685-687`）。
- **影响**：电脑重启后手机不会立刻补读，要等下一轮 15 s 轮询。
- **优先级**：P2

### G-09 `bot/not-found` 与会话被删没有区分
- **RN**：`code === 'bot/not-found'` 置 `gone`，显示「No messages yet」并回调 `onMissing`（`Chat.tsx:142`）。
- **原生**：一律走 `loadError` + retry（`:851-857`）。
- **影响**：Bot 被删后仍显示错误与一个永远成功的重试按钮。
- **优先级**：P2

### G-10 附件不按能力协商
- **RN**：只有 `hello.capabilities` 含 `send-images` 才给附件入口（`Chat.tsx:407`）。
- **原生**：无 capability 判断（`ChatViewController.swift` 内无 `send-images` 命中），加号始终可点，老电脑上会走 `stage-image` 失败。
- **影响**：老版本电脑上点附件只会得到一次失败。
- **优先级**：P2

### G-11 相邻的步骤行不折叠
- **RN**：`foldSteps` 把相邻 `steps` 合并成一条（`Chat.tsx:427-443`）。
- **原生**：每个 steps 行各自一条 `stepSummary`（`ChatTimeline.swift:137-149`）。
- **影响**：长回合里「用了 N 个工具」刷一列。
- **优先级**：P2

### G-12 时间戳显示规则不同
- **RN**：同一 Bot 连续气泡只在最后一条显示时间（`Chat.tsx:459-467`）。
- **原生**：行内有 `time` 就显示（`ChatMessageCell.swift:157-160`）。
- **影响**：连续气泡每行都带时间，比 RN 啰嗦。
- **优先级**：P2

### G-13 空页但 cursor 不变时会重复请求同一页
- **RN**：`loadMore` 只在 `cursor == null` 时停（`Chat.tsx:178`），同样没有空页记忆，但列表阈值不同（`:382`）。
- **原生**：`loadOlder` 同样只按 cursor 停（`:860-889`），失败静默重试（`:885-888`）。
- **影响**：宿主返回空页时，来回滑动会反复请求。
- **优先级**：P2

### G-14 未读时间只在 state 读成功时写
- **RN**：进入对话即 `markSeen(id)`（`Chat.tsx:239`），每条 `message` 再写一次（`:259`）。
- **原生**：写在 `refreshLatest` 成功分支（`:785-786`），且必须在 target 解析成功之后。
- **影响**：离线状态切进某个 Bot，红点不会清，要等连接恢复后的第一次读。
- **优先级**：P2

### G-15 离开聊天页仍在每 15 s 轮询
- **RN**：屏幕卸载即清掉定时器与订阅（`Chat.tsx:167`、`:247-254`）。
- **原生**：`polling` 只在状态变化/重连时取消（`:695-703`，取消点在 `:622-656` 的 showStatus），push 到详情页或切到别的 Tab 后照旧读。
- **影响**：后台耗电与流量，且回前台更可能与半开连接撞上（见 G-02）。
- **优先级**：P2

### G-16 没有启动预读
- **RN**：`prefetchChat` 在链路刚通、团队还没到时先读上次的对话（`Chat.tsx:59-65`，调用在 `ShellB.tsx:190`）。
- **原生**：无。
- **影响**：冷启动后第一次进对话多等一个往返。
- **优先级**：P2

---

## 已对齐（查过，无需改）

| 行为 | RN | 原生 |
| --- | --- | --- |
| 发送幂等（同文同图不会被算成新行） | `Chat.tsx:81-84`、`:284-288`、`:321-326` | `Outgoing.known` + `acknowledgedRows` 去重（`:83-102`） |
| 失败后可重试 / 丢弃 | `retry`（`Chat.tsx:306-312`） | 点失败气泡弹 sheet（`:1457-1474`） |
| 流式按 attemptId 累积 | `Chat.tsx:580-596` | `ChatStream.swift:18-38` |
| 断线清掉半截流式文本 | 不清（`Chat.tsx:223-228` 只置 online=false） | 清（`:622-656` 的 offline/disconnected 分支里的 `stream.clear()`） |
| revision/live/message/room 触发补读 | `team/link.ts:213-217`，`Chat.tsx:249-263` | `handleFeed`（`:539-563`） |
| 分页游标只在首屏/换会话时取，向上翻到 `null` 停 | `Chat.tsx:136`、`:178` | `:839-841`、`:861` |
| 只有贴底才自动跟随 | `Chat.tsx:383`、`:390-396` | `:833`、`:847-850` |
| 停止当前回合 | `stop-chat` / `stop-room-work`（`Chat.tsx:313-316`） | `stopChat`（`:1359-1369`） |
| 15 s 兜底轮询 | `Chat.tsx:12`、`:24` | `:695-703` |
| 发送后滚到最新 | `Chat.tsx:303` | `:1308-1310` |

---

## 附录：聊天屏里仍有硬编码英文（语言单的漏网）

这三处不在 `tr(...)` 调用里，第一批没扫到：

- `ChatMessageCell.swift:158`：`"Not sent · …"` 与 `"Sending…"`。
- `ChatTimeline.swift:142`：`"Used N tools"`。
- `ChatTimeline.swift:195`：`"Work steps"`。
- `ChatViewController.swift:669`：`"Update DS Bot on the computer to use this phone."`——G-06 那条提示本身就没走 `tr`。

建议随 G-11/G-12 一起改，避免同一处改两遍。

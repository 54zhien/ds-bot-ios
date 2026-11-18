# 原生 iOS 的 CI（一页）

仓库 `54zhien/ds-bot-ios`，`main` 是默认分支。原生这条线的**所有**编译、测试、出包、截图都在 GitHub Actions 上跑：本地没有 Xcode / Swift 工具链，也不允许用本地结果代替 CI 结论。

下面每个数字都是真跑出来的 run 记录，不是估计；估计的会标「未实测」。

## 1. 五个 workflow

| workflow（文件） | job | 触发 | 实测耗时 | 回答什么问题 | 什么时候手动 dispatch |
|---|---|---|---|---|---|
| `ios-native.yml` | `compile` | **push** 到任意分支，且改动命中 `native/**` 或 `.github/workflows/ios-native.yml`。tag 推送被 `if` 排除 | 2m53s – 10m49s，通常 ~6 min（随排队浮动） | 这棵树编得过吗？单测过吗？ | **不 dispatch**：dispatch 进的是 ipa job，compile 在 dispatch 里是 `skipped` |
| `ios-native.yml` | `ipa` | `workflow_dispatch`（`runner` / `xcode_version`），或 push tag `ios-native-v*` | 96s – 2m05s | 能不能出一个合格的未签名 IPA | 要可安装的包、或验证出包链时才跑；**用 `scripts/dispatch-ipa.ps1`**，它会自动重试饿死（见 §6） |
| `ios-native-smoke.yml` | `smoke` | **push 到 `main`**，且命中 `native/Sources/DSBot/**` 或 `native/project.yml`；另有 dispatch | 7m43s | app 起得来吗？首屏是不是黑屏/白屏？ | 改完 UI 想要一张真界面截图时 |
| `ios-native-interop.yml` | `interop` | 只有 `workflow_dispatch` | 57s / 98s | Swift 传输层能不能跟真 relay 走完 hello → 握手 → 一次 RPC | 动了 `native/Sources/Transport/**` 或协议之后 |
| `ios-native-screens.yml` | `screens` | 只有 `workflow_dispatch` | **未实测**（从没跑过，估计 6–9 min） | 喂一份结构正确的样张 state，界面到底画成什么样 | 要判 UI 差距时；用户嫌慢，先问 Warden |
| `ios-toolchain.yml` | `probe` | `workflow_dispatch`，或 push tag `ios-probe-*`（矩阵：`macos-26` + `macos-15`） | 未实测（workflow 注释写约 1 min） | 镜像上装了哪些 Xcode、有没有 iOS 26 SDK / Liquid Glass | 换 runner，或怀疑镜像变了 |

两点补充：

- `ios-native.yml` 的 dispatch 和 tag 走的是 **ipa job**；compile job 在这两种事件下被 `if` 排除。反过来，分支 push 永远进不了 ipa job。两个 job 严格互斥。
- `runner` 默认 `macos-26`，可选 `macos-15`。选 Xcode 那步要求 **major ≥ 26**，低于就当场失败；`xcode_version` 留空则取镜像上最新的稳定版。

## 2. 谁顶谁

| workflow | concurrency group | cancel-in-progress |
|---|---|---|
| compile | `ios-native-compile-<ref>` | **true** |
| smoke | `ios-native-smoke-<ref>` | **true** |
| ipa | `ios-native-ipa-<ref>` | false |
| interop | `ios-native-interop-<ref>` | false |
| screens | `ios-native-screens-<ref>` | false |

- **compile 在跑时再推一次，前一次会被取消。** 实测：`44288510304`（`72fad1f`）在 `10:50:22` 那次 push 之后约 20 秒被取消。后果不是「编译坏了」，而是**那次提交永远不会有编译结论**——手快连推三次，只有最后一个 commit 有答案。要判断中间某次提交是否引入错误，就别在它编译出结果前继续推。
- **smoke 会被顶，而且 push 与 dispatch 共用一个组。** 实测两条：dispatch 出来的 `44285414031`（`e9f24f4`）被 `f7f3283` 的 push 触发顶掉；`44289924858`（`7e13b75`）被 `1eecf6e` 顶掉。所以 dispatch 一次 smoke，同时有人在推 UI，两者只有后到的那个会跑完——这是期望行为，不用修。
- **ipa / interop / screens 排队，不互相取消。** 连续 dispatch 两次 ipa 会依次跑完。
- **跨 workflow 不会互相取消。** 五个文件的 group 名字互不相同。实测：`10:46:22` dispatch 的 ipa（`44288530179`）与同一 SHA 的 compile（`44288510304`）同时在跑，compile 后来是被 `10:50:22` 的**新 push** 取消的，不是被这次 dispatch 取消的。dispatch 里被 `if` 跳过的 job 显示 `skipped`，不占用并发组。

## 3. 失败怎么读

**`Compile the Swift tree` 红** —— 基本都不是流水线的问题，是这棵树第一次真的被编译。常见三种：Swift 6 严格并发（`main actor-isolated default value in a nonisolated context` 这类）、`@MainActor` 初始化时机、新文件没进 `native/project.yml` 的 `sources`。日志已自动打印末尾 40 行 `error:` 与后 120 行，失败时另有 artifact `DS-Bot-ios-native-compile-log`。

**smoke 红** —— 先看判定器打出的三个数字，再看一份日志：

```
distinct colours: N        (需要 ≥ 8)      —— 有没有画出东西
... 18 samples differ (2.25%, need ≥ 0.5%) —— 内容区有多少不是背景色
mean luminance 252.1       (< 40 且 < 4 色 = black screen)
```

判定只采样**内容区**：切掉 60pt 状态栏与 34pt home indicator（按图里反推的 3x/2x 比例，不写死 180px）。所以黑屏判据不会被状态栏白字救活。图在 artifact `ios-native-smoke-screen`；日志在 `smoke/device.log`，其中命中 `Fatal error` / `SIGABRT` / `terminated`（`connection terminated` 已滤掉）就直接失败。若报 `screenshot is not a BMP` 或 `unexpected BMP shape`，坏的是截图那一步，不是 UI。

**interop 红** —— 按顺序看 `interop/host.log`：`hello` 里有没有带 `pairingCode`、`connect.request` 有没有过、两段 Noise 握手是否完成。配置是 host 写进 `InteropConfig.generated.swift` 再编译进测试的（`xcodebuild test` 不把 shell 环境变量传给测试进程），所以字段名对不上会先在**编译**阶段红，而不是断言失败。

**screens 红** —— `screens/host.log` 里有没有 `state -> ok`。如果 state 已经 ok 而图里仍是 `No Bot yet`，问题在 app 侧——这正是这条流水线存在的理由：把「连上但看不到 Bot」在 CI 里复现，而不是等真机截图。

## 4. artifact 都有什么

| 来自 | artifact | 内容 | 保留 |
|---|---|---|---|
| compile | `DS-Bot-ios-native-compile-log` | `dist/compile.log`（仅失败） | 7 天 |
| ipa | `DS-Bot-ios-native-unsigned` | **四个文件**：`DS-Bot-<ver>-native-unsigned.ipa`、`DS-Bot-native-unsigned.sha256`、`build-info-native.json`、`release-notes.md` | 30 天 |
| ipa | `DS-Bot-ios-native-dSYMs` | `DSBotNative.xcarchive/dSYMs` | 30 天 |
| ipa | `DS-Bot-ios-native-build-log` | `dist/xcodebuild-native.log`（仅失败） | 7 天 |
| smoke | `ios-native-smoke-screen` / `-log` | `smoke/01-launch.png` / build、launch、device 日志（仅失败） | 7 天 |
| interop | `DS-Bot-ios-native-interop-log` | `interop/*.log`（仅失败） | 7 天 |
| screens | `DS-Bot-ios-native-screens` / `-log` | `screens/*.png`（14 天）/ `screens/*.log`（仅失败，7 天） | 14 / 7 天 |
| toolchain | 无 | 结论写在 run summary 里 | — |

`release-notes.md` 里就是「这版有什么」：commit 判据是**上一个祖先 `ios-native-v*` tag**（没有 tag 则最近 20 条），最多列 40 条，其余折在 `compare/<tag>...<sha>` 后面；版本取自 `native/project.yml`（经 Info.plist 进包），归档里的值与它不一致时这一步直接失败，所以说明和包不可能互相矛盾。最新 tag 与版本对不上时，文件里会自带一段 `> Version note:` 交代矛盾。

## 5. 冻结的那条线

`.github/workflows/ios.yml` 是 **React Native** 那条线的，已冻结，别动。原生的一切都在 `ios-native*` 里。

另外两条容易踩的：

- **版本号以 `native/project.yml` 的 `CFBundleShortVersionString` / `CFBundleVersion` 为准**。`mobile/app.json` 是 RN 那边的，`mobile/` 下没有任何东西决定原生包的版本。
- **不要打 tag。** `ios-native-v*` 由人手动切，现有 `v0.1.0`…`v0.1.4` 是 11-16 一下午连打的，此后原生加了一百多个提交、版本号没动。在用户真机验收第一版可用之前，不切新 tag；版本号与 tag 策略等验收后再一起定。

## 6. 出包 dispatch 与排队饿死

macos-26 的 runner 池偶尔派不出机器：排队的 ipa job 在 **15m01s** 被平台回收，job 层记 `cancelled`、`steps=0`、`runner_id=0`，run 层记 `failure`。实测 `44334425742`、`44337943209` 两次都是这个形状，紧跟的重 dispatch 直接成功。这个签名与真编译红不同（`steps>0`），与人手取消也不同（run 层是 `cancelled`），所以三者可以可靠地区分。

出包一律走 `scripts/dispatch-ipa.ps1`（默认 N=3 次尝试）：dispatch → 每 30s 轮询 → **只对饿死**自动重 dispatch（每次重试前打印 `attempt k/N` 与新 run id，并注明是饿死重试）→ 真红（`steps>0`）立即停并报红掉的步骤名 → 成功后自动收尾：下载 `DS-Bot-ios-native-unsigned`、按 `DS-Bot-<version>-native-<sha>-unsigned.ipa` 改名、sha256 与 build-info 交叉验证、复制进 `D:\DSBotWorkspace\DS Bot iOS\artifacts`（Hermes 的转发任务盯那个目录）。每次判定都会打印原始字段（`run.conclusion` / `job.conclusion` / `steps` / `runner_id`），凭据可见。换 runner 不是杠杆：macos-15 没有 Xcode 26，两个 job 都会在选 Xcode 那步红。

**方案 C（未启用）：仓库内巡逻 workflow。** 形态：`ios-native-ipa-retry.yml`，`on: workflow_run` 监听「iOS native」完成，`if` 卡「dispatch 触发 + run `failure` + `run_attempt < N`」，调 jobs API 验上面的饿死签名，`gh run rerun --failed` 原 run 重跑（attempt+1，内置 `GITHUB_TOKEN` + `permissions: actions: write`，无 secret，同一 run id 保证据链）。**什么时候启用：出现定时/无人值守的出包才轮到它**——巡逻 workflow 不需要任何人的机器开机。今天所有 dispatch 都是人在场点的，人在场机器就在，脚本已覆盖；多一个每次 run 结束都会评估一遍的 workflow，目前只是噪声，所以不建。


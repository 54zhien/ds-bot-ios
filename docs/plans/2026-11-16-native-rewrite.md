# 原生重写（Swift）总体规划

决定：DS-Bot iOS 从 React Native 彻底转为原生（UIKit 为主、SwiftUI 局部），只做 iOS。
用户明确的前置条件：**连接稳定性优先于界面**。因此协议层先移植并互通验证，界面后做。

## 现状（重写的起点）

| 项 | 数值 |
|---|---|
| RN 界面代码 | `mobile/src` 49 个文件 / 8227 行 TS/TSX / 9 个页面 |
| 协议与加密 | `link/src` + `link/server` 15 个文件 / 2313 行 TS |
| 测试 | 25 个（mobile）+ 45 个（link） |
| 出包 | `.github/workflows/ios.yml`：expo prebuild → pod install → archive → 手工压 IPA → 9 条校验 |
| 产物 | 未签名 IPA，用户企业证书重签 |

## 不可协商的三条

1. **现有 RN 版本继续可用**：重写期间不删 `mobile/`，出包链继续保留，作为回退与对照。
2. **协议必须先互通**：Swift 端必须能与现有 Node relay/host 完成握手、RPC、断线重连，且与 TS 实现互通——这先于任何界面工作。
3. **每个阶段都出可测包**：不做「攒一个大版本」。

## 阶段与放行条件

### N0 协议层移植（唯一前置，先做）
- Swift 实现：Noise IK 握手（X25519 / ChaChaPoly / SHA-256，用 CryptoKit）、relay 帧编解码（base64url + JSON 信封）、RpcClient（超时、分片、并发上限）、心跳与看门狗、supervisor 退避。
- **验收**：与本地 Node relay + host 端到端跑通；用 TS 侧测试里的同一组向量做逐字节比对（握手 prologue、帧编码、counter 语义）；断网 10s / 90s / 重启 host 三种情况行为与 RN 版一致。
- 放行条件：`swift test` 全绿 + 真机与真实 relay 连通 + 断线场景通过。

### N1 单屏闭环（聊天）
- 原生聊天页：消息列表（分页、反转）、输入框（照 zen 的 Composer 结构：caret 定位占位符、UIVisualEffectView 表面、键盘时序动画）、发送/停止、断线与重连横幅。
- 验收：与 RN 版同屏对照，收发、滚动、重连一致；输入框手感对齐 zen。

### N2 其余页面
- 抽屉与团队列表、Bot 详情与设置各页、侧边对话、配对（扫码）、卡片（审批/密钥/视图）。
- 验收：逐页与 RN 版对照，功能不缺项。

### N3 收尾
- 推送与 NSE、崩溃兜底、性能与内存、最终验收清单。

## 工程形态

- 新目录 `native/`：XcodeGen 生成工程（`project.yml`），iOS 16.4 deployment target（与现有包一致），Swift 6。
- 新 workflow `ios-native.yml`：`xcodebuild archive`（CODE_SIGNING_ALLOWED=NO）→ 手工压 Payload → 与 RN 版同一套 9 条校验（未签名 / arm64 / bundle id / Frameworks / 无 __MACOSX）。
- **两个 workflow 并存**，产物命名区分：`DS-Bot-<ver>-native-unsigned.ipa` 与现有 `DS-Bot-<ver>-ios-unsigned.ipa`。
- 从 N1 起，native 包与 RN 包并行出，用户自行决定测哪个。

## 风险与对策

| 风险 | 对策 |
|---|---|
| 协议移植出现隐性不兼容（counter、分片边界、base64url 细节） | 以 TS 实现的测试向量为唯一标准，逐字节比对；不一致时以 TS 行为为准 |
| 一个 Bug 修两遍（RN 与 Swift） | 重写期只修 native；RN 冻结在当前版本只作回退 |
| CI 出包链重做失败 | 新 workflow 独立，不影响现有 ios.yml；先只求 archive 成功，再加校验 |
| 键盘/手势/滚动手感与 RN 版不同 | 以 zen 的实现为参照（同栈同框架），逐项对齐 |
| 时间不可控 | 每阶段单独放行，N0 不通过不进 N1 |

## 当前动作

1. Relay 出协议规格 + 机器可读测试向量（N0 的验收基准）
2. Mason 搭 native 工程骨架 + Swift 传输层
3. Freight 出 `ios-native.yml`，先跑通空壳 archive
4. Verdict 出「RN vs native 功能对照表」，作为 N1/N2 的验收清单

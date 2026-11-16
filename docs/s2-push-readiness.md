# S2 推送与 NSE：可执行准备清单

状态：只读准备。S1（原生工程能出包）未放行，S2 未开工；本文件不含代码改动，只记录现状、后台要准备什么、NSE 目标怎么进构建、以及哪些坑踩了就回不来。

取证范围：仓库 `ds-bot-ios`（main 工作区）+ 仓库外草稿目录 `s2-drafts/`（与 `ds-bot-ios` 同级）。所有结论来自 Windows 上读源码和本地 `node_modules`，没有任何 macOS prebuild / xcodebuild / 真机运行。
**验证等级分三档，全文按这档标注：**

| 档 | 含义 |
|---|---|
| 已核对 | 读过仓库或依赖里的实际代码/配置，能给出文件与行号 |
| 静态推断 | 依赖某个库的内部行为，代码读过，但没在真工具链跑过 |
| 未验证 | 只能在 macOS / 真机上得出结论，本文不给结论 |

---

## 0. 一页结论

1. 今天的包**与推送无关**：`mobile/app.json` 里没有 `aps-environment`（也没有 `ios.entitlements` 键）、没有 `UIBackgroundModes`、没有推送插件、没有 `expo-notifications`。CI 出的 IPA 只有一个 App target，重签只涉及 `DSBot.app`。
2. S2 的实质增量是**一个独立 target**（NSE），它由 config plugin 在 `expo prebuild` 阶段注入，不是 app.json 能声明的。现有 CI 的「Check the IPA」9 项断言对 appex 全部不适用——包会照常通过，等于没有防线。
3. 后台准备是**四个 App ID 侧的东西 + 一把 APNs key + 两个 In-House profile**。APNs key 只在发送端用，不进仓库、不进 IPA、不进 CI。
4. 环境只有一条规则：**`aps-environment` 由签名时带的 entitlement 决定**。企业 In-House 就是 `production`，发送端打 `api.push.apple.com`；写 `development` 会拿到 sandbox token，服务端按 production 发，回 `BadDeviceToken`。
5. 不可逆点集中在：bundle id、APNs key（只可下载一次）、App Group 名字、企业证书/profile 有效期。做错这些只能换新标识或重新签发。

---

## 1. 现状盘点

### 1.1 `mobile/app.json`：与推送相关的键

核对方式：读 `mobile/app.json`、`mobile/app.config.js`、`mobile/package.json`（已核对）。

| 键 | 现在 | 与推送的关系 |
|---|---|---|
| `expo.ios.bundleIdentifier` | `io.github.fei2411.dsbot` | 扩展必须是 `.push` 后缀；改包名要连扩展一起改 |
| `expo.ios.entitlements` | **不存在** | 没有它，prebuild 生成的 entitlements 里不会出现 `aps-environment`；当前包签出来也注册不了推送 |
| `expo.ios.infoPlist.UIBackgroundModes` | **不存在** | 缺 `remote-notification`，App 在后台被推送唤醒的能力没有声明 |
| `expo.ios.infoPlist` 其余键 | `CFBundleLocalizations`、`NSFaceIDUsageDescription`、`NSPhotoLibraryUsageDescription`、`NSLocalNetworkUsageDescription` | 与推送无关，但 CI 会校验其中三个 usage description 非空，S2 改 Info.plist 时别把它们弄丢 |
| `expo.ios.buildNumber` | 无（由 `app.config.js` 从 `ds-bot/package.json` 的 version 算出数字） | appex 的 `CFBundleVersion` 必须与主 App 完全一致，来源只能是这一个 |
| `expo.plugins` | `expo-secure-store`、`expo-camera`（注入 `NSCameraUsageDescription`）、`./plugins/android-release-signing.js`、`expo-build-properties`（iOS deploymentTarget 16.4） | 没有推送插件；S2 在这里加一行 `./plugins/ios-push.js` |
| `expo.ios` 其它 | `supportsTablet: true` | 扩展的 `TARGETED_DEVICE_FAMILY` 跟随它 |

`mobile/package.json`：没有 `expo-notifications`、没有 `expo-device`。全仓库搜 `aps-environment`、`UIBackgroundModes`、`remote-notification` 在 `mobile/` 的配置文件里为空（已核对）。

由此可推的两条（已核对）：
- 现在这套配置 prebuild 出来的工程**没有任何实质 entitlement 内容**（最坏是一个空 dict），CI 又用 `CODE_SIGN_ENTITLEMENTS=''` 归档，所以交付的未签名 IPA 里一个 entitlement 都没有——这正好符合"授权由用户签名时带入"的约定。
- `mobile/src/store.ts:16` 的 SecureStore 统一用 `WHEN_UNLOCKED_THIS_DEVICE_ONLY`。锁屏那一刻这类条目读不到，NSE 的密钥必须避开这个保护类。这是 S2 的第一个实现约束，不是可选项。

### 1.2 `s2-drafts/`：逐个文件，可用到什么程度

| 文件 | 是什么 | 直接用？ |
|---|---|---|
| `docs/2026-11-15-push-nse.md`（256 行） | 内部设计：为什么只有 NSE 能解密、App Group 与 Keychain 组是两种 entitlement、密钥布局、降级路径、签名顺序、探针读数表、§8 验证状态、§9 四个开放决策 | 作为设计输入可用。它明确自称静态推断，并已标注两处 node-xcode 发现。两处引用已失效：`docs/plans/2026-10-24-mobile-app.md` 在仓库里不存在（`docs/` 下没有 `plans/`）；`ios-resign-entitlements.md` 实际在 `_archive/` 下，且前提是"包内没有 NSE"，S2 之后会误导人 |
| `docs/ios-push-resign-guide.md`（242 行） | 给用户的重签说明：包内自查、两份 entitlement、`$(AppIdentifierPrefix)` 展开、先 `.appex` 后 `.app`、`-34018`/`-25300` 判断、无 Keychain 时的文件降级、一页清单 | 已经不缺 brief 要求的全部要点。**现在还不宜当成品交付**：它假定包里已有 `PlugIns/DSBotPush.appex`，而 S2 之前没有；包名也写的是 `DSBot-unsigned.ipa`，CI 实际产物是 `DS-Bot-<version>-ios-unsigned.ipa`。S2 落地后按真实产物校对一遍即可 |
| `modules/dsbot-push/expo-module.config.json`（6 行） | expo module 声明（apple / `DSBotPushModule`） | 内容正确，但**单靠它不会被打包**：`s2-drafts/modules/dsbot-push/` 下没有 `package.json`，Expo autolinking 认不出这个模块。这是缺件，见 §1.3 |
| `modules/dsbot-push/index.ts`（27 行） | JS 侧探针接口，`requireOptionalNativeModule('DSBotPush')`，返回 token/两个通道的状态 | 可用。只是探针，不是推送 API |
| `modules/dsbot-push/ios/DSBotPush.podspec`（17 行） | pod 定义；`source_files` 只含 `PushShared.swift` 与 `DSBotPushModule.swift`（`NotificationService.swift` 归扩展 target，不进 app） | 本地 pod 可用。`author = ''`、`homepage` 占位、`source = { :git => '' }`——`pod lib lint` 会挑这几处，`pod install` 不挑 |
| `modules/dsbot-push/ios/PushShared.swift`（127 行） | 共享密钥实现：Keychain（`AfterFirstUnlockThisDeviceOnly`）+ App Group 文件降级（`completeFileProtectionUntilFirstUserAuthentication`、排除备份）+ 日志 + 探针；`$(AppIdentifierPrefix)` 未展开时主动返回 nil | 是 S2 的起点，但 `startProbe()` 是探针不是正式读写。`appGroup` 兜底值硬编码 `group.io.github.fei2411.dsbot`，改包名要同步改 |
| `modules/dsbot-push/ios/NotificationService.swift`（34 行） | NSE 主体：当前只回填一行探针文案，**不解析 `e/k/s`、不做解密** | 骨架可用。真正的解密（CryptoKit X25519 + HKDF-SHA256 + ChaChaPoly）是 S2 的主体工作，草稿里还没有 |
| `plugins/ios-push.js`（233 行） | config plugin：写 app 的 entitlements（两个组 + `$(APS_ENVIRONMENT)`）、写 Info.plist（`UIBackgroundModes`、`DSBotAppGroup`、`DSBotKeychainGroup`）、用 node-xcode 加 `DSBotPush` target、把源文件与 plist/entitlements 落盘到 `ios/DSBotPush/` | 可用，方向正确，两处发现见 §3.3。**没有随附测试文件**：设计文档称"plugin 自检 21/21 通过"，但 `s2-drafts/` 里没有 `ios-push.test.js`，那 21 项今天复现不了 |
| `scripts/apns-probe.mjs`（76 行） | 发一条真实 APNs 推送（ES256 JWT + HTTP/2），或 `--payload` 打印同样 payload 给 `simctl push`；p8 从 `APNS_KEY_P8` 指向的文件读；`APNS_ENV=production` 切生产端点 | 可直接用。需要四个环境变量：`APNS_KEY_P8`（即 `[P8_PATH]`）、`KEY_ID`（`[APNS_KEY_ID]`）、`TEAM_ID`（`[TEAM_ID]`）、`DEVICE_TOKEN`。默认是 development 端点，企业包必须显式设 `APNS_ENV=production` |
| `src/push/probe.ts`（15 行） | RN 侧入口：只有 `EXPO_PUBLIC_DSBOT_PUSH_PROBE=1` 时才调 native 探针 | 可用。正式包不设这个变量就不会跑，但 native 的 `startProbe` 仍挂在模块里，S2 要决定是否保留 |

### 1.3 草稿缺件（S2 开工前必须补齐）

| 缺件 | 为什么必需 |
|---|---|
| `modules/dsbot-push/package.json` | Expo autolinking 按 package 发现本地模块；没有它 `npx expo prebuild` 不会把 `DSBotPush` 原生模块链进 app |
| `mobile/plugins/ios-push.test.js` | `npm test` 的 glob 是 `plugins/*.test.js`，现有 `plugins/release.test.js` 就是这种写法；补上测试才能让 plugin 的 pbxproj 改动进 CI 的必过项 |
| 解密实现 | `NotificationService.swift` 现在只回填探针文案 |
| device token 注册与上报 | 现在没有 token 的来源：要么引入 `expo-notifications`，要么在 `DSBotPushModule` 里自己做 `registerForRemoteNotifications` 并把 token 交给现有加密链路（设计文档 §9 决策 1 推荐前者） |
| 权限请求时机 | 设计文档 §9 决策 2：配对成功后、在上下文里问，不在首次启动问 |
| 发送端 seal | 电脑侧用设备公钥封包（X25519→HKDF→ChaChaPoly），本仓库里还没有 |

### 1.4 现有 CI 的校验点（`.github/workflows/ios.yml`，已核对）

构建链：checkout → setup-node 24 → 选 Xcode（<26 直接失败）→ `npm ci ../link` → `npm ci` → typecheck → test → `npx expo prebuild --platform ios --no-install` → `pod install` → 读 workspace/scheme（`ios.yml:158-168`）→ `xcodebuild archive`（`ios.yml:177-195`，`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGN_ENTITLEMENTS=''`）→ 手工打 zip（`ios.yml:203-221`）→ **Check the IPA**（`ios.yml:223-302`）→ build-info.json → 上传 ipa/sha256/build-info + dSYMs。

「Check the IPA」现在 9 条断言：IPA 里有 `Payload/<App>.app/Info.plist`；无 `__MACOSX`；`CFBundleIdentifier` 等于 app.json 里的值；四个 usage description 非空；`zh-Hans.lproj/InfoPlist.strings` 存在且含中文；`CFBundleVersion` 等于 `app.config.js` 算出的值；主二进制含 arm64；每个 `Frameworks/*.framework` 有二进制；主 App 未签名。

这 9 条**没有一条会看 appex**。加了 NSE 之后它们仍全部通过——所以 §3.4 的增量断言不是"优化"，是唯一能挡住"appex 没进包"的防线。

---

## 2. 苹果开发者后台要准备什么

### 2.1 清单（谁做、在哪个页面、填到哪）

| 项 | 值 / 位置 | 落到哪里 |
|---|---|---|
| Team ID | `[TEAM_ID]`（Membership details 页，10 位） | JWT 的 `iss`；entitlement 的 `com.apple.developer.team-identifier` 与 `application-identifier` 前缀；keychain 组前缀 |
| APNs Auth Key | Keys → "+" → 勾 APNs → 下载得 `[P8_PATH]`，记下 Key ID `[APNS_KEY_ID]`（10 位） | 只在发送端：`APNS_KEY_P8=[P8_PATH]`、`KEY_ID=[APNS_KEY_ID]`、`TEAM_ID=[TEAM_ID]`。**不进仓库、不进 IPA、不进 CI** |
| 主 App ID | `io.github.fei2411.dsbot`，勾 Push Notifications、App Groups、Keychain Sharing | 生成 `PROFILE_APP` |
| 扩展 App ID | `io.github.fei2411.dsbot.push`，勾 App Groups、Keychain Sharing，**不勾 Push Notifications** | 生成 `PROFILE_NSE` |
| App Group | 注册 `group.io.github.fei2411.dsbot`，两个 App ID 都要勾上 | 两个 profile 的 `com.apple.security.application-groups` |
| 签名证书 | 企业 `Apple Distribution`（In-House）+ 私钥导出的 p12 | 用户本地签名 |
| 描述文件 | 两个 In-House profile：`PROFILE_APP`、`PROFILE_NSE` | 用户本地签名 |

拿不到 Key ID 或丢了 p8 的后果：**p8 只能下载一次**，丢了只能撤销重建，撤销后所有用旧 key 的发送端立刻失效（见 §4.1）。

### 2.2 三个占位符分别填在哪

| 占位符 | 填在哪 | 判别 |
|---|---|---|
| `[TEAM_ID]` | JWT `iss`；entitlements 的 `application-identifier` 前缀、`team-identifier`；keychain 组前缀 | 与证书组织单位一致，也是 `security cms -D -i profile` 里 `application-identifier` 的点号前半段 |
| `[APNS_KEY_ID]` | JWT header 的 `kid`；`apns-probe.mjs` 的 `KEY_ID` | 后台 Keys 列表里那 10 位，与文件名 `AuthKey_XXXXXXXXXX.p8` 的 X 一致 |
| `[P8_PATH]` | 发送端读取的私钥路径 | 放在仓库外。仓库确实忽略了 `*.p8`（`mobile/.gitignore`），但依赖 ignore 规则保护私钥不是好习惯 |

APNs key 是 **team 级**的：一把 key 可以给该 team 下所有 App 发推送，不需要为每个 App ID 单独生成，也不参与重签。这与"证书必须和 App ID 配"是两件事。

### 2.3 sandbox / production 在企业证书下怎么对应

规则只有一条：**设备注册到哪个 APNs 环境，由它被签名时带的 `aps-environment` 决定；`aps-environment` 又必须被描述文件覆盖。** 所以环境不是"选"出来的，是描述文件决定的。

| 构建/分发方式 | profile 类型 | `aps-environment` | 发送端点 | token 属性 |
|---|---|---|---|---|
| Xcode Debug 装机调试（设备已登记） | Development | `development` | `https://api.development.push.apple.com` | sandbox token |
| 企业 In-House（本项目的全部交付） | In-House | `production` | `https://api.push.apple.com` | production token |
| Ad Hoc | Ad Hoc | `production` | `https://api.push.apple.com` | production token |
| App Store | App Store | `production` | `https://api.push.apple.com` | production token |

由此有两条对 S2 有直接影响的推论：

- **用企业证书签出来的包永远进不了 sandbox。** 想在 sandbox 上做早期联调，只能另做一份 Debug + Development profile 的包，而且设备要在账号里登记。企业包和 sandbox 混用 = 白折腾。
- 服务端按 `aps-environment` 选端点。同一个 token 打到错端点，苹果回 `400 BadDeviceToken`；topic 写错（写成 `.push`）回 `DeviceTokenNotForTopic`。

核对描述文件里的值：

```sh
security cms -D -i PROFILE_APP.mobileprovision > profile.plist
plutil -extract Entitlements.aps-environment raw profile.plist        # 期望 production
plutil -extract Entitlements.application-identifier raw profile.plist # 期望 [TEAM_ID].io.github.fei2411.dsbot
plutil -extract Entitlements.keychain-access-groups json -o - profile.plist
plutil -extract Entitlements.com.apple.security.application-groups json -o - profile.plist
```

触发 NSE 的最小 payload（`apns-probe.mjs` 默认发的就是这类）：

```json
{ "aps": { "alert": { "title": "DS Bot", "body": "…" }, "mutable-content": 1, "sound": "default" }, "e": "…", "k": "…", "s": "…" }
```

`mutable-content: 1` 是 NSE 被调用的前提；只有 `content-available` 的静默推送不会进 NSE，也就不会解密。`apns-topic` 用主 App 的 bundle id，不用扩展的。

### 2.4 `aps-environment` 在重签时必须保留——这句话的准确含义

交付的未签名 IPA **里面没有任何 entitlement**：CI 用 `CODE_SIGN_ENTITLEMENTS=''` + `CODE_SIGNING_ALLOWED=NO` 归档，包内没有 `_CodeSignature`，也没有嵌入的 entitlements blob。所以"保留"不是"包里已有、别删"，而是：

1. 用户重签时，**主 App 的 entitlements 必须显式写入 `aps-environment`**，值等于 `PROFILE_APP` 里的 `Entitlements.aps-environment`（企业 = `production`）。
2. 扩展的 entitlements **省略** `aps-environment`（扩展不注册推送；多写会让签名与 `PROFILE_NSE` 冲突）。
3. 用 `codesign -d --entitlements :- Payload/DSBot.app` 读回来复核；用 zsign 的 `-e` 时，提供的是**完整**替换文件，少一项就等于删一项能力。

漏写的现象：包能装、能开、通知权限能弹，`registerForRemoteNotifications` 直接失败，日志是 `no valid 'aps-environment' entitlement string found for application`，永远拿不到 token。这与"服务端没配"看起来一样，只能靠读 entitlement 区分。

---

## 3. NSE 目标要加什么

### 3.1 为什么它进不了 app.json

NSE 是一个独立 target，独立 bundle id、独立 `Info.plist`（`NSExtension`）、独立 entitlements、必须被嵌进 `DSBot.app/PlugIns/`。app.json 描述的是主 App，这些都不在它的表达范围里。Expo 的 config plugin 是 prebuild 阶段唯一被官方支持、且能改 `project.pbxproj` 的钩子，所以注入点是 **`expo prebuild`**（CI 的 "Generate the iOS project" 那一步，`ios.yml:132-133`）。

三种方案的取舍：

| 方案 | 与现有流水线 | 代价 |
|---|---|---|
| **config plugin + node-xcode 改 pbxproj（现方案）** | prebuild 内执行，产物是普通 Xcode 工程，`pod install`、`xcodebuild`、CI 全部原样 | 依赖 node-xcode 4.0.0 的内部结构；SDK 升级要复测；只能在 macOS 上真正验证 |
| prebuild 之后跑 xcodegen 重新生成工程 | 会丢掉 Expo 注入的 build settings 与 Pods 的 xcconfig 引用，`pod install` 的集成得重做 | 等于换工程生成器，S0 基线要跟着变 |
| 提交 `ios/`、手写 pbxproj | `mobile/.gitignore` 把 `/ios` 当生成目录；CI 每跑都 prebuild | 变成 bare 工作流，Expo SDK 升级手工合并，S2 范围外 |

结论：继续用 config plugin。**S2 在 `app.json` 的改动只有一行**——往 `plugins` 数组里加 `"./plugins/ios-push.js"`；其余全在 plugin 与模块目录里。

### 3.2 plugin 在哪些阶段做什么（已核对 `plugins/ios-push.js`）

| 阶段 | 动作 |
|---|---|
| `withEntitlementsPlist` | 主 App entitlements：`com.apple.security.application-groups` 加 `group.<bundleId>`；`keychain-access-groups` 加 `$(AppIdentifierPrefix)group.<bundleId>`；`aps-environment` = `$(APS_ENVIRONMENT)` |
| `withInfoPlist` | 主 App Info.plist：`UIBackgroundModes` 加 `remote-notification`；写入 `DSBotAppGroup`、`DSBotKeychainGroup`（后者保留 `$(`，供运行时判断是否展开） |
| `withXcodeProject` | 给主 target 每个配置设 `APS_ENVIRONMENT`（Debug→`development`，Release→`production`）；用 node-xcode `addTarget('DSBotPush','app_extension','DSBotPush', '<bundleId>.push')` 加 target，写 15 项 build settings，按去引号的名字判断是否已存在 |
| `withDangerousMod(['ios'])` | 把 `NotificationService.swift`、`PushShared.swift` 复制到 `ios/DSBotPush/`，生成 `DSBotPush-Info.plist`（`NSExtensionPointIdentifier = com.apple.usernotifications.service`、principal class `$(PRODUCT_MODULE_NAME).NotificationService`）与 `DSBotPush.entitlements`（两个组，无 `aps-environment`） |

扩展 target 的 build settings（plugin `:109-125`）：`PRODUCT_BUNDLE_IDENTIFIER`=`<bundleId>.push`、`INFOPLIST_FILE`、`CODE_SIGN_ENTITLEMENTS`、`APPLICATION_EXTENSION_API_ONLY=YES`、`SKIP_INSTALL=YES`、`IPHONEOS_DEPLOYMENT_TARGET` 复制自主 target（16.4）、`MARKETING_VERSION`=`config.version`、`CURRENT_PROJECT_VERSION`=`config.ios.buildNumber`、`SWIFT_VERSION=5.0`、`TARGETED_DEVICE_FAMILY`=`1,2`。

两条必须守住的 invariant：

1. **appex 的 `CFBundleVersion` 必须与主 App 逐字相同**（都来自 `app.config.js` 算出的数字）。不一致时安装报 bundle version 不匹配，而 CI 完全看不到。
2. **appex 必须被主 target 的 Copy Files phase 嵌入**（`dstSubfolderSpec = 13`）。这一步**不需要额外代码**：node-xcode 的 `addTarget` 对 `app_extension` 类型自动给第一个 target 建 Copy Files phase 并把产物加进去（`pbxProject.js:1578-1585`，已核对），并自动加 target dependency（`pbxProject.js:1621`）。

### 3.3 两处「未在 macOS 真实 prebuild 验证」的发现

两条都是在 Windows 上读 node-xcode 4.0.0 源码得出的**静态推断**；plugin 里已经写了规避代码，但规避本身没在真 prebuild 上跑过。

1. **`PBXTargetDependency` 段不存在时，依赖会被静默跳过。** `addTargetDependency` 只在 `PBXTargetDependency` 与 `PBXContainerItemProxy` 两个 section 都存在时才写入（`pbxProject.js:901-907`），新生成的 Expo 工程没有这两个 section，于是 `addTarget` 的依赖调用什么都不做，主 App 可以比扩展先构建。plugin 在加 target 之前先把两个 section 置为空对象（`plugins/ios-push.js:93-95`）绕开。
2. **target 名带引号会让二次 prebuild 重复加 target。** `addTarget` 把 name 存成 `"DSBotPush"`（带 pbxproj 引号，`pbxProject.js:1563-1566`），`pbxTargetByName` 因此找不到它；plugin 改用"去掉引号再比较"的查重（`plugins/ios-push.js:86-89`）。真 prebuild 跑两次是否仍只有一份 target/**未验证**。

附带一条读代码时的观察（同样是静态推断，影响面小）：`addToPbxCopyfilesBuildPhase` 通过 `buildPhaseObject('PBXCopyFilesBuildPhase','Copy Files',file.target)` 找 phase，而这个 phase 挂在主 target 上、`file.target` 指向扩展——匹配靠的是"section 里只有一个名为 Copy Files 的 phase"（`pbxProject.js:466-469`、`1151-1167`）。将来若再嵌第二个扩展或其它 Copy Files phase，appex 可能被塞进错的 phase。S2 加断言时顺手把"主 target 恰好有一个 dstSubfolderSpec=13 且 files 含 `DSBotPush.appex`"写进 pbxproj 检查里。

### 3.4 对「GitHub Actions 出未签名 IPA」意味着什么

**不需要变的：**

- 不加 workflow、不加 secret、不引入任何证书。runner 仍然没有签名材料，`CODE_SIGNING_ALLOWED=NO` + `CODE_SIGN_ENTITLEMENTS=''` 对两个 target 一起生效，包里 app 与 appex 都未签名。
- scheme 选择保持原样（`ios.yml:158-168`）：它按项目名精确匹配、并且已经排除 `Pods*`，同名的 `DSBotPush` scheme 顶不掉 `DSBot`。那段注释（`:155-157`，"a further target, such as a notification extension, must never be archived in its place"）要保留。
- 打包步骤（`zip -qryX Payload`）不用改：appex 在 `DSBot.app/PlugIns/` 下，会随 app 一起进 zip。
- dSYM 上传路径是目录（`ios.yml:357-365`），会自动带上 `DSBotPush.appex.dSYM`。
- 产物名、sha256、artifact 名不变。

**必须变的：`Check the IPA` 这 9 条对 appex 全是盲区。** 建议在现有断言之后追加（只写在文档里，S2 合入时才动 `ios.yml`）：

```sh
nse="$app/PlugIns/DSBotPush.appex"
test -d "$nse" || { echo "::error::the IPA has no PlugIns/DSBotPush.appex"; exit 1; }

test "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$nse/Info.plist")" = \
     "com.apple.usernotifications.service" || { echo "::error::not a notification service extension"; exit 1; }

app_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
nse_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$nse/Info.plist")"
test "$nse_id" = "$app_id.push" || { echo "::error::appex id $nse_id is not $app_id.push"; exit 1; }

# iOS refuses to install an extension whose version differs from the app.
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$nse/Info.plist")" = \
     "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" || exit 1
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$nse/Info.plist")" = \
     "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" || exit 1

exec_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$nse/Info.plist")"
test -f "$nse/$exec_name" || { echo "::error::the appex has no binary $exec_name"; exit 1; }
case "$(lipo -archs "$nse/$exec_name")" in *arm64*) ;; *) echo "::error::the appex is not arm64"; exit 1 ;; esac

# Signing happens in the user's tool; anything signed here would hide that step.
if codesign -dv "$nse" >/dev/null 2>&1; then echo "::error::the appex is signed"; exit 1; fi
test ! -e "$nse/_CodeSignature" || { echo "::error::the appex carries _CodeSignature"; exit 1; }
test ! -e "$nse/embedded.mobileprovision" || { echo "::error::the appex carries a profile"; exit 1; }

# The app group names must reach the device through Info.plist; the keychain one keeps the
# build variable on purpose, so the re-sign guide can tell the user to expand it.
/usr/libexec/PlistBuddy -c 'Print :DSBotAppGroup' "$app/Info.plist" | grep -Fqx "group.$app_id" || exit 1
/usr/libexec/PlistBuddy -c 'Print :DSBotKeychainGroup' "$app/Info.plist" | grep -q '\$(' || exit 1
/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes' "$app/Info.plist" | grep -qx "remote-notification" || exit 1
```

另外把 `build-info.json` 加两个字段（`ios.yml:309-332`）：`"has_nse": true`、`"nse_bundle_id": "<app_id>.push"`，用户在重签前能直接核对要签第二个 target。

**CI 永远发现不了的（只能 macOS/真机）**：pbxproj 里 embed phase 是否真生效、Swift 是否编过、`$(APS_ENVIRONMENT)` 是否被展开、NSE 是否真被调用、Keychain 跨进程是否读得到。CI 的职责只是"包的结构对了"，不是"推送能解"。

### 3.5 分支与基线

- NSE 相关的一切只落 `feat/ios-push-probe`；`main` 保持 S0 出包基线。混进 main 的后果是：出包失败时分不清是原生基线坏了还是 NSE 坏了。
- 合入前的最低门槛：CI 新增断言全绿 + 模拟器 `xcrun simctl push` 看到 NSE 日志 + 一次真机重签后锁屏见到明文。

---

## 4. 风险与不可逆点

### 4.1 不可逆（做错只能换标识或重签）

| 项 | 为什么回不去 | 预防 |
|---|---|---|
| bundle id / App ID | 创建后名字固定，只能新建；换 id 等于换一个 App，已装用户、钥匙串、App Group、推送 token 全部作废 | 现在就定死 `io.github.fei2411.dsbot` + `.push` |
| APNs key（.p8） | 私钥只可下载一次；撤销后所有用它的发送端立刻失效 | 生成后立刻离线存两处；`[P8_PATH]` 指向仓库外 |
| 企业证书 | 有效期到点后已安装的 App **打不开**（不是"提示过期"，是启动失败） | 到期前换新证书重签发版；把日期记进发布清单 |
| In-House profile | 过期后签不出新包、装不上新包 | 与证书一起维护 |
| App Group 名字 | 一旦写进已签发的 entitlement，改名 = 两个 target 的 entitlement 全改 + 全量重签；旧包与新包读不到同一份文件/keychain | 名字一次定死，改包名时同步改 |
| keychain 组前缀 | 前缀是 `[TEAM_ID].`；换 team 签同一份包，两个 target 的组串都对不上，`-34018` | 明确"用户的签名 team 必须与 entitlement 里的前缀一致" |
| 已注册的 device token | token 与 topic + 环境绑定；换环境、换 topic 都要全量重注册 | 服务端保存 token 时带上环境标记 |

### 4.2 会伪装成别的故障的（可逆，但排查成本高）

| 症状 | 真因 | 区分方法 |
|---|---|---|
| 能装、能开、通知能到，永远是兜底文案 | 先签了 `.app` 后签 `.appex`（后签的覆盖掉扩展） | 比较两份 `codesign -d --entitlements` 与该 appex 的签名时间 |
| 同上 | appex 根本没进包（embed phase 没生效） | `unzip -l` 看 `PlugIns/`；§3.4 的断言 |
| 同上 | 密钥用 `WHEN_UNLOCKED*` 保护类，锁屏读不到 | `PushShared` 里读写都用 `AfterFirstUnlockThisDeviceOnly`；探针通知会写 `keychain err` |
| 扩展日志 `-34018` | 组串没写、写成 `$(` 字面量、或两个 target 不同 team | 读两份 entitlement 的组串前缀 |
| 能授权、永远拿不到 token | `aps-environment` 缺、或写成 `development` 而 profile 是 production | `codesign -d --entitlements :- Payload/DSBot.app` |
| 有 token，发送回 `BadDeviceToken` | 端点与环境不配（production token 打到 sandbox），或 topic 写成了 `.push` | `apns-probe.mjs` 的 `APNS_ENV` 与 `apns-topic` |
| 本机改好了，CI 又变回去 | `ios/` 是生成目录，手改 pbxproj 下次 prebuild 就没了 | 一切改动走 plugin |

### 4.3 本项目特有的

1. **NSE 进 main = 基线污染。** 出包失败时分不清是原生基线坏了还是 NSE 坏了，这是 S0/S1 阶段的唯一信号来源。
2. **交付说明的版本必须跟包一起走。** `_archive/ios-resign-entitlements.md` 的前提是"包内没有 NSE"，一旦发出去的包里有 appex，那份旧说明会让人只签主 App——正好命中"能开但永不解密"。S2 发第一版带 appex 的包时，旧说明要归档标注，现行版本用 `s2-drafts/docs/ios-push-resign-guide.md`。
3. **探针代码不该进正式包。** `probe.ts` 有 `EXPO_PUBLIC_DSBOT_PUSH_PROBE` 开关，但 native `startProbe` 一直挂在模块上（会写 keychain、写日志文件）。S2 交付前要么摘掉，要么加编译期开关。
4. **用户侧的重签是交付的一半。** 未签名 IPA + 重签说明是同一个交付物；说明里任何一个占位符没写清，用户就只签一个 target。

### 4.4 本文的验证边界

- 依赖 node-xcode 内部行为的两条（§3.3）是**静态推断**，没有跑过 macOS prebuild。
- 扩展 target 能否被 `pod install` / `xcodebuild` 接受、Swift 能否编过、embed 是否真生效：**未验证**。
- APNs 实际投递、`-34018` 的实际出现条件、NSE 在锁屏时能读什么：**未验证**（需要真机 + 企业证书）。
- `mobile/app.json` 与两个 workflow 的现状是**已核对**（读的是当前工作区文件）。

---

## 5. 开工前 gate

- [ ] 后台：两个 App ID（主 + `.push`）建好，能力按 §2.1 勾选
- [ ] 后台：`group.io.github.fei2411.dsbot` 注册并在两个 App ID 上勾选
- [ ] 后台：APNs key 生成，`[P8_PATH]` 与 `[APNS_KEY_ID]` 记下并离线保存
- [ ] 导出 `PROFILE_APP`、`PROFILE_NSE`，用 §2.3 的命令确认 `aps-environment=production`、两个组都在
- [ ] 补 `modules/dsbot-push/package.json`
- [ ] 补 `mobile/plugins/ios-push.test.js`（让 `npm test` 覆盖 plugin）
- [ ] macOS 上先跑一次 `npx expo prebuild --platform ios --no-install` + `pod install`，确认工程能生成（不带 NSE，先证明基线可用）
- [ ] 同一台机器上再带 plugin 跑一次，确认：target 只有一份、Copy Files phase 有 `DSBotPush.appex`、`DSBotPush/` 下四个文件齐全
- [ ] CI 增加 §3.4 的断言（S2 合入前提）
- [ ] 重签说明按真实产物名、真实 `Info.plist` 内容校对一遍
- [ ] 决定 §1.3 的缺件由谁做（解密、token 上报、权限时机、发送端 seal）

---

## 附录 A：本文用到的只读命令

```sh
git -C ds-bot-ios status --short --branch          # 当前分支与未跟踪文件
node -e "const c=require('./mobile/app.json');console.log(JSON.stringify(c.expo.ios,null,2))"
node -e "const p=require('./mobile/package.json');console.log(Object.keys(p.dependencies).join('\n'))"
sed -n '223,302p' .github/workflows/ios.yml        # Check the IPA 的 9 条断言
grep -rn "aps-environment\|UIBackgroundModes" mobile/ --include='*.json'
ls -R ../s2-drafts                                  # 草稿目录（仓库外）
```

## 附录 B：占位符

| 占位符 | 含义 |
|---|---|
| `[TEAM_ID]` | 企业团队 10 位标识 |
| `[APNS_KEY_ID]` | APNs Auth Key 的 Key ID |
| `[P8_PATH]` | `.p8` 私钥文件路径（仓库外） |
| `PROFILE_APP` / `PROFILE_NSE` | 两个 In-House 描述文件 |
| `APP_GROUP_ID` | `group.io.github.fei2411.dsbot` |
| `KEYCHAIN_GROUP` | `[TEAM_ID].group.io.github.fei2411.dsbot`（重签时必须是展开后的字面量） |
| `DEVICE_TOKEN` | 设备 token（64 hex，production 环境的） |

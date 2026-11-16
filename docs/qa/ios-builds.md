# iOS 出包记录

只记**未签名 IPA**的成功构建，新的在上。工作流 `.github/workflows/ios.yml`（job `ipa`，产物 `DS-Bot-ios-unsigned`，保留 30 天）。

**口径**：以下数字不是从 CI 摘要抄的，是把下载到本机的 IPA 用 Python `zipfile` + `plistlib` 重新解包读出来的，sha256 也重算过一遍。

- entry 数 = zip 条目总数（含目录条目），`__MACOSX` 单列
- 签名痕迹 = 名字里带 `_CodeSignature` 或 `embedded.mobileprovision` 的条目数，必须是 0
- arm64 = 主二进制 `Payload/DSBot.app/DSBot` 的 Mach-O `cputype`（`0x0100000C`）
- Frameworks 数 = `Payload/DSBot.app/Frameworks/*.framework/` 的个数（本轮恒为 14：ExpoCamera、ExpoCameraBarcodeScanning、ExpoFileSystem、ExpoFont、ExpoImageManipulator、ExpoModulesCore、ExpoModulesJSI、ExpoModulesWorklets、React、ReactNativeDependencies、SDWebImage、SDWebImageWebPCoder、ZXingObjC、hermesvm）
- 玻璃符号 = 主二进制里 `ExpoGlassEffect` / `UIGlassEffect` 字符串出现次数。`ExpoGlassEffect` 是 static pod，编进主二进制，**不会**有独立 .framework
- `Xcode` 来自产物里的 `build-info.json`（`DSBOT_XCODE`，即 `xcodebuild -version | head -1`）；SDK 来自 Info.plist 的 `DTSDKName`

---

## run 4 · 43777451997 · ca37f59

- 时间：2026-11-15T23:56:05Z 创建（本地 11-16 07:56），job 23:56:08Z → 00:08:59Z，**12m51s**
- 触发：`workflow_dispatch`，`main` = `ca37f599987f5c54d0a0ba14fea9cfc34be80438`（fix: keep one field, lift it with the keyboard, float the surfaces）
- runner：`macos-26`（GitHub Actions 1000006490），node v24.22.3
- Xcode：**Xcode 26.6**，SDK `iphoneos26.5`（`DTPlatformVersion` 26.5）
- IPA：`DS-Bot-0.3.6-ios-unsigned.ipa`，**12,095,479 B**
- sha256：`2a62e7a9dadb662d3573df50b272b983885c16509c0af5bde375262659962539`
- 结构复核：231 entry / `__MACOSX` 0 / 签名痕迹 0 / arm64 / `io.github.fei2411.dsbot` / CFBundleVersion 300699 / MinimumOSVersion 16.4 / Frameworks 14 / 玻璃符号 `ExpoGlassEffect`×9、`UIGlassEffect`×2
- 本机副本：`artifacts/glass-run-43777451997/DS-Bot-ios-unsigned/`
- 链接：https://github.com/54zhien/ds-bot-ios/actions/runs/43777451997

## run 3 · 43733406230 · 405d9e2

- 时间：2026-11-15T16:04:36Z 创建（本地 11-16 00:04），job 16:04:40Z → 16:21:16Z，**16m36s**
- 触发：`workflow_dispatch`，`main` = `405d9e2da9b67df8c5aa7e63b060e6dcb499f2be`（fix: centre the glyphs and follow the zen composer geometry）
- runner：`macos-26`（GitHub Actions 1000006489），node v24.22.2
- Xcode：**Xcode 26.6**，SDK `iphoneos26.5`
- IPA：`DS-Bot-0.3.6-ios-unsigned.ipa`，**12,091,884 B**
- sha256：`bbc5508311ffac0cbef29e687f8c6481da20db7c8f27db95bde79e23d90acff2`
- 结构复核：231 entry / `__MACOSX` 0 / 签名痕迹 0 / arm64 / `io.github.fei2411.dsbot` / CFBundleVersion 300699 / MinimumOSVersion 16.4 / Frameworks 14 / 玻璃符号 `ExpoGlassEffect`×9、`UIGlassEffect`×2
- 本机副本：`artifacts/glass-run-43733406230/DS-Bot-ios-unsigned/`
- 链接：https://github.com/54zhien/ds-bot-ios/actions/runs/43733406230

## run 2 · 43728805624 · 5944470

- 时间：2026-11-15T15:14:57Z 创建（本地 23:14），job 15:15:01Z → 15:30:01Z，**15m00s**
- 触发：`workflow_dispatch`，`main` = `5944470e85747820486da3b97578d11d42479582`（feat: draw the iOS surfaces as Liquid Glass）
- runner：`macos-26`（GitHub Actions 1000006488），node v24.22.2
- Xcode：**Xcode 26.6**，SDK `iphoneos26.5`
- IPA：`DS-Bot-0.3.6-ios-unsigned.ipa`，**12,088,316 B**
- sha256：`ad4e95de54d333fb2922f0622fdcd39e923d47468be169f85267ca83dc9329be`
- 结构复核：231 entry / `__MACOSX` 0 / 签名痕迹 0 / arm64 / `io.github.fei2411.dsbot` / CFBundleVersion 300699 / MinimumOSVersion 16.4 / Frameworks 14 / 玻璃符号 `ExpoGlassEffect`×9、`UIGlassEffect`×2
- 本机副本：`artifacts/glass-run-43728805624/DS-Bot-ios-unsigned/`
- 链接：https://github.com/54zhien/ds-bot-ios/actions/runs/43728805624

## run 1 · 43714983425 · b356af0

- 时间：2026-11-15T12:39:46Z 创建（本地 20:39），job 12:39:52Z → 12:58:10Z，**18m19s**
- 触发：`workflow_dispatch`，`main` = `b356af08c109c7395f8b7186c098dd267416dd07`（build: ship the iOS app with an unsigned-IPA workflow）
- runner：`macos-26`（GitHub Actions 1000006487），node v24.22.2
- Xcode：**Xcode 26.6**，SDK `iphoneos26.5`
- IPA：`DS-Bot-0.3.6-ios-unsigned.ipa`，**12,068,137 B**
- sha256：`25e1ac31b8d45f0873f5f05e232448b858c198caa51b4f1cb4589c3d28625bf7`
- 结构复核：231 entry / `__MACOSX` 0 / 签名痕迹 0 / arm64 / `io.github.fei2411.dsbot` / CFBundleVersion 300699 / MinimumOSVersion 16.4 / Frameworks 14 / 玻璃符号 **0 / 0**
- 备注：基线包，`expo-glass-effect` 尚未进入依赖，主二进制里没有任何玻璃符号；run 2 起才带上
- 本机副本：`artifacts/first-ipa/DS-Bot-ios-unsigned/`
- 链接：https://github.com/54zhien/ds-bot-ios/actions/runs/43714983425

---

## 流水状态（2026-11-16 08:20 本地采样）

成功 4 次（run 1–4）。同一时段其余：run 5（`8b8ca0c`）in_progress、run 6（`271600f`）cancelled、run 7（`4d3764a`）cancelled、run 8（`7e409db`）pending。取消的都是被后一次 dispatch 顶掉，不是构建失败。

## 追加模板

```markdown
## run N · RUN_ID · sha7

- 时间：YYYY-MM-DDThh:mm:ssZ 创建（本地 …），job … → …，**XmXs**
- 触发：workflow_dispatch | tag ios-vX.Y.Z，`main` = `完整 sha`（commit subject）
- runner：`macos-26`（GitHub Actions …），node v…
- Xcode：**Xcode …**，SDK `iphoneos…`
- IPA：`DS-Bot-X.Y.Z-ios-unsigned.ipa`，**N,NNN,NNN B**
- sha256：`…`
- 结构复核：N entry / `__MACOSX` 0 / 签名痕迹 0 / arm64 / `io.github.fei2411.dsbot` / CFBundleVersion … / MinimumOSVersion … / Frameworks N / 玻璃符号 `ExpoGlassEffect`×N、`UIGlassEffect`×N
- 本机副本：`artifacts/<文件夹>/DS-Bot-ios-unsigned/`
- 链接：https://github.com/54zhien/ds-bot-ios/actions/runs/RUN_ID
```

校验命令见 [ios-release-runbook.md](ios-release-runbook.md) 第 5 节，出的数直接填进上面几行。

# iOS 出包 checklist（一页）

工作流 `.github/workflows/ios.yml`，job `ipa`。只出**未签名** IPA，签名在用户自己的工具里做。行号对应当前 main 上的 ios.yml。

## 1. 下手前

- [ ] `git status --porcelain` 干净；要发的 commit 已经在 `origin/main` 上（tag 打到远端 commit，工作区没提交的东西不会进包）
- [ ] `mobile/package-lock.json` 的改动已随 commit 提交（CI 用 `npm ci`，lock 与 package.json 不一致会当场失败）
- [ ] `pod install` 相关：`mobile/ios` 从不入库（`mobile/.gitignore:40`），CI 每次全新生成，不用手动清

## 2. 触发

dispatch（推荐，能钉 Xcode）：

```bash
gh workflow run ios.yml --ref main -f runner=macos-26 -f xcode_version=26.6
gh run watch <run-id> --exit-status
```

- `xcode_version` **必须显式写**。不填时 `:63-108` 会挑 `/Applications` 里版本号最大的 Xcode（beta 只 warning 不拦），出来的 Xcode 版本不可预期
- 该版本在镜像上不存在时，`:69-73` 直接 error 并打印可用列表
- `:103-107` 硬拦 Xcode major < 26：没有 iOS 26 SDK 就出不了 Liquid Glass，直接失败
- tag 路径：`git tag ios-v0.3.7 && git push origin ios-v0.3.7`（匹配 `:24` `ios-v*`）；**push 前要 Warden 点头**

## 3. 盯这几行（缺一行就是链接断了）

`pod install` 阶段（`:141-145`）必须看到：

```
Installing ExpoGlassEffect (58.0.5)
Installing ExpoBlur (58.0.6)
Installing RNCMaskedView (0.3.2)
```

前两个走 expo autolinking（模板 Podfile 的 `use_expo_modules!`），`RNCMaskedView` 走 RN CLI autolinking（同一 Podfile 的 `use_native_modules!`）。同批应该一起出现的其余 pod：`Expo`、`ExpoAsset`、`ExpoCamera`、`ExpoClipboard`、`EXConstants`、`ExpoCrypto`、`ExpoFileSystem`、`ExpoFont`、`ExpoHaptics`、`ExpoImageManipulator`、`ExpoImagePicker`、`ExpoKeepAwake`、`ExpoLocalAuthentication`、`ExpoModulesCore`、`ExpoModulesJSI`、`ExpoModulesWorklets`、`ExpoSecureStore`、`ExpoStatusBar`、`ExpoSystemUI`、`ExpoDomWebView`、`ExpoLogBox`。

另外两处指纹：

- `:112-121` `Report the toolchain` 打印 `iphoneos SDK 26.x` 与 `UIGlassEffect: present`
- `:296-302` `Check the IPA` 打印 `unsigned: confirmed` 和 `MinimumOSVersion: 16.4`

## 4. 挂了先看哪几步（按顺序，别从 Archive 开始瞎翻）

1. **Select Xcode**（`:63-109`）—— 版本不存在 / major < 26，日志里是 `::error::`，一眼能认
2. **Install pods**（`:141-145`）—— 上面三行缺哪个就查哪个包的 `expo-module.config.json` / podspec；`test -d Pods` 不过多半是 pod install 半途死
3. **Archive**（`:177-195`）—— 先看 `Show the build errors`（`:197-201`）抓的 `error:` 尾部 40 行，再看完整 `dist/xcodebuild.log`；签名参数已经全关（`:188-193`），这里的错误基本是编译或链接
4. **Package / Check the IPA**（`:203-302`）—— 报错文案自带原因：无 `Info.plist`、`__MACOSX`、bundle id 不符、缺 usage description、`zh-Hans/InfoPlist.strings` 空、CFBundleVersion 与 `app.config.js` 不符、非 arm64、framework 缺二进制、包被签名
5. 失败时自动上传 `DS-Bot-ios-build-log`（`:367-374`，7 天），artifact 里直接拿日志

## 5. 出包后的落点与复核

artifact（`:343-365`）：

| artifact | 内容 | 保留 |
|---|---|---|
| `DS-Bot-ios-unsigned` | `DS-Bot-<ver>-ios-unsigned.ipa`、`DS-Bot-ios-unsigned.sha256`、`build-info.json` | 30 天 |
| `DS-Bot-ios-dSYMs` | `DSBot.xcarchive/dSYMs` | 30 天 |

下载与归档约定：`gh run download <run-id> -n DS-Bot-ios-unsigned -D artifacts/glass-run-<run-id>/DS-Bot-ios-unsigned`，随后在 [ios-builds.md](ios-builds.md) 追加一条。

本地复核（Windows 就能跑，不依赖 Mac）：

```bash
python -c "import hashlib,zipfile,plistlib,os,sys; p=sys.argv[1]; z=zipfile.ZipFile(p); n=z.namelist(); i=plistlib.loads(z.read([x for x in n if x.endswith('.app/Info.plist')][0])); print('entries', len(n)); print('sha256', hashlib.sha256(open(p,'rb').read()).hexdigest()); print('bundle', i['CFBundleIdentifier'], 'build', i['CFBundleVersion'], 'minOS', i['MinimumOSVersion']); print('frameworks', sum(1 for x in n if x.endswith('.framework/'))); print('sig', sum(1 for x in n if '_CodeSignature' in x or 'mobileprovision' in x)); print('macosx', sum(1 for x in n if '__MACOSX' in x))" <ipa 路径>
```

合格线：`entries 231`、`sig 0`、`macosx 0`、`frameworks 14`、`bundle io.github.fei2411.dsbot`、`minOS 16.4`，且 `sha256` 与同目录 `.sha256` 文件一致。玻璃符号用主二进制里 `ExpoGlassEffect`/`UIGlassEffect` 字符串计数确认（static pod，没有独立 .framework）。

## 6. 红线

- 仓库里不放证书、profile、Apple 账号；`CODE_SIGNING_ALLOWED=NO` 那套参数不要动
- 出的是未签名包，`-exportArchive` 永远不要 reintroduce（它强制要求签名）
- 低版本 iOS（< 26）上玻璃是**降级渲染**，不是崩溃；`MinimumOSVersion` 由 `app.json:47-49` 的 `deploymentTarget` 决定，改它等于改这张验收表

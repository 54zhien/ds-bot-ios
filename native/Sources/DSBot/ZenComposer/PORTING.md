# ZenComposer 移植记录

本目录存放从 `C:\Users\Azusa\Desktop\Zen-Agent`（下称 zen）移植的输入框几何与动效代码。
每一件都逐字搬运，标识符改名单独记在下面的表里。

## 一、为什么不是 141 个文件

闭包数字经历了四次演变，每一次都被前一次的事实推翻，记在这里省得下一个人重跑：

| 口径 | 文件 / 行数 | 被否的原因 |
|---|---|---|
| 直接依赖 | 29 / 5,501 | 只在「直接依赖」这一层成立；传递闭包后前提被推翻 |
| 传递闭包（放任继续跟） | **141 / 24,532** | 拉进 `ZenDatabase`、`PersistenceStore+*`、`Migrations`、`KeychainSecretBackend`、`URLSessionHTTPTransport`、`SSEParser`、`DeepSeekProvider`、`AppShellModel`——等于把 zen 的整个应用层塞进本 module |
| 中途边界 | 56 / 10,896 | **不自足**：`SidebarSurfaceDecoration`(207)、`SidebarRailView`(162)、`SurfaceLiftController`(683) 在界内，但它们的引用在界外未闭合，第一层就可能编不过 |
| 视觉脊柱 | 12 / 727 | 见第三节：逐件证明后发现 4 件仍有真代码级外部引用，按止损线应丢件 |
| **本批执行（输入框全量）** | **43 / 6,922** | 用户改了口径：输入框相关的都要，包括菜单、引用、拖拽、控件入口与动画。`ComposerHostView` 的逐字闭包实测 **110 / 22,242**（多出的 67 件是 workspace 批与 runtime/persistence/provider/tool 脊柱），改由六处宿主替身收口，见第八节 |

141 那一次的具体数据（供复核，不必重跑）：闭包内 **464 个顶层类型**，与本仓库 `native/Sources` 撞车 **12 个**：

- **真冲突 2 个**：`JSONValue`（本仓库 `Frames.swift:83`；zen 全包核心类型，141 文件处处使用，改名等于全包重命名 + 两套 JSON 表示互转）、`Typography`/`TypographyRole`（本仓库 `DesignTokens.swift:204`）。
- **嵌套同形 10 个**（作用域不同，无需处理）：`Choice`、`CodingKeys`、`Entry`、`Item`、`Kind`、`Layout`、`Owner`、`Snapshot`、`State`、`Version`。

## 二、更正：「零网络耦合」只对直接 29 件成立

第一轮审计结论「闭包全静态、零网络与存储耦合」**只对直接的 29 个文件成立**。
按「继续往上跟直到闭包自足」的要求做传递闭包后，该结论不成立：闭包会依次拉进 Provider、Credential、Persistence、HTTP 四个子系统（见上表第二行）。
此后凡引用「零网络耦合」，必须写明范围是「直接 29 件」。

## 三、12 件清单与逐件自足性证明

逐件列出体内引用的外部符号，并按四档归类：① 声明体内部 ② 同文件 helper ③ 已批闭包内 ④ 都不在。

| 文件 | 来源行数 | 外部符号 | 档位 | 结论 |
|---|---|---|---|---|
| `ComposerGeometry` | 228 | `TypographyRole`（`:11` 属性、`:163`/`:217` 取 `.interfaceBody`） | **④ 都不在** | 需改名规则放行，见第四节 |
| `ComposerMorphGeometry` | 69 | 无（依赖均为③） | ③ | 可搬 |
| `ComposerMotionController` | 33 | 无 | ③ | 可搬 |
| `ComposerInputAnimation` | 26 | 无 | — | 可搬 |
| `ComposerBottomFadeLayer` | 34 | 无 | — | 可搬 |
| `WindowCornerGeometry` | 25 | 无 | — | 可搬 |
| `ComposerPresentationReducer` | 123 | 无 | — | 可搬（提供 `ComposerCollapseProgress`） |
| `ComposerDraftState` | 14 | `[QuoteReference]`、`[AttachmentReference]`（`:12-13`） | **④ 都不在** | 需放行两个 13/90 行的值类型文件 |
| `ComposerSelection` | 4 | 无 | — | 可搬 |
| `ComposerOverlayFocus` | 22 | `weak var host: ComposerHostView?`（`:7`、`:12`） | **④ 都不在** | 按止损线丢件（宿主不搬） |
| `ComposerTextView` | 38 | 无 | — | 可搬 |
| `ComposerContextAction` | 111 | `projection: RunProjection?`（`:30`） | **④ 都不在** | 需放行 `RunProjection`（100 行），其自身还引用 `AgentEvent`/`Records`，待核是否纯值类型 |

**当前状态：按止损线丢件后只剩 6 件 / 267 行**（`InputAnimation`、`BottomFadeLayer`、`WindowCornerGeometry`、`PresentationReducer`、`Selection`、`TextView`），而「玻璃成形 / 高度变化 / 展开收起」的几何全在被丢的 `Geometry` / `MorphGeometry` / `MotionController` 里。**等裁**。

> **结论（比上面任何数字都重要）**：**「闭包自足」在 zen 这份代码上不成立。** 按「发现闭包外引用就丢掉那一件、不许补文件」的止损线执行 B，12 件会**塌成 6 件**，而被丢掉的正是三件几何脊柱——玻璃成形、高度变化、展开收起三件事的几何全部消失，只余键盘起落与底部渐隐。看到「12 件」这个数字的人请先读这一句：**它不是 12 件，它是 12 件在止损线下必然塌缩的前提**，真正可执行的是「类型依附放行」把缺失的纯值类型补回来（规则见仓库提交说明与 Warden 裁定），或接受四件事里划掉三件。

`Typography` / `JSONValue` 检查：12 件内 `JSONValue` 引用 **0 次**；`Typography(Role)` 仅 `ComposerGeometry` 1 处（见上表）。

## 四、标识符改名表（只有标识符，没有取值）

| 旧名 | 新名 | 原因 |
|---|---|---|
| `Typography` | `ZenTypography` | 与本仓库 `DesignTokens.swift:204` 的 `struct Typography` 撞名 |
| `TypographyRole` | `ZenTypographyRole` | 同上，配套改名 |
| `TypographyFace` | `ZenTypographyFace` | 同上，配套改名（`Typography.swift` 整文件搬，不只 role） |
| `TypographyToken` | `ZenTypographyToken` | 同上，配套改名 |

改名只换标识符，不动取值、结构、顺序。除这两项外，本目录内不得再出现任何 zen 标识符改名，出现即视为改动 zen 代码，需另行报批。

## 五、归档：两段抠体的分析（本批改用替身，分析留档）

B 路线不搬 `ComposerHostView`，当时因此不移植下面两段。本批改口径后也没有搬它们，但原因变了：它们只在类型位置被引用，改用 `Boundary/` 的标记替身，见第八节表。分析留档，供将来真要接 workspace 时直接使用。

- `SurfaceClipView`（`ConversationSurfaceHost.swift:1043` 起，逐字 **169 行**）：体内引用中，`validationViewport` / `validationContent`（`:1045-1046`）与 `recordMovement(_:)`（`:1157`，含 `#if DEBUG`）属于**②同文件 helper**，需一并带上（约 +11 行）；**④ 都不在 = 0**。→ 可独立搬，约 180 行，远小于整文件 1,253 行。
- `ComposerDockContainer`（`WorkspaceComposerDock.swift:183`，逐字 **85 行**）：引用同文件的 `ComposerHostPortal`（`:94`）与 `WorkspaceComposerDockOutline`（`:176`）为**②**；`SidebarProgressPresentation`（`SidebarRailView.swift:64`）与 `SidebarSurfaceDecoration`（同文件 `:78`）为**③**；**④ = 0**。→ 可独立搬，带入约 182 行（`:94`–`:281`），小于整文件 282 行。

## 六、已知偏离（写在这里，不是遗忘）

| 偏离 | 原因 | 影响 |
|---|---|---|
| **字体非 zen 原字体**：用系统字 + 系统默认字重，不是 `AnthropicSansWebVariable-TextRegular` | zen 通过捆绑可变字体 + `kCTFontVariationAttribute`（`Typography.swift:27-36`、`:52-54`）表达字重；本仓库没有该字体 | 观感有差异；**几何不受影响**——`ComposerGeometry` 只消费 `pointSize`/`lineHeight` 数值（17 / `.body`，`Typography.swift:65`、`:92`），字号仍走 `UIFontMetrics(forTextStyle: .body)` 保住 Dynamic Type（`:107-108`） |
| **未移植：plus/primary 落位形变** | `ComposerMorphGeometry.interpolate` 的插值字段含 `plus` 与 `primary` 两个落位框，而它依赖的 `ComposerContextAction` 因 `RunProjection`（GRDB 记录类型，`Records.swift` 422 行）超出「类型依附放行」预算而丢 | 「展开收起」只做输入框高度/圆角/内距随折叠进度插值；plus 按钮从落位框飞向 primary 的动画**这次不做**，也不在宿主里另写近似实现 |
| `ComposerOverlayFocus` 曾按宿主替代 | 12 件口径时它引用 `ComposerHostView`，而宿主不搬 | **本批已作废**：宿主与它都已逐字搬入，焦点转移走 zen 原文（`Boundary/` 只补类型，不接管焦点） |
| **`WindowCornerGeometry` 加了可用性守卫** | `cornerConfiguration` 与 `effectiveRadius` 只有 iOS 26 才有，我们的部署目标是 16.4（`native/project.yml:11`） | iOS 26 上走 zen 原文；**16.4–25.x 回落**为 `layer.cornerRadius` + `maskedCorners`（回落代码我们写的，已注释标明）。部署目标未改 |
| **宿主替身六件**（`Boundary/`）：`SurfaceLiftController`、`ComposerDockContainer`、`SurfaceClipView`、`RunProjection`、`QuoteReferencePresentation` 对、`CredentialStoring` 协议 | 这六处 zen 都只在类型位置用到，而真类型分别拖进 workspace 批（5,444 行）、runtime/persistence 脊柱（9,022 行）、GRDB（`Records.swift` 486 行）与 Keychain（451 行） | lift 手柄每次 `arm`/`drag` 都拒绝；两个标记视图让 `is` / `as?` 两条分支永不成立；`RunProjection` 只有 `.runID`/`.isActive`/`.canStop`；`CredentialStoring` 只取协议原文。每件文件头有 `// deviation:` |
| **玻璃走 `ZenGlass`** | `UIGlassEffect` 与 `cornerConfiguration` 是 iOS 26 API，本批落地的四个 zen 文件共 13 处调用 | 26 上执行 zen 原文；16.4–25.x 回落 `UIBlurEffect(style: .systemThinMaterial)` + 连续圆角 `layer.cornerRadius`。zen 文件只在调用点不同，其余逐字，已列在各自文件头 |
| **最低系统抬到 iOS 17.0**（`native/project.yml:5/11/20/72`） | zen 输入框用到 `@Observable`（`ComposerActionMenuView.swift:7`）、两参 `.onChange(of:)`（`ComposerThinkingControl` 等 10 处）、`.phaseAnimator`（`ComposerThinkingTrack.swift:116`）、`registerForTraitChanges`（`ComposerHostView.swift:217`）——都只有 iOS 17 才有 | 逐处降级会引入重写：`@Observable`→`ObservableObject` 要重验观测语义，`.phaseAnimator` 要手写定时器状态机，两处都会变成「像 zen 但不是 zen」。抬目标是一行且可回退。**iOS 26 的 `#available` 守卫仍然必要**（玻璃与 `cornerConfiguration`），不得因为 17.0 而删除 |

## 七、批次

落 `native/Sources/DSBot/ZenComposer/`，保持 zen 的分层，一层一提交：

1. 几何与动效（6）
2. 状态与呈现（4）
3. 编辑器与控件（2）
4. 数据模型（3）

每层编过再进下一层。

本批改口径后追加五层，顺序是依赖序，不是重要性序：

5. 宿主边界六件（`Boundary/`）：`SurfaceLiftController`、`ComposerDockContainer`、`SurfaceClipView`、`RunProjection`、`QuoteReferencePresentation` 对、`CredentialStoring`
6. 排版整文件：`ZenTypography` 195 行，`ZenTypeMetrics` 改为读它的取值
7. 输入框 UI：菜单、思考控件、引用拖拽与引用架、编辑器、provider 取值词汇（30 件）
8. 玻璃三面与 `ZenGlass`、`ProviderError`
9. 宿主 `ComposerHostView`（1,116 行）

## 八、输入框全量移植（本批口径）

用户把口径改成「输入框相关的全搬，包括控件入口和动画」，Warden 放行的上限是 56 文件 / 10,900 行。实测后本批不是 56，是 **43 文件 / 6,922 行**，落到 `ZenComposer/` 下共 **53 个 swift 文件 / 6,879 行**（含本目录的边界与解析器，不含 `PORTING.md`）。

`ComposerHostView` 的逐字闭包是 **110 文件 / 22,242 行**，这次没有按它搬，原因是四处接缝只用到类型名：

| 接缝 | zen 位置 | 拖进来的东西 |
|---|---|---|
| `SurfaceLiftController` | `QuoteDragBridge.swift:31/125/132`，零业务调用 | `SurfaceLiftController` 707 行 + workspace 批 5,444 行 + pane/store/runtime 脊柱 |
| `ComposerDockContainer` | `ComposerHostView.swift:471`，一个 `is` | `WorkspaceComposerDock.swift` 282 行 |
| `SurfaceClipView` | `ComposerHostView.swift:482`，一个 `as?` | `ConversationSurfaceHost.swift` 1,253 行 |
| `RunProjection` | `ComposerContextAction.swift:30/38/39`，三个成员 | `Records.swift` 486 行（GRDB）+ `RequestConfigSeed` 200 + `CredentialTypes` 90 |

另有两处在落地时才发现：`QuoteShelfView:15` 要的 `QuoteReferencePresentation` 在 `ConversationTimeline.swift`，而它引用 12 个 GRDB 记录类型；`ModelProvider.swift:69` 的签名里出现 `any CredentialStoring`。两处都按替身处理，理由同上——本 module 没有 GRDB，也没有 Keychain 实现。

排版按「整文件搬 + 改名」，不再只搬 `TypographyRole`：`ZenTypeMetrics` 只保留解析，数值一律取自 `ZenTypography`，本目录里不存在第二份字号。


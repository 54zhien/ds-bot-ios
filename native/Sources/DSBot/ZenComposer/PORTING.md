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

`Typography` / `JSONValue` 检查：12 件内 `JSONValue` 引用 **0 次**；`Typography(Role)` 仅 `ComposerGeometry` 1 处（见上表）。

## 四、标识符改名表（只有标识符，没有取值）

| 旧名 | 新名 | 原因 |
|---|---|---|
| `Typography` | `ZenTypography` | 与本仓库 `DesignTokens.swift:204` 的 `struct Typography` 撞名 |
| `TypographyRole` | `ZenTypographyRole` | 同上，配套改名 |

改名只换标识符，不动取值、结构、顺序。除这两项外，本目录内不得再出现任何 zen 标识符改名，出现即视为改动 zen 代码，需另行报批。

## 五、归档：两段抠体的分析（本批不用）

B 路线不搬 `ComposerHostView`，因此下面两段表面宿主本批不移植。分析留档，供将来走 56 或 141 路线时直接使用。

- `SurfaceClipView`（`ConversationSurfaceHost.swift:1043` 起，逐字 **169 行**）：体内引用中，`validationViewport` / `validationContent`（`:1045-1046`）与 `recordMovement(_:)`（`:1157`，含 `#if DEBUG`）属于**②同文件 helper**，需一并带上（约 +11 行）；**④ 都不在 = 0**。→ 可独立搬，约 180 行，远小于整文件 1,253 行。
- `ComposerDockContainer`（`WorkspaceComposerDock.swift:183`，逐字 **85 行**）：引用同文件的 `ComposerHostPortal`（`:94`）与 `WorkspaceComposerDockOutline`（`:176`）为**②**；`SidebarProgressPresentation`（`SidebarRailView.swift:64`）与 `SidebarSurfaceDecoration`（同文件 `:78`）为**③**；**④ = 0**。→ 可独立搬，带入约 182 行（`:94`–`:281`），小于整文件 282 行。

## 六、批次

落 `native/Sources/DSBot/ZenComposer/`，保持 zen 的分层，一层一提交：

1. 几何与动效（6）
2. 状态与呈现（4）
3. 编辑器与控件（2）
4. 数据模型（3）

每层编过再进下一层。菜单、引用、拖拽三组本批不做——它们属于 `ComposerHostView`，我们只写薄宿主。

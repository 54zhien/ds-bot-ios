# 这版最容易坏的 8 个地方

> 按「坏的概率 × 一眼能看出来」排的。前三条我已经在代码里看到对不上的地方，优先级最高：**1 键盘、7 顶栏模糊带、2 渐隐方向**。
> 每条给一个 2 分钟内能做完的验法，验完直接在 `ios-glass-report-template.md` 对应条目里记结论。
> 行号以 `4d3764a` 为准，代码一动就对不上，认文件名和函数名。

## 1. 键盘与输入框交叠（两套键盘逻辑并存）

**哪里容易坏**：`Chat.tsx` 用 `keyboardWillChangeFrame` 自己算 `keyboardUp`，`side.tsx` 用 `keyboardWillShow/Hide` 各写一份，而两边外层还套着 `KeyboardAvoidingView behavior="padding"`；`composer.tsx` 又按 `keyboardUp` 单独加了一次底部 padding。KAV 抬一次、composer 再抬一次，是这版最容易叠出双倍空隙的地方。抽屉打开时会 `Keyboard.dismiss()`。

**怎么快速验**：聊天页点输入框，量输入框底边到键盘顶边的距离；切到侧边对话页重复；再把键盘换成手写或表情键盘（高度变化）看是否跳两次；最后在键盘弹起时拉抽屉。

**坏了的症状**：间距从 12pt 变 24pt 以上；输入框半截被键盘盖住；换键盘类型时输入框抖一下再回位；拉抽屉时键盘先收、界面闪一格。

**找谁**：Mason

## 2. 倒置列表的渐隐方向

**哪里容易坏**：聊天列表是 `FlatList inverted`，顶部渐隐不是列表的一部分，而是单独一层 `GlassFade edge="top"`，`side.tsx` 同款；`fade.tsx` 在 `edge=top` 时把 alpha 数组反转。方向写反、或者被塞进旋转容器里，就会出现在屏幕底部。

**怎么快速验**：开一个有 200 条消息的会话，滚到顶、滚到底、再停在中间；看那条模糊带在顶还是底；设置页和侧边对话各看一次。

**坏了的症状**：模糊带跑到屏幕底部（记下来，是 top/bottom 要对调）；顶部消息硬切、透明度突变；同时出现两条模糊带（说明 `scrollEdgeEffects` 与 `GlassFade` 都在生效）。

**找谁**：Mason 改 edge，Canvas 定观感

## 3. material 描边在浅色下的可见度

**哪里容易坏**：`material.tsx` 的 `rimSkin` 浅色是 1pt `rgba(0,0,0,0.08)`，选中态 1.5pt `0.35`。设置页卡片、分段控件、sheet 内的行全部走它，浅色主题 + 白底房间是最吃亏的组合。

**怎么快速验**：浅色主题、亮度拉满，看设置页卡片边缘和分段控件；选中一段再取消，看选中态是否认得出；同一屏切深色对比。

**坏了的症状**：卡片和背景糊成一片、边界消失；分段控件看不出哪个选中；深色下反而清楚（说明只调了深色那一半）。

**找谁**：Canvas

## 4. 玻璃在 iOS 18 上的降级

**哪里容易坏**：`glass.tsx` 顶层的 `native` 判断（`isGlassEffectAPIAvailable() && isLiquidGlassAvailable()`）为 false 时，走自绘的 fill + 斜向高光 + 描边 + 阴影。两条分支共用外层布局，但填充、圆角、阴影是各画各的。

**怎么快速验**：拿一台 iOS 17 或 18 的机器跑同一构建，依次看顶栏、输入框、dock、设置卡、四个 sheet；与 iOS 26 截图并排放。

**坏了的症状**：控件透明没底、文字浮在消息上；描边在深色下消失；圆角或高度跟 iOS 26 不一致；点击目标变小。

**找谁**：Mason 改逻辑，Canvas 看观感

## 5. formSheet 里的键盘遮挡

**哪里容易坏**：`ShellB.tsx` 把四个 sheet 从 modal 换成 `formSheet` + 系统 grabber，`Needs` 还是 `sheetAllowedDetents: [0.55, 1]`；`Pair.tsx`、`manage.tsx` 里各自套了 `KeyboardAvoidingView`。sheet 本身就是一层受键盘影响的容器，里面再套一层容易抵消。

**怎么快速验**：配对页点输入框输一半；Bot 详情改名字的输入框；Needs sheet 拉到半高再点输入；三处各输一次字、各下拉一次。

**坏了的症状**：输入框被键盘盖住、sheet 不跟着上移；下拉关闭时和键盘手势打架（先收键盘还是先关 sheet 不确定）；半高状态输入框被挤没。

**找谁**：Mason

## 6. 44 点击目标与 hitSlop

**哪里容易坏**：`icons.tsx` 的默认尺寸抬到了 20–24（Chevron/Sidebar/Side 24、Search/Plus 20、Gear 22、Stop 20），但命中区靠外壳：`GlassControl` 只有 `hitSlop=4`，`manage` 的返回键 8，`composer` 的按钮才是真正的 44×44。图标变大不等于能点中。

**怎么快速验**：单手拇指连点返回、Search、Plus、Chevron、Gear、Stop 各 5 次，记误触次数；再试顶栏返回和 bot 信息胶囊挨着的那块。

**坏了的症状**：图标看着大了但点不中、边缘要试两次；返回与相邻控件的点击区重叠，点胶囊返回了；Stop 图标 24 但按钮还是 44 以外的老尺寸。

**找谁**：Canvas 定尺寸，Mason 补 hitSlop

## 7. 顶栏模糊带是双份还是零份

**哪里容易坏**：`ShellB.tsx` 里 `screenOptions` 加了 `scrollEdgeEffects` 四边 `soft`，但紧挨着的注释写明：它需要原生导航栏才生效，`headerShown: false` 时什么也画不出来，真正干活的是 `GlassFade`。Chat 里 header 还挂在列表**之后**（先列表、后 header）。这版同时改了两处，最容易出现一条没有或两条都有。

**怎么快速验**：iOS 26 上滚聊天页看顶栏边缘的模糊渐变；再进设置页、侧边对话页各看一次；对比消息从玻璃下穿过的地方。

**坏了的症状**：一条模糊带都没有，消息硬切到顶栏；出现两条（一条在顶栏下、一条在屏幕底）；顶栏变全透明，标题压在消息上看不清。

**找谁**：Canvas

## 8. 多层 blur 的滚动性能

**哪里容易坏**：一次滚动里同时活着：原生 `GlassView`（顶栏、输入框、dock）、`GlassFade` 的 `BlurView` 套 `MaskedView`、倒置长列表、悬浮顶栏、以及每屏十几行气泡。ios-glass memo 里那块「blur 层过多」说的就是这里。

**怎么快速验**：200 条消息的会话连续滚 3 分钟，手摸机背、看电量掉幅；再杀后台重进，看首屏出得快不快。

**坏了的症状**：滚动掉帧、机背发烫、3 分钟掉电超 3%；被系统当内存压力杀掉（Jetsam）；进会话要等一两秒才出消息。

**找谁**：Mason，出包侧 Freight 确认是否 debug 构建

---

## 附：这 8 条与验收清单的对应

| 风险 | 对应验收条目 |
|---|---|
| 1 键盘交叠 | A4、A7、B7 |
| 2 渐隐方向 | A12、B2 |
| 3 描边浅色 | B1、B5 |
| 4 iOS 18 降级 | A10 |
| 5 formSheet 键盘 | A7、A8 |
| 6 44 目标 | B4 |
| 7 顶栏模糊带 | A12、B2 |
| 8 多层 blur 性能 | A3、A11、B8 |

符号化流程见 `docs/qa/symbolicate.md`；报告模板见 `docs/qa/ios-glass-report-template.md`。

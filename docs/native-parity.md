# RN → 原生功能对照（持续更新）

基准：仓库内冻结的 `mobile/src`，不是桌面端的全部功能。状态只按源码和验证证据填写；GitHub 编译不等于真机可用。

| 范围 | RN 基准 | 原生现状 | 下一项 |
|---|---|---|---|
| 配对与连接 | `screens/Pair.tsx`, `team/link.ts`, `store.ts`：扫码、粘贴、多电脑、重连、feed、通知补读 | 粘贴、多电脑记录/切换/删除、重连、feed 路径已写；未真机验 | 扫码、hello/notice、拒绝配对反馈 |
| 团队导航 | `nav/ShellB.tsx`, `nav/Drawer.tsx`, `screens/TeamList.tsx`：主 Bot tile、Bot/群列表、搜索、未读、创建入口 | 主 Bot/Bot/群列表与目标切换已写，待 CI；布局、未读、创建入口未齐 | 抽屉布局、预览、未读、创建入口 |
| Bot 聊天 | `screens/Chat.tsx`：最新页、旧页、feed、流式、发送、停止、滚动保持、待发消息 | 文本最新页/旧页、feed 补读、发送/停止；无流式、待发消息 | 完成消息闭环与同屏核对 |
| 聊天内容 | `screens/chat/items.tsx`, `markdown.tsx`, `view.tsx`：文本、Markdown、步骤、图片/文件、视图、历史卡片 | 仅纯文本与简化占位 | 按 kind 逐项渲染与打开附件 |
| 输入框 | `screens/chat/composer.tsx`：图片、发送/停止、展开卡片、键盘、原版图标 | 文本输入、发送/停止、材质、展开；未真机验 | 图片与键盘/尺寸对照 |
| 群聊 | `screens/Chat.tsx` 的 room 分支、`TeamList.tsx` | `room-chat` 文本读取、分页、发送/停止已写，待 CI | 群成员、消息形态及互动 |
| 待处理 | `screens/NeedsYou.tsx`, `screens/chat/dock.tsx`：问题、审批、密钥、卡片、浏览器交接 | 无 | 列表与可提交动作 |
| Bot 管理 | `screens/manage.tsx`：详情、编辑、新建、模型、记忆、计划、目录、用量、浏览器 | 无 | 导航及逐页 RPC |
| 群管理 | `screens/manage.tsx`：群详情、设置、新建 | 无 | 逐页 RPC |
| 侧边对话 | `screens/side.tsx` | 无 | 列表、新建、提问 |
| 设置 | `screens/Settings.tsx`, `settings-pages.tsx`：电脑、外观、语言、横幅、模型、连接器、能力、用量、密钥、位置、更新、关于 | 无 | 设置导航及逐页功能 |
| 通知 | RN 当前包的本地通知/横幅行为，`team/link.ts` 的 notices | 无 | 核对实际 RN 能力后移植 |

## 验收证据

- 协议向量和 relay/host 互通：见 `HANDOFF-2026-11-16.md` 的 run 号。
- 原生基本聊天代码：`6a49761`；Swift CI 37 项通过（run `43817669550`），未签名 IPA（run `43818471522`）。
- `1fe9c6e` 新增 feed 处理，Swift CI 通过（run `43819139451`）。
- 原生真机连接、收发、键盘、分页、后台恢复：尚无证据。

本表每完成一项都应更新到具体提交和验证 run，不以“页面存在”代替 RN 功能对照。

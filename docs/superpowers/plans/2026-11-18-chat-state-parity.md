# Chat State Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match the frozen RN chat's blocked Bot, computer use, and group goal surfaces in the native iOS chat.

**Architecture:** Project the relevant fields from the existing `state` response into small UIKit views. Keep RPC writes in `ChatViewController`, which already owns the selected target and live session; views report user actions through closures.

**Tech Stack:** Swift 6, UIKit, existing `JSONValue` and `BotAPI`, XcodeGen, macOS GitHub Actions.

**Spec:** `mobile/src/screens/Chat.tsx:355-402,472-578`; `docs/native-parity.md`.

## Global Constraints

- `mobile/` is frozen and remains the comparison source.
- Keep native changes on `feat/native-rn-basics`; do not merge or change RN packaging.
- Windows has no Xcode. Swift compilation and tests run in `.github/workflows/ios-native.yml`.
- Record compile/test, unsigned IPA, and device evidence separately.

## Review Focus

- A card for another Bot or room must not appear after switching targets.
- A stale RPC response must not overwrite a newer selected target.
- Computer use approval must send exactly `deny`, `once`, or `always` with the ask ID.
- The Stop action must use the current Bot ID, never a prior selection.
- A room goal with no stages must still show a meaningful title and status.

---

### Task 1: Blocked Bot repair surface

**Files:** Create `native/Sources/DSBot/BotBlockedView.swift`; modify `native/Sources/DSBot/ChatViewController.swift`; test `native/Tests/TransportTests/ChatStateCardTests.swift`.

**Interfaces:** `BotBlockedView.configure(bot: JSONValue, models: [JSONValue])`; closures `onProviders`, `onModel`, and `onTopUp` route the three RN repairs. `ChatViewController.refreshLatest` supplies the selected Bot and model catalog.

- [ ] Add a projection test for each RN blocked code and the matching repair action.
- [ ] Implement the blocked message and repair buttons; hide the surface outside the selected blocked Bot.
- [ ] Run push triggered Swift CI, inspect the exact test result, and commit the bounded change.

### Task 2: Computer use requests and active control

**Files:** Create `native/Sources/DSBot/ComputerUseView.swift`; modify `native/Sources/DSBot/ChatViewController.swift`; extend `ChatStateCardTests.swift`.

**Interfaces:** `ComputerUseView.configure(bot: JSONValue, live: JSONValue?)`; `onAnswer(id: String, answer: String)` and `onStop(botID: String)` feed `computer-app-answer` and `computer-stop` RPCs. Refresh after an action completes.

- [ ] Test ask filtering by Bot ID and the three answer payloads.
- [ ] Render asks and active app control above the composer without covering the existing pending dock.
- [ ] Run Swift CI and a same SHA unsigned IPA; record both outcomes.

### Task 3: Group goal status

**Files:** Create `native/Sources/DSBot/RoomGoalView.swift`; modify `native/Sources/DSBot/ChatViewController.swift`; extend `ChatStateCardTests.swift`.

**Interfaces:** `RoomGoalView.configure(goal: JSONValue?)` shows the RN title, current status, stage count, progress segments, and expandable stage list. It receives only the selected room's `goal`.

- [ ] Test drafting, active, paused, stopped, complete, and empty-stage projections.
- [ ] Render the goal below the status bar and keep the message list scrollable.
- [ ] Run Swift CI and a same SHA unsigned IPA; record both outcomes and update `docs/native-parity.md`.

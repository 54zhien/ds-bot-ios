import XCTest
@testable import DSBot

/// The drawer's list is one set of conversations shown in two groups: the current and
/// pinned ones with a single check, the rest with a relative time, and a fold row that
/// has to stay put. These hold the structure the form settled on.
@MainActor
final class SidebarDrawerContentTests: XCTestCase {
    private func conversations(_ count: Int) -> [SidebarConversation] {
        (0..<count).map { index in
            SidebarConversation(
                target: ChatTarget(kind: .bot, id: "bot-\(index)", name: "Bot \(index)"),
                look: CharacterMarks.look(shape: "moon", color: "violet"),
                lastAt: 1_700_000_000_000 - Double(index) * 60_000)
        }
    }

    private func agent(_ index: Int) -> SidebarAgent {
        SidebarAgent(target: ChatTarget(kind: .bot, id: "agent-\(index)", name: "Agent \(index)"),
                     look: CharacterMarks.look(shape: "star", color: "magenta"))
    }

    private func checked(_ content: SidebarDrawerContent) -> [SidebarConversationRow] {
        (content.currentRows + content.earlierRows).filter(\.isCurrent)
    }

    /// One check, on the conversation the reader is in — never a second one.
    func testTheOpenConversationWearsTheOnlyCheck() {
        let content = SidebarDrawerContent()
        let list = conversations(4)
        content.configure(deviceName: "Mac", connected: true,
                          conversations: list, current: list[1].target, agents: [])
        XCTAssertEqual(checked(content).count, 1)
        XCTAssertEqual(checked(content).first?.conversation?.target, list[1].target)
        XCTAssertEqual(content.currentRows.count, 1, "the open one heads the first group")
    }

    /// Choosing another row is switching conversations: the check follows, and the row
    /// that had it loses it.
    func testChoosingAnotherRowMovesTheCheck() {
        let content = SidebarDrawerContent()
        let list = conversations(4)
        content.configure(deviceName: "Mac", connected: true,
                          conversations: list, current: list[0].target, agents: [])
        var chosen: ChatTarget?
        content.onSelect = { chosen = $0 }
        guard let row = content.earlierRows.first(where: { $0.conversation?.target == list[2].target })
        else { return XCTFail("the third conversation should be in the earlier group") }

        content.select(row)
        XCTAssertEqual(chosen, list[2].target)
        XCTAssertEqual(checked(content).count, 1)
        XCTAssertTrue(row.isCurrent)
    }

    /// Ten recent ones, the rest behind a row that does not go away when it is used.
    func testTheEarlierGroupFoldsToTenAndKeepsItsWayBack() {
        let content = SidebarDrawerContent()
        let list = conversations(14)
        content.configure(deviceName: "Mac", connected: true,
                          conversations: list, current: list[0].target, agents: [])
        XCTAssertEqual(content.earlierRows.count, SidebarDrawerContent.historyWindow)
        XCTAssertEqual(content.historyToggle.hiddenCount, 3)
        XCTAssertFalse(content.historyToggle.isHidden)

        content.toggleHistory()
        XCTAssertEqual(content.earlierRows.count, 13, "the tail is shown")
        XCTAssertEqual(content.historyToggle.hiddenCount, 3)
        XCTAssertFalse(content.historyToggle.isHidden, "the way back is still there")

        content.toggleHistory()
        XCTAssertEqual(content.earlierRows.count, SidebarDrawerContent.historyWindow)
    }

    /// One device pixel between the list and the grid, and the controls sit over the
    /// list rather than inside it.
    func testTheGridIsSeparatedAndTheControlsFloat() {
        let content = SidebarDrawerContent()
        content.frame = CGRect(x: 0, y: 0, width: 340, height: 800)
        content.configure(deviceName: "Mac", connected: true, conversations: conversations(2),
                          current: nil, agents: [agent(0), agent(1), agent(2), agent(3), agent(4)])
        content.layoutIfNeeded()

        XCTAssertEqual(content.grid.visibleTiles.count, 5)
        XCTAssertEqual(content.hairline.hairlineHeight,
                       1 / max(1, content.traitCollection.displayScale), accuracy: 0.0001)
        XCTAssertEqual(content.scrollView.contentInset.bottom, SidebarDrawerContent.floatInset)
        XCTAssertFalse(content.settingsGlass.isDescendant(of: content.scrollView))
        XCTAssertFalse(content.searchGlass.isDescendant(of: content.scrollView))
    }

    /// The time column has no upstream, so it is the platform's formatter — and it has
    /// to answer in the app's language, not the device's.
    func testRelativeTimeMovesWithTheAge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = SidebarDrawerContent.relativeTime(now.timeIntervalSince1970 * 1000 - 60_000, now: now)
        let old = SidebarDrawerContent.relativeTime(now.timeIntervalSince1970 * 1000 - 86_400_000, now: now)
        XCTAssertFalse(recent.isEmpty)
        XCTAssertNotEqual(recent, old)
    }
}

import XCTest
@testable import DSBot

/// G4: the computer's flat layout reaches the phone. items.tsx:317-327 lays a
/// Bot row straight on the page colour with no bubble; a user row keeps its own.
final class FlatLayoutTests: XCTestCase {
    private func botRow() -> ChatRow {
        ChatRow(.object(["kind": .string("bot"), "text": .string("Working on it")]))
    }

    private func userRow() -> ChatRow {
        ChatRow(.object(["kind": .string("user"), "text": .string("Hi")]))
    }

    @MainActor func testFlatDropsTheBotBubbleAndKeepsTheUserOne() {
        let cell = ChatMessageCell(style: .default, reuseIdentifier: nil)
        cell.configure(botRow(), flat: true)
        XCTAssertEqual(cell.bubbleFillColor, .clear)
        XCTAssertEqual(cell.bubbleCornerRadius, 0)

        cell.configure(userRow(), flat: true)
        XCTAssertEqual(cell.bubbleFillColor, ThemeStore.palette(trait: cell.traitCollection).user)
        XCTAssertEqual(cell.bubbleCornerRadius, Radius.bubble)
    }

    @MainActor func testBubbleLayoutKeepsTheBotRowsRoundedSurface() {
        let cell = ChatMessageCell(style: .default, reuseIdentifier: nil)
        cell.configure(botRow(), flat: false)
        XCTAssertEqual(cell.bubbleCornerRadius, Radius.bubble)
    }

    @MainActor func testAReusedCellLeavesFlatWhenThePreferenceGoesBack() {
        let cell = ChatMessageCell(style: .default, reuseIdentifier: nil)
        cell.configure(botRow(), flat: true)
        XCTAssertEqual(cell.bubbleCornerRadius, 0)
        cell.configure(botRow(), flat: false)
        XCTAssertEqual(cell.bubbleCornerRadius, Radius.bubble)
    }
}

import XCTest
@testable import DSBot

/// items.tsx gives every message row a surface of its own: a Bot row sits on
/// p.bubble (:296, :305, :332), a user row on p.user, photos stand alone (:248),
/// a settled card keeps p.card, and the flat layout puts the row on the page
/// colour (:321 bg={p.main}). Native used to draw Bot rows as bare text.
final class MessageBubbleTests: XCTestCase {
    private func makeCell() -> ChatMessageCell {
        ChatMessageCell(style: .default, reuseIdentifier: nil)
    }

    @MainActor func testABotRowSitsOnTheBubbleColour() {
        let cell = makeCell()
        cell.configure(ChatRow(.object(["kind": .string("bot"), "text": .string("Working")])))
        let palette = ThemeStore.palette(trait: cell.traitCollection)
        XCTAssertEqual(cell.bubbleFillColor, palette.bubble)
    }

    @MainActor func testAFlatBotRowSitsOnThePageColour() {
        let cell = makeCell()
        cell.configure(ChatRow(.object(["kind": .string("bot"), "text": .string("Working")])), flat: true)
        let palette = ThemeStore.palette(trait: cell.traitCollection)
        XCTAssertEqual(cell.bubbleFillColor, palette.main,
                       "flat rows use the page colour, not transparency: a clear row shows the list behind it")
    }

    @MainActor func testAUserRowKeepsItsOwnInk() {
        let cell = makeCell()
        cell.configure(ChatRow(.object(["kind": .string("user"), "text": .string("Hi")])))
        let palette = ThemeStore.palette(trait: cell.traitCollection)
        XCTAssertEqual(cell.bubbleFillColor, palette.user)
    }

    @MainActor func testAPhotosOnlyRowHasNoSurface() {
        let cell = makeCell()
        let row = ChatRow(.object([
            "kind": .string("user"),
            "imageRefs": .array([.object(["attachmentId": .string("photo-1")])]),
        ]))
        cell.configure(row)
        XCTAssertEqual(cell.bubbleFillColor, .clear)
    }

    @MainActor func testASettledCardKeepsTheCardSurface() {
        let cell = makeCell()
        let row = ChatRow(.object([
            "kind": .string("closed"),
            "question": .object(["question": .string("Continue?")]),
            "closed": .string("replied"),
        ]))
        XCTAssertNotNil(row.settled, "the row must draw a card for this test to mean anything")
        cell.configure(row)
        let palette = ThemeStore.palette(trait: cell.traitCollection)
        XCTAssertEqual(cell.bubbleFillColor, palette.card)
    }

    @MainActor func testANoticeRowStaysBare() {
        let cell = makeCell()
        cell.configure(ChatRow(.object(["kind": .string("event"), "text": .string("Working")])))
        XCTAssertEqual(cell.bubbleFillColor, .clear)
    }
}

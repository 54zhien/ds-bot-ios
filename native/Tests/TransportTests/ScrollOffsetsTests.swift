import XCTest
@testable import DSBot

final class ScrollOffsetsTests: XCTestCase {
    func testAChatComesBackToWhereItWasLeft() {
        var book = ScrollOffsetBook()
        book.keep(420, for: "c:bot:a")
        XCTAssertEqual(book.offset(for: "c:bot:a"), 420)
    }

    func testAnotherChatInheritsNothing() {
        var book = ScrollOffsetBook()
        book.keep(420, for: "c:bot:a")
        XCTAssertNil(book.offset(for: "c:bot:b"))
        XCTAssertNil(book.offset(for: "c:room:a"))
    }

    func testTheOldestChatFallsOutAtTheCap() {
        var book = ScrollOffsetBook(capacity: 3)
        book.keep(1, for: "a")
        book.keep(2, for: "b")
        book.keep(3, for: "c")
        book.keep(4, for: "a")
        XCTAssertEqual(book.offset(for: "a"), 4)
        book.keep(5, for: "d")
        // b was the oldest after a moved to the newest end.
        XCTAssertNil(book.offset(for: "b"))
        XCTAssertEqual(book.offset(for: "c"), 3)
        XCTAssertEqual(book.offset(for: "d"), 5)
    }

    func testAPositionOnlyLandsOnTheChatItWasRecordedFor() {
        var pending = PendingScroll()
        pending.expect(420, for: "c:bot:a")
        XCTAssertNil(pending.take(for: "c:bot:b"), "a different chat must open at the bottom")
        // Taking it for the wrong chat also forgets it, so it cannot surface later.
        XCTAssertNil(pending.take(for: "c:bot:a"))
    }

    func testTheRecordedChatTakesItsPositionOnce() {
        var pending = PendingScroll()
        pending.expect(420, for: "c:bot:a")
        XCTAssertEqual(pending.take(for: "c:bot:a"), 420)
        XCTAssertNil(pending.take(for: "c:bot:a"), "a position is spent once it is used")
    }

    func testAFirstVisitHasNothingWaiting() {
        var pending = PendingScroll()
        pending.expect(nil, for: "c:bot:a")
        XCTAssertNil(pending.take(for: "c:bot:a"))
    }

    /// A push opens a chat at its newest row, so the caller arms no position even
    /// though the book still remembers one for that chat.
    func testAPushArmsNoPositionForAChatThatHasOne() {
        var book = ScrollOffsetBook()
        book.keep(420, for: "c:bot:a")
        var pending = PendingScroll()
        pending.expect(nil, for: "c:bot:a")
        XCTAssertNil(pending.take(for: "c:bot:a"))
        // The recorded position survives for the next ordinary visit.
        XCTAssertEqual(book.offset(for: "c:bot:a"), 420)
    }
}

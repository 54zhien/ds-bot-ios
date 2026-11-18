import XCTest
@testable import DSBot

/// An event's row shows until the read replaces it, and never draws twice: the
/// buffer dedups on the chat plus its sequence, the field RN's own append check
/// reads (Chat.tsx:255). The on-device feel — another window's message
/// appearing before the poll — is a device check.
final class ChatFeedBufferTests: XCTestCase {
    private func message(kind: String = "bot", seq: Int, text: String) -> JSONValue {
        .object([
            "sessionId": .string("s-1"),
            "item": .object([
                "kind": .string(kind),
                "name": .string("Bot"),
                "text": .string(text),
                "seq": .number(Double(seq)),
                "time": .number(1_000),
            ]),
        ])
    }

    func testAnEventBecomesAPendingRow() {
        var buffer = ChatFeedBuffer()
        let row = buffer.feed(message(seq: 7, text: "hello"), for: "s-1")
        XCTAssertEqual(row?.text, "hello")
        XCTAssertEqual(buffer.pending(among: []).count, 1)
    }

    func testTheSameSequenceNeverDrawsTwice() {
        var buffer = ChatFeedBuffer()
        XCTAssertNotNil(buffer.feed(message(seq: 7, text: "one"), for: "s-1"))
        XCTAssertNil(buffer.feed(message(seq: 7, text: "one again"), for: "s-1"),
                     "the sequence is already pending, so the repeat is not a new row")
        XCTAssertEqual(buffer.pending(among: []).count, 1)
    }

    func testOurOwnPendingSendSuppressesItsEcho() {
        var buffer = ChatFeedBuffer()
        // The host echoes our send back as a message event; the outbox row already
        // draws it, so the echo would show the same message twice until the read.
        XCTAssertNil(buffer.feed(message(kind: "user", seq: 7, text: "mine"), for: "s-1", sendsPending: true))
        XCTAssertEqual(buffer.pending(among: []).count, 0)
        // With nothing of ours in flight, another window's user message is still
        // worth showing ahead of the read.
        XCTAssertNotNil(buffer.feed(message(kind: "user", seq: 8, text: "theirs"), for: "s-1"))
    }

    func testARowTheLoadedPageAlreadyCarriesIsNotShown() {
        var buffer = ChatFeedBuffer()
        _ = buffer.feed(message(seq: 7, text: "hello"), for: "s-1")
        // The same item, as the page read would render it: same seq, same fields.
        let loaded = [ChatRow((message(seq: 7, text: "hello")["item"] ?? .null))]
        XCTAssertEqual(buffer.pending(among: loaded).count, 0,
                       "the poll won the race, so the confirmed row stays the only one")
    }

    func testAnotherChatsEventIsIgnored() {
        var buffer = ChatFeedBuffer()
        let other = message(seq: 7, text: "hi")
        let row = buffer.feed(other, for: "s-2")
        XCTAssertNil(row)
        XCTAssertTrue(buffer.rows.isEmpty)
    }

    func testAnEventWithoutAnItemIsIgnored() {
        var buffer = ChatFeedBuffer()
        XCTAssertNil(buffer.feed(.object(["sessionId": .string("s-1")]), for: "s-1"))
        XCTAssertNil(buffer.feed(.object([:]), for: nil))
        XCTAssertNil(buffer.feed(.null, for: "s-1"))
    }

    func testTheReadThatLandsClearsTheBuffer() {
        var buffer = ChatFeedBuffer()
        _ = buffer.feed(message(seq: 7, text: "hello"), for: "s-1")
        buffer.clear()
        XCTAssertEqual(buffer.pending(among: []).count, 0)
        // And a new event is accepted again.
        XCTAssertNotNil(buffer.feed(message(seq: 8, text: "again"), for: "s-1"))
    }
}

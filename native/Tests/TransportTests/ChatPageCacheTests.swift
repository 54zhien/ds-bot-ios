import XCTest
@testable import DSBot

/// Switching back to a chat renders its page on the first frame, which is only as
/// good as the cache keeping the right page, dropping the stale one and evicting
/// the one nobody looked at. The React Native side pins the same rules (chat-cache.ts).
final class ChatPageCacheTests: XCTestCase {
    private final class Clock {
        var seconds: Double = 0
    }

    private func cache(limit: Int = 16, maxAge: TimeInterval = 5 * 60, clock: Clock? = nil) -> ChatPageCache {
        guard let clock else { return ChatPageCache(limit: limit, maxAge: maxAge) }
        return ChatPageCache(limit: limit, maxAge: maxAge) { Date(timeIntervalSince1970: clock.seconds) }
    }

    private func row(_ text: String) -> ChatRow {
        ChatRow(.object(["kind": .string("bot"), "text": .string(text)]))
    }

    func testAStoredPageComesBackWhole() {
        let cache = ChatPageCache()
        cache.store(
            key: "h:bot:1", older: [row("older")], rows: [row("one"), row("two")],
            cursor: .number(5), sessionID: "s-1")
        let entry = cache.retrieve("h:bot:1")
        XCTAssertEqual(entry?.rows.map(\.text), ["one", "two"])
        XCTAssertEqual(entry?.older.map(\.text), ["older"])
        XCTAssertEqual(entry?.cursor, .number(5))
        XCTAssertEqual(entry?.sessionID, "s-1")
    }

    func testKeysKeepChatsApart() {
        let cache = ChatPageCache()
        cache.store(key: "h:bot:1", older: [], rows: [row("a")], cursor: nil, sessionID: "s-1")
        cache.store(key: "h:room:2", older: [], rows: [row("b")], cursor: nil, sessionID: "s-2")
        XCTAssertEqual(cache.retrieve("h:bot:1")?.rows.map(\.text), ["a"])
        XCTAssertEqual(cache.retrieve("h:room:2")?.rows.map(\.text), ["b"])
        XCTAssertNil(cache.retrieve("h:bot:3"))
    }

    func testTheLeastRecentlyUsedPageIsTheOneEvicted() {
        let cache = self.cache(limit: 2)
        cache.store(key: "a", older: [], rows: [row("a")], cursor: nil, sessionID: nil)
        cache.store(key: "b", older: [], rows: [row("b")], cursor: nil, sessionID: nil)
        // Reading "a" makes "b" the one nobody looked at.
        XCTAssertNotNil(cache.retrieve("a"))
        cache.store(key: "c", older: [], rows: [row("c")], cursor: nil, sessionID: nil)
        XCTAssertNotNil(cache.retrieve("a"), "a was used last, so it stays")
        XCTAssertNil(cache.retrieve("b"), "b was the least recently used, so it goes")
        XCTAssertNotNil(cache.retrieve("c"))
    }

    func testAPagePastItsAgeIsNotShown() {
        let clock = Clock()
        let cache = self.cache(maxAge: 300, clock: clock)
        cache.store(key: "a", older: [], rows: [row("fresh")], cursor: nil, sessionID: "s-1")
        XCTAssertNotNil(cache.retrieve("a"))
        clock.seconds = 301
        XCTAssertNil(cache.retrieve("a"), "a page nobody refreshed for five minutes must not flash on screen")
        // The read that follows can still put the chat back.
        clock.seconds = 302
        cache.store(key: "a", older: [], rows: [row("newer")], cursor: nil, sessionID: "s-2")
        XCTAssertEqual(cache.retrieve("a")?.rows.map(\.text), ["newer"])
    }

    func testTheSameKeyKeepsOnlyTheNewestPage() {
        let cache = ChatPageCache()
        cache.store(key: "a", older: [], rows: [row("first")], cursor: nil, sessionID: "s-1")
        cache.store(key: "a", older: [row("older")], rows: [row("second")], cursor: nil, sessionID: "s-2")
        let entry = cache.retrieve("a")
        XCTAssertEqual(entry?.rows.map(\.text), ["second"])
        XCTAssertEqual(entry?.older.map(\.text), ["older"])
        XCTAssertEqual(entry?.sessionID, "s-2")
    }

    func testTheKeyNamesTheHostTheKindAndTheId() {
        let bot = ChatTarget(kind: .bot, id: "b1", name: "Bot")
        let room = ChatTarget(kind: .room, id: "r1", name: "Room")
        XCTAssertEqual(ChatPageCache.key(host: "h", target: bot), "h:bot:b1")
        XCTAssertEqual(ChatPageCache.key(host: "h", target: room), "h:room:r1")
        XCTAssertNil(ChatPageCache.key(host: nil, target: bot))
        XCTAssertNil(ChatPageCache.key(host: "", target: room))
    }
}

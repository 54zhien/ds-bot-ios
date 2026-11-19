import XCTest
@testable import DSBot

final class LastChatStoreTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LastChatStore.key)
        super.tearDown()
    }

    func testSaveThenLoadReturnsTheTargetWithoutItsName() {
        LastChatStore.save(ChatTarget(kind: .bot, id: "b-1", name: "Aster"))
        let loaded = LastChatStore.load()
        XCTAssertEqual(loaded?.kind, .bot)
        XCTAssertEqual(loaded?.id, "b-1")
    }

    func testARoomTargetSurvivesTheRoundTrip() {
        LastChatStore.save(ChatTarget(kind: .room, id: "r-9", name: "Ops"))
        XCTAssertEqual(LastChatStore.load()?.kind, .room)
        XCTAssertEqual(LastChatStore.load()?.id, "r-9")
    }

    func testRestoreKeepsATargetTheTeamStillHas() {
        LastChatStore.save(ChatTarget(kind: .bot, id: "b-1", name: ""))
        let restored = LastChatStore.restore(stillKnown: { $0.id == "b-1" })
        XCTAssertEqual(restored?.id, "b-1")
        XCTAssertNotNil(LastChatStore.load())
    }

    func testARemovedTargetIsClearedAndFallsBack() {
        LastChatStore.save(ChatTarget(kind: .room, id: "r-gone", name: ""))
        XCTAssertNil(LastChatStore.restore(stillKnown: { _ in false }))
        XCTAssertNil(LastChatStore.load())
    }

    func testAnUnreadableValueCountsAsNoSavedChatAndIsLeftAlone() {
        UserDefaults.standard.set("{oops", forKey: LastChatStore.key)
        XCTAssertNil(LastChatStore.load())
        XCTAssertEqual(UserDefaults.standard.string(forKey: LastChatStore.key), "{oops")
    }
}

import XCTest
@testable import DSBot

/// items.tsx:286-291 draws a room row from the roster: avatar, the member's own
/// colour, the name, and the Admin mark on the member who leads the room.
final class RoomRowDataTests: XCTestCase {
    private let bots: [JSONValue] = [
        .object(["id": .string("b-1"), "name": .string("Aster"), "color": .string("violet"),
                 "avatar": .object(["shape": .string("whale")])]),
        .object(["id": .string("b-2"), "name": .string("Nova"), "color": .string("green")]),
    ]

    private func post(_ botID: String?, name: String? = nil) -> ChatRow {
        var item: [String: JSONValue] = ["kind": .string("post"), "text": .string("Done")]
        if let botID { item["botId"] = .string(botID) }
        if let name { item["name"] = .string(name) }
        return ChatRow(.object(item))
    }

    func testARoomRowPicksUpItsMembersNameColourAndAvatar() {
        var rows = [post("b-1")]
        RoomRowData.decorate(&rows, bots: bots, adminBotID: nil)
        XCTAssertEqual(rows[0].memberName, "Aster")
        XCTAssertEqual(rows[0].memberColor, "violet")
        XCTAssertEqual(rows[0].memberAvatar?["shape"]?.stringValue, "whale")
        XCTAssertFalse(rows[0].isAdmin)
    }

    func testOnlyTheRoomsAdminIsMarked() {
        var rows = [post("b-1"), post("b-2")]
        RoomRowData.decorate(&rows, bots: bots, adminBotID: "b-2")
        XCTAssertFalse(rows[0].isAdmin)
        XCTAssertTrue(rows[1].isAdmin)
    }

    func testARowWithNoMemberKeepsItsOwnFields() {
        let plain = ChatRow(.object(["kind": .string("bot"), "text": .string("Hi")]))
        var rows = [plain]
        RoomRowData.decorate(&rows, bots: bots, adminBotID: "b-1")
        XCTAssertNil(rows[0].memberName)
        XCTAssertNil(rows[0].memberColor)
        XCTAssertNil(rows[0].memberAvatar)
        XCTAssertFalse(rows[0].isAdmin)
    }

    func testAMemberMissingFromTheRosterLeavesTheRowAlone() {
        var rows = [post("b-gone", name: "Old")]
        RoomRowData.decorate(&rows, bots: bots, adminBotID: "b-1")
        XCTAssertNil(rows[0].memberName)
        XCTAssertEqual(rows[0].name, "Old", "the item's own name survives")
        XCTAssertFalse(rows[0].isAdmin)
    }

    func testAUserRowNeverGetsMemberFields() {
        var rows = [ChatRow(.object(["kind": .string("user"), "text": .string("Hi")]))]
        RoomRowData.decorate(&rows, bots: bots, adminBotID: "b-1")
        XCTAssertNil(rows[0].botID)
        XCTAssertNil(rows[0].memberColor)
    }
}

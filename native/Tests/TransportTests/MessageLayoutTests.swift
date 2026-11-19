import XCTest
@testable import DSBot

/// items.tsx:285-292 puts a room member's row above the bubble, not inside it,
/// and :271/:338 place the stamp at opposite edges for a user and a Bot.
final class MessageLayoutTests: XCTestCase {
    private func cell() -> ChatMessageCell {
        ChatMessageCell(style: .default, reuseIdentifier: nil)
    }

    private func roomPost(_ id: String = "b-1") -> ChatRow {
        ChatRow(.object(["kind": .string("post"), "text": .string("Done"),
                         "botId": .string(id), "name": .string("Aster"),
                         "time": .number(1_700_000_000_000)]))
    }

    @MainActor func testAMemberRowSitsAboveTheBubble() {
        let cell = cell()
        var members: [ChatRow] = [roomPost()]
        members[0].inRoom = true
        RoomRowData.decorate(&members, bots: [.object(["id": .string("b-1"),
                                                       "name": .string("Aster"),
                                                       "color": .string("violet")])],
                             adminBotID: nil)
        cell.configure(members[0])
        XCTAssertTrue(cell.memberHeaderVisible)
        XCTAssertTrue(cell.memberAvatarVisible)
        XCTAssertEqual(cell.memberNameText, "Aster")
    }

    @MainActor func testABotRowHasNoMemberRow() {
        let cell = cell()
        cell.configure(ChatRow(.object(["kind": .string("bot"), "text": .string("Hi")])))
        XCTAssertFalse(cell.memberHeaderVisible)
        XCTAssertFalse(cell.memberAvatarVisible)
    }

    @MainActor func testTheStampSitsAtTheEdgeItsOwnerUses() {
        let cell = cell()
        let user = ChatRow(.object(["kind": .string("user"), "text": .string("Hi"),
                                    "time": .number(1_700_000_000_000)]))
        let bot = ChatRow(.object(["kind": .string("bot"), "text": .string("Done"),
                                   "time": .number(1_700_000_000_000)]))
        cell.configure(user)
        XCTAssertTrue(cell.stampHugsTrailingEdge, "a user's stamp sits at the right, marginRight 2")
        cell.configure(bot)
        XCTAssertFalse(cell.stampHugsTrailingEdge, "a Bot's stamp starts at the left, four in")
    }
}

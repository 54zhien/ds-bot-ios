import XCTest
@testable import DSBot

/// The chat header's 28pt mark and the empty block's 64pt mark draw what
/// marks.tsx draws: a Bot's character, or a room's members. Neither draws the
/// letter the pill used to show.
final class HeaderMarkTests: XCTestCase {
    private let bots: [JSONValue] = [
        .object(["id": .string("b-1"), "name": .string("Aster"), "color": .string("violet"),
                 "avatar": .object(["shape": .string("whale")])]),
        .object(["id": .string("b-2"), "name": .string("Nova"), "color": .string("green")]),
    ]
    private var team: JSONValue { .object(["bots": .array(bots)]) }

    private func bot(_ id: String) -> JSONValue? {
        bots.first { $0["id"]?.stringValue == id }
    }

    func testABotTargetHandsTheMarkItsCharacter() {
        let mark = ChatViewController.HeaderMark.choose(bot: bot("b-1"), room: nil, team: team)
        XCTAssertEqual(mark.look?.shape, "whale")
        XCTAssertTrue(mark.members.isEmpty)
    }

    func testARoomTargetHandsTheMarkItsRoster() {
        let room: JSONValue = .object(["id": .string("r-1"),
                                       "members": .array([.string("b-2"), .string("b-1")])])
        let mark = ChatViewController.HeaderMark.choose(bot: nil, room: room, team: team)
        XCTAssertNil(mark.look, "a room draws members, not one character")
        XCTAssertEqual(mark.members.count, 2)
        // marks.tsx:116 keeps the room's own order, so b-2 comes first.
        XCTAssertEqual(mark.members.first?.color, "green")
        XCTAssertEqual(mark.members.last?.shape, "whale")
    }

    func testARoomWithNoKnownMembersStillAnswers() {
        let room: JSONValue = .object(["id": .string("r-1"),
                                       "members": .array([.string("b-gone")])])
        let mark = ChatViewController.HeaderMark.choose(bot: nil, room: room, team: team)
        XCTAssertNil(mark.look)
        XCTAssertTrue(mark.members.isEmpty, "an empty roster hides the mark rather than drawing nothing")
    }

    func testNoTargetDrawsNothing() {
        let mark = ChatViewController.HeaderMark.choose(bot: nil, room: nil, team: team)
        XCTAssertNil(mark.look)
        XCTAssertTrue(mark.members.isEmpty)
    }

    @MainActor func testTheEmptyBlockDropsItsLetterOnceItHasALook() {
        let view = EmptyChatView()
        view.configure(name: "Aster", role: "Coder", color: "violet", caption: "No messages yet",
                       look: CharacterMarks.Look(bot: bot("b-1")))
        XCTAssertFalse(view.isShowingLetter)

        let roomView = EmptyChatView()
        let room: JSONValue = .object(["id": .string("r-1"), "members": .array([.string("b-1")])])
        roomView.configure(name: "Ops", role: "", color: nil, caption: "No messages yet",
                           members: CharacterMarks.Look.members(of: room, team: team))
        XCTAssertFalse(roomView.isShowingLetter)

        let bare = EmptyChatView()
        bare.configure(name: "Aster", role: "Coder", color: "violet", caption: "No messages yet")
        XCTAssertTrue(bare.isShowingLetter, "a caller with no look keeps the letter fallback")
    }
}

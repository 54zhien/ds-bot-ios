import XCTest
@testable import DSBot

/// items.tsx:268-300: in a room every reply carries its member outside the bubble —
/// a 22pt avatar in its own column, the name in that member's colour, the Admin mark
/// and the clock. A one-to-one chat draws none of it, and the flat layout keeps its
/// bare row whatever the roster says.
@MainActor
final class RoomRowLayoutTests: XCTestCase {
    private func roomRow(avatar: JSONValue? = .object(["shape": .string("whale")]),
                         color: String? = "violet") -> ChatRow {
        var row = ChatRow(.object([
            "kind": .string("post"), "text": .string("Done"), "botId": .string("b-1"),
        ]))
        row.inRoom = true
        row.memberName = "Aster"
        row.memberColor = color
        row.memberAvatar = avatar
        return row
    }

    private func cell() -> ChatMessageCell {
        ChatMessageCell(style: .default, reuseIdentifier: nil)
    }

    func testARoomRowCarriesItsMemberOutsideTheBubble() {
        let cell = cell()
        cell.configure(roomRow())
        XCTAssertTrue(cell.memberHeaderVisible, "the member's name row")
        XCTAssertTrue(cell.memberAvatarVisible, "the 22pt column")
        XCTAssertEqual(cell.memberNameText, "Aster")
        XCTAssertEqual(cell.bubbleLeadingInset, 12 + 22 + 8, "the bubble clears the column and its gap")
    }

    func testAOneToOneRowLeavesTheColumnOut() {
        var row = roomRow()
        row.inRoom = false
        let cell = cell()
        cell.configure(row)
        XCTAssertFalse(cell.memberHeaderVisible)
        XCTAssertFalse(cell.memberAvatarVisible)
        XCTAssertEqual(cell.bubbleLeadingInset, 12)
    }

    func testANullAvatarReservesNothing() {
        let cell = cell()
        cell.configure(roomRow(avatar: .null))
        XCTAssertFalse(cell.memberAvatarVisible, "a null avatar draws no disc and no blank column")
        XCTAssertFalse(cell.memberHeaderVisible)
        XCTAssertEqual(cell.bubbleLeadingInset, 12)
    }

    func testFlatKeepsItsBareRow() {
        let cell = cell()
        cell.configure(roomRow(), flat: true)
        XCTAssertFalse(cell.memberHeaderVisible)
        XCTAssertFalse(cell.memberAvatarVisible)
        XCTAssertEqual(cell.bubbleLeadingInset, 12)
        XCTAssertEqual(cell.bubbleFillColor, ThemeStore.palette(trait: cell.traitCollection).main)
        XCTAssertEqual(cell.bubbleCornerRadius, 0)
    }

    func testTheNameWearsTheMembersColour() {
        let cell = cell()
        cell.configure(roomRow(color: "violet"))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        cell.memberNameColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // tokens.ts inkColor: violet's ink is #8B5CF6 in light (the swatch's #7d5aff
        // belongs to COLOR_PAINT, which a picker draws, not a name).
        XCTAssertEqual(red, 0x8B / 255, accuracy: 0.01)
        XCTAssertEqual(green, 0x5C / 255, accuracy: 0.01)
        XCTAssertEqual(blue, 0xF6 / 255, accuracy: 0.01)
    }

    /// inkColor sends an unknown name to the ink table's gray; ink2 is only for a row
    /// with no member colour at all.
    func testAnUnknownColourFallsToTheInkGray() {
        let cell = cell()
        cell.configure(roomRow(color: "chartreuse"))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        cell.memberNameColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0x8A / 255, accuracy: 0.01)
        XCTAssertEqual(green, 0x8F / 255, accuracy: 0.01)
        XCTAssertEqual(blue, 0x98 / 255, accuracy: 0.01)
    }

    func testAMemberWithoutAColourFallsToInk2() {
        let cell = cell()
        cell.configure(roomRow(color: nil))
        let palette = ThemeStore.palette(trait: cell.traitCollection)
        XCTAssertEqual(cell.memberNameColor, palette.ink2)
    }

    func testTheAdminMarkFollowsTheRoomAdmin() {
        let cell = cell()
        var row = roomRow()
        row.isAdmin = true
        cell.configure(row)
        XCTAssertTrue(cell.adminTagVisible)
        row.isAdmin = false
        cell.configure(row)
        XCTAssertFalse(cell.adminTagVisible)
    }

    /// A narrow row takes its shortfall out of the name, never out of the tag: a tag
    /// narrower than its text draws the middle of "管理员" and reads as two characters.
    func testANarrowRowSqueezesTheNameNotTheAdminTag() {
        let cell = cell()
        cell.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
        var row = roomRow()
        row.isAdmin = true
        row.memberName = String(repeating: "很长很长的名字", count: 6)
        cell.configure(row)
        cell.layoutIfNeeded()
        XCTAssertTrue(cell.adminTagVisible)
        XCTAssertTrue(cell.adminTagFitsItsText, "the tag keeps the width its text needs")
    }

    func testAReusedCellDropsTheColumn() {
        let cell = cell()
        cell.configure(roomRow())
        XCTAssertTrue(cell.memberAvatarVisible)
        var oneToOne = roomRow()
        oneToOne.inRoom = false
        cell.configure(oneToOne)
        XCTAssertFalse(cell.memberAvatarVisible, "a recycled cell must not keep the last member's column")
        XCTAssertEqual(cell.bubbleLeadingInset, 12)
    }
}

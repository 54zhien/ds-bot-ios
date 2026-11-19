import XCTest
@testable import DSBot

/// The marks the app was still drawing without: a group's member rows, the side
/// chat's head, and the Bot editor's preview. Every size here is a number marks.tsx
/// passes at its own call site, so these hold the views to that number rather than
/// to how they happen to look.
@MainActor
final class MemberMarkTests: XCTestCase {
    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        var found: [T] = []
        for child in view.subviews {
            if let match = child as? T { found.append(match) }
            found += find(type, in: child)
        }
        return found
    }

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.compactMap { $0 as? UILabel }
    }

    /// manage.tsx:566-576: the mark leads, the name follows ten points later.
    func testAGroupMemberRowLeadsWithTheMark() {
        let cell = GroupMemberCell(style: .default, reuseIdentifier: "member")
        cell.frame = CGRect(x: 0, y: 0, width: 340, height: 56)
        cell.configure(name: "Nova", detail: "Admin",
                       look: CharacterMarks.look(shape: "moon", color: "violet"),
                       palette: Palette.make(dark: false))
        cell.layoutIfNeeded()
        guard let mark = find(MarkView.self, in: cell.contentView).first else {
            return XCTFail("the member row has no mark")
        }
        XCTAssertEqual(mark.frame.width, 32)
        XCTAssertEqual(mark.frame.height, 32)
        XCTAssertEqual(mark.frame.minX, Glass.margin)
        let name = labels(in: cell.contentView).first { $0.text == "Nova" }
        XCTAssertNotNil(name, "the name is the row's own label")
        XCTAssertEqual(name?.frame.minX ?? 0, mark.frame.maxX + 10, accuracy: 0.5)
        XCTAssertNotNil(labels(in: cell.contentView).first { $0.text == "Admin" })
    }

    /// manage.tsx:628-647: the tick rides the name, and only a member may lead.
    func testAGroupMemberRowCarriesItsTickAndAdminControl() {
        let row = GroupMemberRow(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        row.mark.configure(look: CharacterMarks.look(shape: "kitty", color: "rose"))
        row.configure(name: "Iris", checked: false, admin: false)
        row.layoutIfNeeded()
        XCTAssertEqual(row.mark.frame.width, 32)
        XCTAssertEqual(row.mark.frame.height, 32)
        XCTAssertEqual(row.member.frame.minX, 42, "the name starts ten off the mark")
        XCTAssertEqual(row.member.title(for: .normal), "○  Iris")
        XCTAssertTrue(row.lead.isHidden, "a Bot outside the room has no admin control")

        row.configure(name: "Iris", checked: true, admin: true)
        XCTAssertEqual(row.member.title(for: .normal), "✓  Iris")
        XCTAssertFalse(row.lead.isHidden)
        XCTAssertEqual(row.lead.title(for: .normal), NativeLanguage.text("Admin"))

        row.configure(name: "Iris", checked: true, admin: false)
        XCTAssertEqual(row.lead.title(for: .normal), NativeLanguage.text("Make admin"))
    }

    /// side.tsx:68: the head carries a 28pt mark beside the Bot's name.
    func testTheSideChatHeadIsAMarkAtTwentyEight() {
        let row = SideChatViewController.titleRow(
            botName: "Nova", look: CharacterMarks.look(id: "abc"), palette: Palette.make(dark: false))
        row.frame = CGRect(x: 0, y: 0, width: 240, height: 44)
        row.layoutIfNeeded()
        guard let mark = find(CharacterAvatarView.self, in: row).first else {
            return XCTFail("the head has no mark")
        }
        XCTAssertEqual(mark.frame.width, 28)
        XCTAssertEqual(mark.frame.height, 28)
        XCTAssertEqual(row.accessibilityLabel, "Nova, " + NativeLanguage.text("Side chat"))
        // The head keeps its labels inside a column stack, so the shallow
        // direct-children helper cannot see them; the recursive one can.
        XCTAssertNotNil(find(UILabel.self, in: row).first { $0.text == "Nova" })
        XCTAssertNotNil(find(UILabel.self, in: row).first { $0.text == NativeLanguage.text("Side chat") })
    }

    /// manage.tsx:504,:223: the editor shows the Bot as it will look, and a photo
    /// wins over the character — one look, so the preview and the list agree.
    func testTheEditorPreviewPrefersAPhotoOverTheCharacter() {
        let character = BotEditorViewController.previewLook(
            shape: "moon", color: "violet", id: "abc", avatar: ["shape": .string("moon")])
        XCTAssertEqual(character.shape, "moon")
        XCTAssertEqual(character.color, "violet")
        XCTAssertNil(character.image)

        let photo = BotEditorViewController.previewLook(
            shape: "moon", color: "violet", id: "abc",
            avatar: ["shape": .string("moon"), "image": .string("data:image/png;base64,AA")])
        XCTAssertEqual(photo.image, "data:image/png;base64,AA")
        XCTAssertEqual(photo.shape, "moon", "the character is still the fallback under it")

        // A new Bot has no id to derive from: the picks stand on their own.
        let fresh = BotEditorViewController.previewLook(
            shape: "star", color: "blue", id: nil, avatar: [:])
        XCTAssertEqual(fresh.shape, "star")
        XCTAssertEqual(fresh.color, "blue")
    }
}

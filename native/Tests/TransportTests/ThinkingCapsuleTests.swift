import XCTest
@testable import DSBot

/// The capsule is the phone's answer to RN's ActionRow (dock.tsx:306-320): the same
/// line and the same mark, in a pill that may not grow past 32pt. These hold the words
/// to phrases.ts, the state walk to Chat.tsx, and the view to showing only while a Bot
/// is working.
@MainActor
final class ThinkingCapsuleTests: XCTestCase {
    private let look = CharacterMarks.look(shape: "moon", color: "violet")

    /// Puts the capsule in a laid-out container with nothing but its leading edge
    /// pinned, so its width is whatever its own content asks for.
    @discardableResult
    private func hosted(_ view: UIView, width: CGFloat = 400) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 120))
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            view.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        container.layoutIfNeeded()
        return container
    }

    // MARK: - Words

    /// The vectors are mobile/src/team/ui-contract.test.ts:45-53, plus the branches
    /// that test does not reach: what the Bot said, a switch, and the fallbacks.
    func testTheWordsFollowPhrasesTS() {
        let before = NativeLanguage.mode
        defer { NativeLanguage.set(before) }

        NativeLanguage.set("en")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("run_shell_command"),
                                                "target": .string("npm test")])),
                       "Running shell commands · npm test")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("web_search")])), "Searching online")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("read_file")])), "Opening a file")
        XCTAssertEqual(WorkPhrase.text(.object(["said": .string("Reading cells.js.…")])), "Reading cells.js")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("catalogue")])), "On it",
                       "the read family needs a word boundary, so the RN pattern misses")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("nonesuch")])), "On it")
        XCTAssertEqual(WorkPhrase.text(.object([:])), "Thinking about it")
        XCTAssertEqual(WorkPhrase.text(.object(["switching": .bool(true), "folder": .bool(true)])),
                       "Switching working folder")
        XCTAssertEqual(WorkPhrase.text(.object(["switching": .bool(true)])), "Moving to a fresh conversation")

        NativeLanguage.set("zh")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("run_shell_command"),
                                                "target": .string("npm test")])),
                       "运行命令 · npm test")
        XCTAssertEqual(WorkPhrase.text(.object([:])), "想一想")
        XCTAssertEqual(WorkPhrase.text(.object(["tool": .string("nonesuch")])), "在做了")
    }

    /// Chat.tsx:256: a session reads its own work entry, a room reads the first in its
    /// list and names the Bot that is doing it.
    func testThePresentationReadsTheStateTheWayTheScreenDoes() {
        let before = NativeLanguage.mode
        defer { NativeLanguage.set(before) }
        NativeLanguage.set("en")

        let state = JSONValue.object([
            "bots": .array([.object([
                "id": .string("bot-1"),
                "name": .string("Ada"),
                "avatar": .object(["shape": .string("moon"), "color": .string("violet")]),
            ])]),
            "work": .object([
                "bots": .object(["bot-1": .object([
                    "tool": .string("run_shell_command"), "target": .string("npm test"),
                ])]),
                "rooms": .object(["room-1": .array([
                    .object(["botId": .string("bot-1"), "tool": .string("web_search")]),
                ])]),
            ]),
        ])

        let bot = ThinkingCapsulePresentation(
            target: ChatTarget(kind: .bot, id: "bot-1", name: "Ada"), state: state)
        XCTAssertEqual(bot?.text, "Running shell commands · npm test…")
        XCTAssertEqual(bot?.look?.shape, "moon")
        XCTAssertEqual(bot?.look?.color, "violet")

        let room = ThinkingCapsulePresentation(
            target: ChatTarget(kind: .room, id: "room-1", name: "Team"), state: state)
        XCTAssertEqual(room?.text, "Ada · Searching online…")
        XCTAssertEqual(room?.look?.shape, "moon")

        let idle = ThinkingCapsulePresentation(
            target: ChatTarget(kind: .bot, id: "bot-2", name: "Idle"), state: state)
        XCTAssertNil(idle, "no work entry means the Bot is idle")
    }

    /// LanguageTests reads literals out of the sources; these keys travel in a table,
    /// so the only place they can be checked is here.
    func testEveryWordThisTableCanShowHasAChineseEntry() {
        for key in WorkPhrase.keys {
            XCTAssertTrue(NativeLanguage.hasEntry(key), "no Chinese entry for \(key)")
        }
    }

    // MARK: - The pill

    func testAnIdleBotShowsNothing() {
        let view = ThinkingCapsuleView()
        view.configure(ThinkingCapsulePresentation(text: "想一想…", look: look))
        XCTAssertFalse(view.isHidden)
        view.configure(nil)
        XCTAssertTrue(view.isHidden, "a nil presentation clears the capsule")
        view.configure(ThinkingCapsulePresentation(text: "", look: look))
        XCTAssertTrue(view.isHidden, "an empty line is nothing to show")
    }

    func testAWorkingBotShowsItsLineAndItsMark() {
        let view = ThinkingCapsuleView()
        view.configure(ThinkingCapsulePresentation(text: "想一想…", look: look))
        XCTAssertFalse(view.isHidden)
        XCTAssertTrue(view.showsMark)
        XCTAssertEqual(view.accessibilityLabel, "想一想…")
        view.configure(ThinkingCapsulePresentation(text: "Thinking about it…", look: nil))
        XCTAssertFalse(view.showsMark, "a Bot with no look shows the line alone")
        XCTAssertEqual(view.accessibilityLabel, "Thinking about it…")
    }

    func testTheCapsuleNeverGrowsTallerThanThirtyTwo() {
        XCTAssertEqual(ThinkingCapsuleView.height, 32)
        let view = ThinkingCapsuleView()
        view.configure(ThinkingCapsulePresentation(text: "Running shell commands · npm test…", look: look))
        hosted(view)
        XCTAssertEqual(view.bounds.height, 32, accuracy: 0.5)
        XCTAssertLessThanOrEqual(view.bounds.height, 32)
    }

    func testALongLineIsCutInsteadOfPushingTheCapsuleWider() {
        let view = ThinkingCapsuleView()
        view.maximumWidth = 160
        view.configure(ThinkingCapsulePresentation(
            text: String(repeating: "检查记忆中的项目结构 ", count: 12), look: look))
        hosted(view)
        XCTAssertLessThanOrEqual(view.bounds.width, 160.5)
        XCTAssertFalse(view.textFits, "the line is cut, not drawn past the edge")

        let short = ThinkingCapsuleView()
        short.maximumWidth = 160
        short.configure(ThinkingCapsulePresentation(text: "在做了…", look: nil))
        hosted(short)
        XCTAssertLessThan(short.bounds.width, 160, "the cap is a ceiling, not a width")
        XCTAssertTrue(short.textFits)
    }
}

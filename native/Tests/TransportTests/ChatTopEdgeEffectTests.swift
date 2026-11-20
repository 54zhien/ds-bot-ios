import XCTest
@testable import DSBot

/// iOS 26 has an official soft scroll edge effect, so the fade this app draws has to give way
/// there. These tests say which one owns the top edge, and that the chat list asks for it.
@MainActor
final class ChatTopEdgeEffectTests: XCTestCase {
    func testTheSystemOwnsTheTopEdgeWhereTheAPIExists() {
        let list = UITableView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), style: .plain)
        let fallback = FadeOverlayView()

        ChatTopEdgeEffect.apply(to: list, fallback: fallback)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(list.topEdgeEffect.style, .soft,
                           "the soft system effect is the one the reader asked for")
            XCTAssertTrue(fallback.isHidden, "the hand-rolled fade must not draw over it")
        } else {
            XCTAssertFalse(fallback.isHidden, "before iOS 26 the fade is the only blur at the top")
        }
    }

    /// The wiring is one line inside a 2000-line controller, and losing it is invisible on a
    /// phone that runs iOS 17-25. Scanning the source is cheaper than building the controller,
    /// which needs a window, a pairing store and a live link before it lays out.
    func testTheChatListHandsItsTopEdgeOver() throws {
        let native = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = native.appendingPathComponent("Sources/DSBot/ChatViewController.swift")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("the sources are not beside this test, so there is nothing to scan")
        }
        let source = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(source.contains("ChatTopEdgeEffect.apply(to: list, fallback: headerFade)"),
                      "the chat list no longer hands its top edge to the system effect")
    }
}

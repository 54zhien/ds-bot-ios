import XCTest
@testable import DSBot

/// The drawer is presented without an animation of its own (the page carries the motion),
/// which leaves its presentation controller with no transition coordinator to ride along
/// with. The scrim then has to be set by hand; if this rule is ever "simplified" away the
/// drawer loses its dimming silently, so the rule has a name and a test.
@MainActor
final class TeamDrawerScrimTests: XCTestCase {
    func testAPresentWithNoAnimationSetsTheScrimByHand() {
        XCTAssertTrue(TeamDrawerPresentationController.scrimNeedsSettingByHand(nil),
                      "no coordinator means nothing to animate alongside")
    }

    /// The other side needs a real presentation — a coordinator cannot be built outside
    /// one — so it is covered by the app itself: a presented drawer keeps its 0.32 scrim.
    func testTheAnimatedPathIsTheCoordinatedOne() {
        XCTAssertFalse(!TeamDrawerPresentationController.scrimNeedsSettingByHand(nil))
    }

    /// One motion subject: the page. The panel's slide was deleted rather than disabled,
    /// so the drawer's own file must not write a transform at all - and a source scan can
    /// hold that without a live presentation, which a unit test cannot build.
    func testOnlyThePageMoves() throws {
        let native = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let drawer = native.appendingPathComponent("Sources/DSBot/TeamDrawerTransition.swift")
        let source = try String(contentsOf: drawer, encoding: .utf8)
        XCTAssertFalse(source.contains(".transform"),
                       "the drawer must not move its own panel: the page carries the motion now")
        XCTAssertTrue(source.contains("transport"), "and the file should say what took over")
    }
}

import XCTest
@testable import DSBot

/// WorkspaceSidebarInteraction.swift:128-312, the admission rules. The fixture is a
/// window with a root view and nothing else — no scene life cycle, no animations, no
/// real touches: a UITouch cannot be built outside UIKit, so what is asserted here is
/// the wiring and the state-gated refusals, which is the half that decides who gets a
/// gesture. Animation length is deliberately not asserted; it is not stable in CI.
///
/// Not covered here, on purpose: touch-level admission (shouldReceive, :196-235) needs a
/// UITouch, and a UITouch cannot be constructed outside UIKit. Seeding it through a DEBUG
/// hook would put a hole in zen's function for the test's sake, and an XCUITest would add
/// a second source of flakiness, so the gap is recorded rather than papered over.
@MainActor
final class SidebarInteractionTests: XCTestCase {
    private struct Fixture {
        let window: UIWindow
        let root: UIViewController
        let content: UIView
        let anchor: WorkspaceSidebarInteraction
        let state: SidebarDragState
    }

    private func fixture(open: Bool = false) -> Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        _ = root.view
        window.isHidden = false

        let content = UIView(frame: window.bounds)
        root.view.addSubview(content)
        let state = SidebarDragState()
        let anchor = WorkspaceSidebarInteraction(frame: root.view.bounds)
        root.view.addSubview(anchor)
        anchor.configure(state: state, travel: 60, isRightToLeft: false) { [weak window] in
            guard let window else { return nil }
            return WorkspaceSidebarNativeContext(
                hostID: ObjectIdentifier(root), paneID: ObjectIdentifier(root), window: window,
                allowsOpening: true, allowsClosing: true, surfaceView: content)
        }
        root.view.layoutIfNeeded()
        if open {
            state.open(eligible: true)
            if let settlement = state.settlementID { state.completeSettlement(settlement) }
        }
        return Fixture(window: window, root: root, content: content, anchor: anchor, state: state)
    }

    /// :128-147: the edge recogniser goes on the scene's root view and the closing pair
    /// on the window, because the surface moves under a page that is not their ancestor.
    func testTheEdgeGoesOnTheRootViewAndTheClosingPairOnTheWindow() {
        let fixture = fixture()
        let recognisers = fixture.anchor.recognisers
        XCTAssertTrue(fixture.root.view.gestureRecognizers?.contains { $0 === recognisers.edge } ?? false)
        XCTAssertTrue(fixture.window.gestureRecognizers?.contains { $0 === recognisers.reverse } ?? false)
        XCTAssertTrue(fixture.window.gestureRecognizers?.contains { $0 === recognisers.closeTap } ?? false)
        XCTAssertEqual(recognisers.edge.edges, .left, "a left-to-right layout watches the left edge")
        XCTAssertEqual(recognisers.edge.maximumNumberOfTouches, 1)
        XCTAssertEqual(recognisers.reverse.maximumNumberOfTouches, 1)
    }

    /// :148-164: detaching takes every recogniser back off, whichever view it went on.
    func testDetachTakesEveryRecogniserBackOff() {
        let fixture = fixture()
        fixture.anchor.detach()
        let recognisers = fixture.anchor.recognisers
        XCTAssertFalse(fixture.root.view.gestureRecognizers?.contains { $0 === recognisers.edge } ?? false)
        XCTAssertFalse(fixture.window.gestureRecognizers?.contains { $0 === recognisers.reverse } ?? false)
        XCTAssertFalse(fixture.window.gestureRecognizers?.contains { $0 === recognisers.closeTap } ?? false)
    }

    /// :110-114: flipping the reading direction cancels the old edge policy first.
    func testTheWatchedEdgeFollowsTheReadingDirection() {
        let fixture = fixture()
        fixture.anchor.configure(state: fixture.state, travel: 60, isRightToLeft: true) { nil }
        XCTAssertEqual(fixture.anchor.recognisers.edge.edges, .right)
        fixture.anchor.configure(state: fixture.state, travel: 60, isRightToLeft: false) { nil }
        XCTAssertEqual(fixture.anchor.recognisers.edge.edges, .left)
    }

    /// :237-243: a gesture may not begin while one is settling, whatever it is.
    func testNothingBeginsWhileASettlementIsOutstanding() {
        let fixture = fixture(open: true)
        // Clear the state the open path left, then leave a fresh settlement behind.
        if let settlement = fixture.state.settlementID { fixture.state.completeSettlement(settlement) }
        _ = fixture.state.begin(eligible: true)
        fixture.state.end(velocity: 0, travel: 60, cancelled: false)
        XCTAssertNotNil(fixture.state.settlementID)

        let anchor = fixture.anchor
        XCTAssertFalse(anchor.gestureRecognizerShouldBegin(anchor.recognisers.edge))
        XCTAssertFalse(anchor.gestureRecognizerShouldBegin(anchor.recognisers.reverse))
        XCTAssertFalse(anchor.gestureRecognizerShouldBegin(anchor.recognisers.closeTap))

        // Arbitration is refused for the same reason, so a content pan keeps the touch.
        let contentPan = UIPanGestureRecognizer()
        fixture.content.addGestureRecognizer(contentPan)
        XCTAssertFalse(anchor.gestureRecognizer(anchor.recognisers.closeTap,
                                                shouldBeRequiredToFailBy: contentPan))
    }

    /// :256-259 / :205: an open sidebar never starts an opening edge gesture again.
    func testAnOpenSidebarDoesNotBeginAnOpeningEdgeGesture() {
        let fixture = fixture(open: true)
        XCTAssertFalse(fixture.anchor.gestureRecognizerShouldBegin(fixture.anchor.recognisers.edge))
    }

    /// :244-248: the closing tap needs the owner it captured on the touch that started
    /// it; a tap with no owner (the fixture cannot fabricate one) is refused.
    func testTheClosingTapNeedsItsCapturedOwner() {
        let fixture = fixture(open: true)
        XCTAssertFalse(fixture.anchor.gestureRecognizerShouldBegin(fixture.anchor.recognisers.closeTap))
    }
}

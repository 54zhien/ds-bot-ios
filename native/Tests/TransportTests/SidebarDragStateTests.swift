import XCTest
@testable import DSBot

/// WorkspaceNavigationState.swift:41-83: the four steps and the flags the gesture
/// code reads. The numbers here are zen's own (half a travel to open, 0.12 of a
/// travel for a flick), not tuned by eye.
@MainActor
final class SidebarDragStateTests: XCTestCase {
    func testAGestureCannotStartWhileOneIsSettling() {
        let state = SidebarDragState()
        XCTAssertTrue(state.begin(eligible: true))
        state.end(velocity: 0, travel: 100, cancelled: false)
        XCTAssertNotNil(state.settlementID)
        XCTAssertFalse(state.begin(eligible: true), "a settling sidebar refuses a new gesture")
        state.completeSettlement(state.settlementID!)
        XCTAssertTrue(state.begin(eligible: true))
    }

    func testProgressIsTheOpenFlagPlusTheDrag() {
        let state = SidebarDragState()
        state.begin(eligible: true)
        state.drag(displacement: 40, travel: 100)
        XCTAssertEqual(state.progress, 0.4, accuracy: 0.0001)

        let open = SidebarDragState()
        open.open(eligible: true)
        open.completeSettlement(open.settlementID!)
        open.begin(eligible: true)
        open.drag(displacement: -40, travel: 100)
        XCTAssertEqual(open.progress, 0.6, accuracy: 0.0001, "a pull from the open side reads 1 - 0.4")
    }

    func testDragIsClamped() {
        let state = SidebarDragState()
        state.begin(eligible: true)
        state.drag(displacement: -500, travel: 100)
        XCTAssertEqual(state.progress, 0)
        state.drag(displacement: 500, travel: 100)
        XCTAssertEqual(state.progress, 1)
    }

    func testHalfATravelOpensAndAFlickCountsA0_12Share() {
        let slow = SidebarDragState()
        slow.begin(eligible: true)
        slow.drag(displacement: 49, travel: 100)
        slow.end(velocity: 0, travel: 100, cancelled: false)
        XCTAssertFalse(slow.isOpen, "under half a travel and no flick stays closed")

        let flick = SidebarDragState()
        flick.begin(eligible: true)
        flick.drag(displacement: 45, travel: 100)
        flick.end(velocity: 50, travel: 100, cancelled: false)
        XCTAssertTrue(flick.isOpen, "0.45 + 50/100 * 0.12 = 0.51 crosses the half")
        XCTAssertEqual(flick.progress, 1)
    }

    func testACancelledGestureKeepsTheSideItCameFrom() {
        let state = SidebarDragState()
        state.open(eligible: true)
        state.completeSettlement(state.settlementID!)
        state.begin(eligible: true)
        state.drag(displacement: -70, travel: 100)
        state.end(velocity: 200, travel: 100, cancelled: true)
        XCTAssertTrue(state.isOpen, "cancelling ignores the flick and the progress")
        XCTAssertEqual(state.progress, 1)
        XCTAssertNil(state.gestureID)
    }

    func testNoTravelEndsTheGestureAsCancelled() {
        let state = SidebarDragState()
        state.begin(eligible: true)
        state.drag(displacement: 20, travel: 0)
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isOpen)
        XCTAssertNotNil(state.settlementID)
    }

    func testBlocksLiftWhileAnimatingOrDragging() {
        let state = SidebarDragState()
        XCTAssertFalse(state.blocksLift)
        state.begin(eligible: true)
        XCTAssertTrue(state.blocksLift)
        state.drag(displacement: 10, travel: 100)
        state.end(velocity: 0, travel: 100, cancelled: false)
        XCTAssertTrue(state.blocksLift, "the settlement still holds the content")
        state.completeSettlement(state.settlementID!)
        XCTAssertFalse(state.blocksLift)
    }

    func testClosingLeavesASettlementOnlyWhenSomethingWasShowing() {
        let fresh = SidebarDragState()
        fresh.close()
        XCTAssertNil(fresh.settlementID, "nothing was showing, so there is nothing to animate out")

        let open = SidebarDragState()
        open.open(eligible: true)
        open.close()
        XCTAssertNotNil(open.settlementID)
        XCTAssertFalse(open.isOpen)
        XCTAssertEqual(open.progress, 0)
    }

    func testSuspendingEndsInputButKeepsThePage() {
        let state = SidebarDragState()
        state.open(eligible: true)
        state.completeSettlement(state.settlementID!)
        state.begin(eligible: true)
        state.drag(displacement: -30, travel: 100)
        state.suspendInteractions()
        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.settlementID)
        XCTAssertTrue(state.isOpen, "the sidebar stays where the user left it")
        XCTAssertEqual(state.progress, 1)
    }
}

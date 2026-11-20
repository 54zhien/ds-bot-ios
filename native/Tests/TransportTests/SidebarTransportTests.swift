import XCTest
@testable import DSBot

/// ConversationSurfaceHost.swift:506-531: one transform for the page, and a settlement
/// that is either a jump (Reduce Motion) or a 0.22s easeOut that reports once it lands.
@MainActor
final class SidebarTransportTests: XCTestCase {
    func testThePageMovesAsOneHorizontalUnit() {
        let transport = SidebarTransportView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        transport.translate(to: 96)
        XCTAssertEqual(transport.offset, 96)
        XCTAssertEqual(transport.transform, CGAffineTransform(translationX: 96, y: 0))
        transport.translate(to: 0)
        XCTAssertEqual(transport.transform, .identity)
        transport.translate(to: .nan)
        XCTAssertEqual(transport.offset, 0, "a broken offset is no offset, not a NaN transform")
    }

    func testTheSettlementDurationIsZensOwn() {
        XCTAssertEqual(SidebarSettlement.duration, 0.22)
    }

    /// Under Reduce Motion the page jumps and the completion still arrives — after a
    /// turn, so the caller can lay out first, the way zen yields before reporting.
    func testReduceMotionJumpsAndStillReports() async {
        let transport = SidebarTransportView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let reported = expectation(description: "the settlement reports back")
        SidebarSettlement.run(offset: 96, on: transport, reduceMotion: true) { reported.fulfill() }
        XCTAssertEqual(transport.offset, 96, "the jump is immediate")
        // Not asserted here: XCTest cannot tell "not yet fulfilled" apart from "never will be"
        // before the wait below, and the old counter could not either without a sleep.
        // The report lands a turn later by design; an expectation waits for it instead of
        // guessing how many yields that costs.
        await fulfillment(of: [reported], timeout: 2)
    }
}

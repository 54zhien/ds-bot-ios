import XCTest
@testable import DSBot

/// The header fade is a blur cut by an alpha mask now, not a colour ramp: the mask has
/// to be fully opaque at the top or nothing gets blurred, and fully transparent at the
/// bottom or the band ends on a line.
///
/// The stops are checked through `stops(forHeight:)` rather than through a laid-out view: a
/// view outside a hierarchy has no size of its own to give, and asking it for one measures the
/// harness, not the mask.
@MainActor
final class FadeOverlayTests: XCTestCase {
    func testTheMaskFadesOutOverItsLastStretch() {
        let stops = FadeOverlayView.stops(forHeight: 100).map { $0.doubleValue }
        XCTAssertEqual(stops.count, 3, "callers read stop [1], so there are always three")
        XCTAssertEqual(stops[0], 0, accuracy: 0.001)
        XCTAssertEqual(stops[1], 0.76, accuracy: 0.001, "the last 24 of a 100pt fade")
        XCTAssertEqual(stops[2], 1, accuracy: 0.001)
    }

    /// However short the view is, the top 60% stays fully blurred: the ramp gives way,
    /// not the opaque part.
    func testAShortFadeKeepsItsTopSixtyPercentOpaque() {
        let stops = FadeOverlayView.stops(forHeight: 40).map { $0.doubleValue }
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[1], 0.6, accuracy: 0.001)
    }

    /// A view with no height yet still comes back with stops: an empty list turns the next
    /// reader into an index crash.
    func testAZeroHeightFadeStillCarriesThreeStops() {
        let stops = FadeOverlayView.stops(forHeight: 0).map { $0.doubleValue }
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[1], 1, accuracy: 0.001)
    }

    /// The view rebuilds its mask for whatever size it is given. The size comes from `bounds`
    /// here: this instance sits outside any hierarchy, so nothing pins the frame a layout pass
    /// would hand it.
    func testTheViewRebuildsItsMaskForTheSizeItHas() {
        let fade = FadeOverlayView()
        fade.bounds = CGRect(x: 0, y: 0, width: 390, height: 100)
        fade.configure(color: .white)
        fade.refreshMask()

        XCTAssertNotNil(fade.layer.mask, "the blur is cut by a mask, not by a colour ramp")
        let stops = fade.maskLocations.map { $0.doubleValue }
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[1], 0.76, accuracy: 0.001)
        XCTAssertEqual(fade.washAlpha, 0.18, accuracy: 0.001)
    }
}

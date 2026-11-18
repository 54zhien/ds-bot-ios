import XCTest
@testable import DSBot

/// The list must not move under its reader. The formula and the bottom judgment are
/// plain numbers here; the "same rows under the thumb" part is a device check.
final class ScrollAnchorTests: XCTestCase {
    func testRowsAboveKeepTheFocus() {
        XCTAssertEqual(ScrollAnchor.offset(keepingFocus: 300, oldHeight: 2_000, newHeight: 2_300), 600)
    }

    func testNoGrowthLeavesTheOffset() {
        XCTAssertEqual(ScrollAnchor.offset(keepingFocus: 300, oldHeight: 2_000, newHeight: 2_000), 300)
    }

    func testTheFirstPageMovesTheFocusByItsOwnHeight() {
        XCTAssertEqual(ScrollAnchor.offset(keepingFocus: 0, oldHeight: 0, newHeight: 500), 500)
    }

    func testTheBottomIsWhereFollowingIsRight() {
        XCTAssertTrue(ScrollAnchor.atBottom(contentSize: 1_000, offset: 300, viewport: 700))
        XCTAssertTrue(ScrollAnchor.atBottom(contentSize: 1_000, offset: 181, viewport: 700),
                       "119 from the bottom still follows")
        XCTAssertFalse(ScrollAnchor.atBottom(contentSize: 1_000, offset: 179, viewport: 700),
                       "121 from the bottom does not")
    }

    func testAReaderUpInTheHistoryIsNotDragged() {
        XCTAssertFalse(ScrollAnchor.atBottom(contentSize: 5_000, offset: 1_000, viewport: 700))
    }

    func testAnEmptyListIsAtTheBottom() {
        XCTAssertTrue(ScrollAnchor.atBottom(contentSize: 0, offset: 0, viewport: 700),
                      "a chat that just opened follows its first page down")
    }

    func testOverscrollStillCountsAsAtTheBottom() {
        XCTAssertTrue(ScrollAnchor.atBottom(contentSize: 1_000, offset: 310, viewport: 700))
    }
}

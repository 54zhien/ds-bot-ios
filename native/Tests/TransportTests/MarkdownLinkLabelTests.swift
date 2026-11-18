import XCTest
@testable import DSBot

final class MarkdownLinkLabelTests: XCTestCase {
    @MainActor func testOnlyWebAndMailLinksAreOpenable() {
        XCTAssertTrue(MarkdownLinkLabel.canOpen(URL(string: "https://example.com")!))
        XCTAssertTrue(MarkdownLinkLabel.canOpen(URL(string: "mailto:test@example.com")!))
        XCTAssertFalse(MarkdownLinkLabel.canOpen(URL(string: "file:///tmp/private")!))
        XCTAssertFalse(MarkdownLinkLabel.canOpen(URL(string: "intent://host")!))
    }
}

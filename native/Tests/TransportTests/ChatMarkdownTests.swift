import XCTest
@testable import DSBot

final class ChatMarkdownTests: XCTestCase {
    func testCodeFenceAndEscapedPipeTableRemainSeparateBlocks() {
        let source = "Before\n\n```swift\nlet x = 1 | 2\n```\n\n| A | B |\n| --- | --- |\n| 1 \\| 2 | three |"
        XCTAssertEqual(ChatMarkdownBlock.parse(source), [
            .text("Before"),
            .code("let x = 1 | 2"),
            .table([["A", "B"], ["1 | 2", "three"]]),
        ])
    }

    func testHeadingsListsQuotesAndRulesAreSeparateBlocks() {
        let source = "## Summary\n- first\n- second\n> quoted **text**\n> next line\n---\n3. third\n4. fourth"
        XCTAssertEqual(ChatMarkdownBlock.parse(source), [
            .heading(2, "Summary"),
            .list(["first", "second"], ordered: false, start: 1),
            .quote("quoted **text**\nnext line"),
            .rule,
            .list(["third", "fourth"], ordered: true, start: 3),
        ])
        XCTAssertTrue(ChatMarkdownView.hasWideBlock(source))
    }
}

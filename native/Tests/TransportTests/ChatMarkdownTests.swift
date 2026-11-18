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

    @MainActor func testHeadingsListsQuotesAndRulesAreSeparateBlocks() {
        let source = "## Summary\n- first\n- second\n> quoted **text**\n> next line\n---\n3. third\n4. fourth"
        XCTAssertEqual(ChatMarkdownBlock.parse(source), [
            .heading(2, "Summary"),
            .list([
                ChatMarkdownListItem(text: "first", marker: "•", depth: 0),
                ChatMarkdownListItem(text: "second", marker: "•", depth: 0),
            ]),
            .quote("quoted **text**\nnext line"),
            .rule,
            .list([
                ChatMarkdownListItem(text: "third", marker: "3.", depth: 0),
                ChatMarkdownListItem(text: "fourth", marker: "4.", depth: 0),
            ]),
        ])
        XCTAssertTrue(ChatMarkdownView.hasWideBlock(source))
    }

    func testNestedListKeepsLevelsAndContinuation() {
        let source = "- parent\n  1. child\n     continued\n    - grandchild\n  2. sibling\n- next"
        XCTAssertEqual(ChatMarkdownBlock.parse(source), [.list([
            ChatMarkdownListItem(text: "parent", marker: "•", depth: 0),
            ChatMarkdownListItem(text: "child\ncontinued", marker: "1.", depth: 1),
            ChatMarkdownListItem(text: "grandchild", marker: "•", depth: 2),
            ChatMarkdownListItem(text: "sibling", marker: "2.", depth: 1),
            ChatMarkdownListItem(text: "next", marker: "•", depth: 0),
        ])])
    }

    @MainActor func testListItemKeepsFencedCodeAndBlankLineAsBlock() {
        let source = "- explanation\n  ```swift\n  let x = 1\n\n  let y = 2\n  ```\n- next"
        let blocks = ChatMarkdownBlock.parse(source)
        guard case .list(let items) = blocks.first else { return XCTFail("Expected a list") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(ChatMarkdownBlock.parse(items[0].text), [
            .text("explanation"), .code("let x = 1\n\nlet y = 2"),
        ])
        let view = ChatMarkdownView()
        view.configure(source)
        XCTAssertEqual(view.arrangedSubviews.count, 1)
    }

    @MainActor func testQuoteCanContainAnotherBlock() {
        let source = "> explanation\n> ```\n> code\n> ```"
        XCTAssertEqual(ChatMarkdownBlock.parse(source), [.quote("explanation\n```\ncode\n```")])
        let view = ChatMarkdownView()
        view.configure(source)
        XCTAssertEqual(view.arrangedSubviews.count, 1)
    }
}

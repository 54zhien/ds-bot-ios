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
}

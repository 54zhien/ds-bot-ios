import XCTest
@testable import DSBot

final class DeepViewNumberRuleTests: XCTestCase {
    func testNumberRuleClampsAndSnapsToNodeBounds() {
        let rule = DeepViewNumberRule(node: .object([
            "min": .number(2), "max": .number(10), "step": .number(2),
        ]))
        XCTAssertEqual(rule.normalize(-4), 2)
        XCTAssertEqual(rule.normalize(5), 6)
        XCTAssertEqual(rule.normalize(100), 10)
    }
}

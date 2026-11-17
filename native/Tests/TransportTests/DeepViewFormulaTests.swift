import XCTest
@testable import DSBot

final class DeepViewFormulaTests: XCTestCase {
    func testInputAndLetFormulaMatchMobileResults() {
        let root = JSONValue.object([
            "let": .object(["total": .object(["=": .string("price * qty")])]),
        ])
        guard let formula = DeepViewFormula(root: root) else {
            XCTFail("Bundled deep-view formula parser did not load")
            return
        }
        let inputs: [String: JSONValue] = ["price": .number(3), "qty": .number(4)]
        XCTAssertEqual(formula.resolve(.object(["=": .string("total")]), inputs: inputs), .number(12))
        XCTAssertEqual(formula.resolve(.object(["=": .string("total")]),
                                       inputs: ["price": .number(3), "qty": .number(5)]), .number(15))
        XCTAssertEqual(formula.resolve(.object(["=": .string("qty > 3 ? fixed(total, 1) : 'low'")]),
                                       inputs: inputs), .string("12.0"))
        XCTAssertNil(formula.resolve(.object(["=": .string("missing + 1")]), inputs: inputs))
    }
}

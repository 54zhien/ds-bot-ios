import UIKit
import XCTest
@testable import DSBot

final class DeepViewChartTests: XCTestCase {
    func testLegendTableAndCSVAffectChartControls() {
        let chart = DeepViewChartView(node: .object([
            "type": .string("chart"),
            "kind": .string("bar"),
            "categories": .array([.string("A,B"), .string("C")]),
            "series": .array([.object([
                "name": .string("Sales"), "values": .array([.number(2), .number(3)]),
            ])]),
            "unit": .string("%"),
        ]))
        func button(_ name: String) -> UIButton? {
            func find(_ view: UIView) -> UIButton? {
                if let button = view as? UIButton, button.accessibilityLabel == name { return button }
                for child in view.subviews {
                    if let found = find(child) { return found }
                }
                return nil
            }
            return find(chart)
        }
        guard let legend = button("Sales"), let menu = button(NativeLanguage.text("Chart options")),
              let asTable = button(NativeLanguage.text("View as table")),
              let copy = button(NativeLanguage.text("Copy data (CSV)")),
              let asChart = button(NativeLanguage.text("View as chart")) else {
            XCTFail("Chart controls are missing")
            return
        }
        legend.sendActions(for: .touchUpInside)
        XCTAssertEqual(legend.accessibilityValue, NativeLanguage.text("Hidden"))
        legend.sendActions(for: .touchUpInside)
        XCTAssertEqual(legend.accessibilityValue, NativeLanguage.text("Visible"))
        menu.sendActions(for: .touchUpInside)
        asTable.sendActions(for: .touchUpInside)
        XCTAssertFalse(asChart.superview?.isHidden ?? true)
        asChart.sendActions(for: .touchUpInside)
        menu.sendActions(for: .touchUpInside)
        copy.sendActions(for: .touchUpInside)
        XCTAssertEqual(UIPasteboard.general.string, ",Sales\n\"A,B\",2.0\nC,3.0")
    }
}

import UIKit
import XCTest
@testable import DSBot

/// The icons are the RN file's own d-strings, parsed at runtime: these tests hold
/// the parser to the SVG rules and hold every glyph inside its 20×20 viewBox, so a
/// mis-copied string cannot land silently on a screen. The on-screen look — the
/// same glyph on every screen matching the RN app — is a device check.
final class IconTests: XCTestCase {
    // MARK: - The parser

    func testMovesAndLinesAbsoluteAndRelative() {
        let path = SVGPath.parse("M1 2L3 4l2 2")
        XCTAssertEqual(elements(path), 3)
        XCTAssertEqual(path.bounds, CGRect(x: 1, y: 2, width: 4, height: 4))
    }

    func testExtraMovePairsBecomeLines() {
        let path = SVGPath.parse("M1 2 3 4 5 6")
        XCTAssertEqual(elements(path), 3, "the first pair moves, the rest are line-tos")
    }

    func testHorizontalAndVertical() {
        let path = SVGPath.parse("M1 2H5V6h2v1")
        XCTAssertEqual(path.bounds, CGRect(x: 1, y: 2, width: 6, height: 5))
        // 1,2 → 5,2 → 5,6 → 7,6 → 7,7
        XCTAssertEqual(elements(path), 5)
    }

    func testPackedNumbersSplitAndSetsRepeat() {
        // The compact forms icons.tsx writes: no separator before a sign or a
        // second decimal point, and argument sets that repeat under one letter.
        let path = SVGPath.parse("M1 2c1.6.6 2.6 2 3 4.1l3.5 3.5 7.5-8")
        XCTAssertEqual(elements(path), 4, "a move, a curve, and two lines out of four argument sets")
    }

    func testCurvesAndTheSmoothReflection() {
        let path = SVGPath.parse("M0 0C1 1 2 1 3 0S5 -1 6 0")
        XCTAssertEqual(elements(path), 3)
        // The S command reflects the previous curve's second control: (2,1) about (3,0).
        let points = controlPoints(path)
        XCTAssertEqual(points[2] ?? .zero, CGPoint(x: 4, y: 1))
    }

    func testQuadraticsAndTheTrailingReflection() {
        let path = SVGPath.parse("M0 0Q2 0 4 0T8 0")
        XCTAssertEqual(elements(path), 3)
        // The T command reflects (2,0) about (4,0).
        let points = controlPoints(path)
        XCTAssertEqual(points[2] ?? .zero, CGPoint(x: 6, y: 0))
    }

    func testACircleClosesIntoExactBounds() {
        // Gear's own inner ring: two arcs under one command and a close must
        // land on the same circle — the second arc is what a parser that stops
        // after the first argument set loses.
        let path = SVGPath.parse("M10 7.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z")
        XCTAssertEqual(path.bounds.minX, 7.4, accuracy: 0.001)
        XCTAssertEqual(path.bounds.minY, 7.4, accuracy: 0.001)
        XCTAssertEqual(path.bounds.width, 5.2, accuracy: 0.001)
        XCTAssertEqual(path.bounds.height, 5.2, accuracy: 0.001)
    }

    func testTheSweepFlagPicksTheSide() {
        let up = SVGPath.parse("M0 0A5 5 0 0 1 10 0")
        // y grows downward, so sweep 1 curls through negative y.
        XCTAssertEqual(up.bounds.minY, -5, accuracy: 0.001)
        XCTAssertEqual(up.bounds.maxY, 0, accuracy: 0.001)
        let down = SVGPath.parse("M0 0A5 5 0 0 0 10 0")
        XCTAssertEqual(down.bounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(down.bounds.maxY, 5, accuracy: 0.001)
    }

    func testTheLargeArcFlagTakesTheLongWayRound() {
        // A chord short of the diameter, so the two flags part ways; with the
        // endpoints diametrically opposite both arcs are halves and the flag
        // cannot show.
        let small = SVGPath.parse("M0 0A5 5 0 0 1 6 0")
        XCTAssertEqual(small.bounds.height, 1, accuracy: 0.001)
        let large = SVGPath.parse("M0 0A5 5 0 1 1 6 0")
        XCTAssertEqual(large.bounds.height, 9, accuracy: 0.001)
    }

    func testAnEllipticalArcKeepsItsOwnRadii() {
        let path = SVGPath.parse("M0 0A4 2 0 0 1 8 0")
        XCTAssertEqual(path.bounds.height, 2, accuracy: 0.001)
        XCTAssertEqual(path.bounds.width, 8, accuracy: 0.001)
    }

    func testCloseReturnsToTheStart() {
        let path = SVGPath.parse("M0 0L10 0L10 10Z")
        XCTAssertEqual(elements(path), 4, "move, two lines, close")
    }

    // MARK: - The set

    func testEveryGlyphStaysInsideTheViewBox() {
        for icon: Icon in [
            .chevronLeft, .chevronRight, .sidebar, .search, .plus, .arrowUp, .arrowDown,
            .gear, .people, .unread, .pinMark, .mainStar, .stop, .dots, .check, .close, .side,
        ] {
            let union = UIBezierPath()
            for part in icon.geometry() { union.append(part) }
            let frame = CGRect(x: 0, y: 0, width: 20, height: 20).insetBy(dx: -0.01, dy: -0.01)
            XCTAssertTrue(
                frame.contains(union.bounds),
                "\(icon) draws to \(union.bounds), outside the 20×20 viewBox")
        }
    }

    func testTheLineGlyphsCarryExactlyTheirOwnCommands() {
        // chevronRight: M + L + l. plus: M v M h. close: M l M L. check: M l l.
        XCTAssertEqual(elements(Icon.chevronRight.geometry()[0]), 3)
        XCTAssertEqual(elements(Icon.plus.geometry()[0]), 4)
        XCTAssertEqual(elements(Icon.close.geometry()[0]), 4)
        XCTAssertEqual(elements(Icon.check.geometry()[0]), 3)
    }

    func testTheStrokeWeightFollowsTheSize() {
        XCTAssertEqual(Icon.strokeWidth(for: 12), 1.6)
        XCTAssertEqual(Icon.strokeWidth(for: 20), 1.7)
        XCTAssertEqual(Icon.strokeWidth(for: 22), 1.8)
        XCTAssertEqual(Icon.strokeWidth(for: 26), 1.9)
        XCTAssertEqual(Icon.strokeWidth(for: 28), 2)
    }

    func testTheImageRendererProducesTheGlyph() {
        let image = Icon.chevronRight.image(size: 16, color: .label)
        XCTAssertEqual(image.size.width, 16)
        XCTAssertEqual(image.size.height, 16)
        XCTAssertFalse(
            Icon.gear.image(size: 26, color: .label).withRenderingMode(.alwaysTemplate)
                .renderingMode != .alwaysTemplate)
    }

    // MARK: - Helpers

    private func elements(_ path: UIBezierPath) -> Int {
        var count = 0
        path.cgPath.applyWithBlock { _ in count += 1 }
        return count
    }

    /// The first control point of every curve, in order.
    private func controlPoints(_ path: UIBezierPath) -> [CGPoint?] {
        var points: [CGPoint?] = []
        path.cgPath.applyWithBlock { element in
            switch element.pointee.type {
            case .addCurveToPoint, .addQuadCurveToPoint:
                points.append(element.pointee.points.pointee)
            default:
                points.append(nil)
            }
        }
        return points
    }
}

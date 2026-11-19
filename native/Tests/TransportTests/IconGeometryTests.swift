import XCTest
@testable import DSBot

/// icons.tsx gives every glyph the same 20x20 viewBox; where the ink lands inside
/// the view decides whether it reads centred. Each icon is rasterised at the sizes
/// the app asks for, one pixel per point, and its non-transparent box must sit
/// centred, unclipped, and the same shape at every size.
///
/// Two glyphs are asymmetric by design and belong on the reviewed list below
/// rather than a quiet pass: unread carries its badge off the corner, and people
/// its second head. If they fail, say so with the numbers — never delete an
/// assertion to make them pass.
@MainActor
final class IconGeometryTests: XCTestCase {
    private let sizes: [CGFloat] = [12, 15, 16, 18, 19, 20, 22, 26, 28]
    private let icons: [Icon] = [.chevronLeft, .chevronRight, .sidebar, .search, .plus,
                                 .arrowUp, .arrowDown, .gear, .people, .unread, .pinMark,
                                 .mainStar, .stop, .dots, .check, .close, .side]

    /// What a raster produced. "no bitmap" and "bitmap with no ink" are separate
    /// answers on purpose: merging them reported a broken harness as 17 broken
    /// icons, and cost a night.
    private enum Raster {
        case ink(CGRect)
        case noBitmap
        case noInk
    }

    /// Four pixels per point. At one, a stroke whose edge lands on a half point has
    /// to pick a side, and its box then reads a whole point off centre; the aspect
    /// of a 12pt raster (9x11 against 10x10) drifts by 0.2 on the grid alone. Both
    /// are the ruler, not the glyph.
    private static let sample: CGFloat = 4

    /// The bitmap is ours, not UIGraphicsImageRenderer's: its alpha byte position
    /// follows the format it picked, and reading the wrong channel finds no ink in
    /// a picture full of it. premultipliedLast puts alpha at byte 3 every time.
    private func raster(_ size: CGFloat, _ paint: (CGContext) -> Void) -> Raster {
        let side = Int((size * Self.sample).rounded())
        guard side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = context.data else { return .noBitmap }
        // UIKit draws with y down; a raw context has y up. Scaling here keeps the
        // painter in points while the bitmap holds more pixels.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: Self.sample, y: -Self.sample)
        UIGraphicsPushContext(context)
        paint(context)
        UIGraphicsPopContext()
        let bytes = buffer.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<side {
            for x in 0..<side where bytes[(y * side + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .noInk }
        return .ink(CGRect(x: CGFloat(minX) / Self.sample, y: CGFloat(minY) / Self.sample,
                           width: CGFloat(maxX - minX + 1) / Self.sample,
                           height: CGFloat(maxY - minY + 1) / Self.sample))
    }

    private func render(_ icon: Icon, size: CGFloat, ring: UIColor? = nil) -> Raster {
        raster(size) { _ in
            icon.draw(in: CGRect(x: 0, y: 0, width: size, height: size), color: .black, ring: ring)
        }
    }

    /// TeamList's hand-drawn glyphs share the same contract.
    private func renderView(_ view: UIView, size: CGFloat) -> Raster {
        view.tintColor = .black
        return raster(size) { _ in view.draw(CGRect(x: 0, y: 0, width: size, height: size)) }
    }

    /// The box the glyph's own path occupies in the 20-unit viewBox. A glyph whose
    /// path is not centred there cannot draw centred whatever the renderer does.
    private func pathBox(_ icon: Icon) -> CGRect {
        let union = UIBezierPath()
        for part in icon.geometry() { union.append(part) }
        return union.bounds
    }

    /// Reviewed as asymmetric inside the 20 box, so a centred assertion never held
    /// for them: unread hangs its badge off a corner (x to 17.1) and pinMark sits on
    /// 5.1–12.9 across and 2.5–15 down. They match RN because the path is the same
    /// path; the list keeps the reason on record instead of the assertion being
    /// deleted. A glyph belongs here only if icon.geometry() itself is off centre —
    /// the test enforces that below, so the list cannot rot. side left the list when
    /// its two parts started being placed by their own boxes (Icon.sideGlyph());
    /// it is centred in the 20 box now, so a centred assertion holds for it.
    private let reviewedAsymmetric: Set<Icon> = [.unread, .pinMark]

    /// The ink must land where the path says, and the path must be centred unless it
    /// is on the reviewed list. Both halves are asserted, so neither can rot.
    private func assertInkFollowsItsPath(_ box: CGRect, icon: Icon, size: CGFloat) {
        let path = pathBox(icon)
        let expectedX = path.midX / 20 * size
        let expectedY = path.midY / 20 * size
        XCTAssertEqual(box.midX, expectedX, accuracy: 0.5,
            "\(icon) at \(size)pt: ink centre x \(box.midX), the path puts it at \(expectedX)")
        XCTAssertEqual(box.midY, expectedY, accuracy: 0.5,
            "\(icon) at \(size)pt: ink centre y \(box.midY), the path puts it at \(expectedY)")
        XCTAssertGreaterThanOrEqual(box.minX, -0.5, "\(icon) at \(size)pt: clipped on the left")
        XCTAssertLessThanOrEqual(box.maxX, size + 0.5, "\(icon) at \(size)pt: clipped on the right")
        XCTAssertGreaterThanOrEqual(box.minY, -0.5, "\(icon) at \(size)pt: clipped on the top")
        XCTAssertLessThanOrEqual(box.maxY, size + 0.5, "\(icon) at \(size)pt: clipped on the bottom")
        let offCentre = abs(path.midX - 10) > 0.25 || abs(path.midY - 10) > 0.25
        if reviewedAsymmetric.contains(icon) {
            XCTAssertTrue(offCentre, "\(icon) is on the reviewed list but its path is centred: take it off")
        } else {
            XCTAssertFalse(offCentre, "\(icon) draws off centre in its 20 box: add it to reviewedAsymmetric with the measurement")
        }
    }

    private func assertCentred(_ box: CGRect, in size: CGFloat, _ label: String) {
        XCTAssertLessThanOrEqual(abs(box.midX - size / 2), 0.5,
            "\(label) at \(size)pt: ink centre x is \(box.midX), view centre \(size / 2)")
        XCTAssertLessThanOrEqual(abs(box.midY - size / 2), 0.5,
            "\(label) at \(size)pt: ink centre y is \(box.midY), view centre \(size / 2)")
        XCTAssertGreaterThanOrEqual(box.minX, -0.5, "\(label) at \(size)pt: clipped on the left")
        XCTAssertLessThanOrEqual(box.maxX, size + 0.5, "\(label) at \(size)pt: clipped on the right")
        XCTAssertGreaterThanOrEqual(box.minY, -0.5, "\(label) at \(size)pt: clipped on the top")
        XCTAssertLessThanOrEqual(box.maxY, size + 0.5, "\(label) at \(size)pt: clipped on the bottom")
    }

    // MARK: - The harness proves itself first

    /// A disc that must land in the middle: if this finds nothing, the rig is
    /// broken and every icon result below it is worthless.
    func testTheHarnessFindsInkThatIsThere() {
        let result = raster(20) { _ in
            UIColor.red.setFill()
            UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 10, height: 10)).fill()
        }
        guard case .ink(let box) = result else {
            XCTFail("a 10pt red disc on a 20pt raster came back as \(result)")
            return
        }
        XCTAssertEqual(box.midX, 10, accuracy: 1, "the disc's centre x")
        XCTAssertEqual(box.midY, 10, accuracy: 1, "the disc's centre y")
        XCTAssertEqual(box.width, 10, accuracy: 1.5)
    }

    /// The same rig must also say when something is off centre, or a passing
    /// geometry test would mean nothing.
    func testTheHarnessReportsOffCentreInk() {
        let result = raster(20) { _ in
            UIColor.red.setFill()
            UIBezierPath(rect: CGRect(x: 7, y: 7, width: 10, height: 10)).fill()
        }
        guard case .ink(let box) = result else {
            XCTFail("a 10pt square on a 20pt raster came back as \(result)")
            return
        }
        XCTAssertGreaterThan(abs(box.midX - 10), 1.5, "a square shifted 2pt must read off centre")
        XCTAssertGreaterThan(abs(box.midY - 10), 1.5)
    }

    // MARK: - The glyphs

    func testInkStaysCentredUnclippedAndUndistorted() {
        for icon in icons {
            var boxes: [CGRect] = []
            for size in sizes {
                switch render(icon, size: size) {
                case .noBitmap:
                    XCTFail("\(icon) at \(size)pt: the raster made no bitmap")
                    continue
                case .noInk:
                    XCTFail("\(icon) at \(size)pt: the glyph left no ink")
                    continue
                case .ink(let box):
                    boxes.append(box)
                    assertInkFollowsItsPath(box, icon: icon, size: size)
                }
            }
            // A shape whose own path has no height or no width has no aspect to keep:
            // dots pins y at 10 for all three points, so its ratio drifts with the
            // stroke width rather than with the drawing. Judged on the path, not on
            // a height threshold, so a change to strokeWidth cannot restart this.
            let path = pathBox(icon)
            if path.width >= 0.5 && path.height >= 0.5 {
                let ratios = boxes.map { $0.height > 0 ? $0.width / $0.height : .greatestFiniteMagnitude }
                if let low = ratios.min(), let high = ratios.max() {
                    XCTAssertLessThanOrEqual(high - low, 0.1,
                        "\(icon) changes shape between sizes: aspect \(low) to \(high)")
                }
            }
        }
    }

    /// marks.tsx:87: the star's cut-out ring shares the frame, so the pair must
    /// still land centred.
    func testMainStarRingStaysCentred() {
        for size in sizes {
            switch render(.mainStar, size: size, ring: .white) {
            case .noBitmap:
                XCTFail("mainStar ring at \(size)pt: the raster made no bitmap")
            case .noInk:
                XCTFail("mainStar ring at \(size)pt: the glyph left no ink")
            case .ink(let box):
                assertCentred(box, in: size, "mainStar ring")
            }
        }
    }

    // MARK: - The gear

    /// The gear is two stroked paths and nothing else: no fill, so no fill rule can
    /// punch a hole in it, and the outline never comes nearer the middle than r 5.999
    /// while the inner circle sits at r 2.6. The gap between them is empty at every
    /// size the app asks for, which is what the reported dark patches would have to
    /// occupy. Held at 20, 28 and 44 so a future path edit cannot fill it in.
    func testTheGearsGapStaysEmptyAtEverySize() {
        for size in [20, 28, 44] as [CGFloat] {
            XCTAssertEqual(alpha(.gear, size: size, at: CGPoint(x: 10, y: 10)) ?? 255, 0,
                           "gear \(size)pt: the middle of the ring is empty")
            XCTAssertEqual(alpha(.gear, size: size, at: CGPoint(x: 10, y: 6.2)) ?? 255, 0,
                           "gear \(size)pt: the gap between the ring and the teeth is empty")
            XCTAssertGreaterThan(alpha(.gear, size: size, at: CGPoint(x: 10, y: 7.4)) ?? 0, 200,
                                 "gear \(size)pt: the inner circle is drawn")
            XCTAssertGreaterThan(alpha(.gear, size: size, at: CGPoint(x: 10, y: 2.53)) ?? 0, 200,
                                 "gear \(size)pt: the teeth are drawn")
        }
    }

    /// Alpha at a point given in the 20-unit box. The one reader here that wants a
    /// pixel rather than a box: the question is whether a spot is empty, and a box
    /// cannot answer that.
    private func alpha(_ icon: Icon, size: CGFloat, at point: CGPoint) -> UInt8? {
        let side = Int((size * Self.sample).rounded())
        guard side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = context.data else { return nil }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: Self.sample, y: -Self.sample)
        UIGraphicsPushContext(context)
        icon.draw(in: CGRect(x: 0, y: 0, width: size, height: size), color: .black)
        UIGraphicsPopContext()
        let column = Int((point.x / 20 * size * Self.sample).rounded(.down))
        let row = Int((point.y / 20 * size * Self.sample).rounded(.down))
        guard column >= 0, column < side, row >= 0, row < side else { return nil }
        return buffer.bindMemory(to: UInt8.self, capacity: side * side * 4)[(row * side + column) * 4 + 3]
    }

    // MARK: - The side glyph

    /// The user's rule: the cross may move, nothing else. The bubble's own box centre
    /// is (10.52, 11.13) in the 20 box and the cross sits at (10, 10), so the cross
    /// read off; each part is placed by its own bounding box instead.
    func testTheSideCrossSitsInTheMiddleOfTheBubble() {
        let parts = Icon.side.geometry()
        XCTAssertEqual(parts.count, 2, "the bubble and the cross")
        guard parts.count == 2 else { return }
        let bubble = parts[0], cross = parts[1]
        XCTAssertEqual(Icon.centre(of: bubble).x, 10, accuracy: 0.25, "the bubble is centred in the button")
        XCTAssertEqual(Icon.centre(of: bubble).y, 10, accuracy: 0.25)
        XCTAssertEqual(Icon.centre(of: cross).x, Icon.centre(of: bubble).x, accuracy: 0.25,
                       "the cross is centred in the bubble")
        XCTAssertEqual(Icon.centre(of: cross).y, Icon.centre(of: bubble).y, accuracy: 0.25)

        // Both parts are the old outline, translated: a raster comparison of drawings
        // shifted by half a point can only be approximate, the curve points are exact.
        assertIsTranslation(bubble, of: SVGPath.parse("M17 11.5a6.5 6.5 0 0 1-6.5 6.5H4l2-2.6A6.5 6.5 0 1 1 17 11.5Z"))
        assertIsTranslation(cross, of: SVGPath.parse("M8.8 8.8 11.2 11.2M11.2 8.8 8.8 11.2"))
    }

    /// Every curve point of `moved` must be the old one plus one offset. A change to
    /// the outline — a radius, an arm, a stroke path — moves a point by something
    /// other than that offset and fails here.
    private func assertIsTranslation(_ moved: UIBezierPath, of original: UIBezierPath,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let before = IconGeometryTests.points(of: original.cgPath)
        let after = IconGeometryTests.points(of: moved.cgPath)
        XCTAssertEqual(after.count, before.count, "the element count changed", file: file, line: line)
        guard after.count == before.count,
              let startBefore = before.first, let startAfter = after.first else { return }
        let shift = CGPoint(x: startAfter.x - startBefore.x, y: startAfter.y - startBefore.y)
        for index in after.indices {
            XCTAssertEqual(after[index].x, before[index].x + shift.x, accuracy: 0.001,
                           "element \(index) moved by more than the shift", file: file, line: line)
            XCTAssertEqual(after[index].y, before[index].y + shift.y, accuracy: 0.001,
                           "element \(index) moved by more than the shift", file: file, line: line)
        }
    }

    /// Every point CGPath walks: the ends and the control points alike.
    private static func points(of path: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        path.applyWithBlock { element in
            let typed = element.pointee
            switch typed.type {
            case .moveToPoint, .addLineToPoint:
                out.append(typed.points[0])
            case .addQuadCurveToPoint:
                out.append(typed.points[0])
                out.append(typed.points[1])
            case .addCurveToPoint:
                out.append(typed.points[0])
                out.append(typed.points[1])
                out.append(typed.points[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return out
    }

    func testOriginalGlyphsStayCentred() {
        // One glyph, one geometry: the hand-traced side now draws Icon.side, so its
        // ink is held to that path instead of to the box.
        let makers: [(String, Icon?, () -> OriginalIconView)] = [
            ("sidebar", nil, { OriginalSidebarIcon() }),
            ("chevronRight", nil, { OriginalChevronRightIcon() }),
            ("side", .side, { OriginalSideIcon() }),
            ("search", nil, { OriginalSearchIcon() }),
        ]
        for (name, icon, make) in makers {
            for size in sizes {
                switch renderView(make(), size: size) {
                case .noBitmap:
                    XCTFail("\(name) at \(size)pt: the raster made no bitmap")
                case .noInk:
                    XCTFail("\(name) at \(size)pt: the glyph left no ink")
                case .ink(let box):
                    if let icon {
                        let expectedX = pathBox(icon).midX / 20 * size
                        let expectedY = pathBox(icon).midY / 20 * size
                        XCTAssertEqual(box.midX, expectedX, accuracy: 0.5,
                            "\(name) at \(size)pt: ink centre x \(box.midX), Icon.\(icon) puts it at \(expectedX)")
                        XCTAssertEqual(box.midY, expectedY, accuracy: 0.5,
                            "\(name) at \(size)pt: ink centre y \(box.midY), Icon.\(icon) puts it at \(expectedY)")
                    } else {
                        assertCentred(box, in: size, name)
                    }
                }
            }
        }
    }
}

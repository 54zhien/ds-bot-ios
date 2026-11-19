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
    /// for them: unread hangs its badge off a corner (x to 17.1), pinMark sits on
    /// 5.1–12.9 across and 2.5–15 down, side spans 3–18 down. They match RN because
    /// the path is the same path; the list keeps the reason on record instead of the
    /// assertion being deleted. A glyph belongs here only if icon.geometry() itself
    /// is off centre — the test enforces that below, so the list cannot rot.
    private let reviewedAsymmetric: Set<Icon> = [.unread, .pinMark, .side]

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

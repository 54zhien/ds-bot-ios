import XCTest
@testable import DSBot

/// icons.tsx gives every glyph the same 20x20 viewBox; where the ink lands inside
/// the view decides whether it reads centred. Each icon is rasterised at the sizes
/// the app asks for, one pixel per point, and its non-transparent box must sit
/// centred, unclipped, and the same shape at every size. Icons drawn asymmetric
/// on purpose (unread's corner badge, people's second head) will fail here and
/// belong on a reviewed list, not a quiet pass.
@MainActor
final class IconGeometryTests: XCTestCase {
    private let sizes: [CGFloat] = [12, 15, 16, 18, 19, 20, 22, 26, 28]
    private let icons: [Icon] = [.chevronLeft, .chevronRight, .sidebar, .search, .plus,
                                 .arrowUp, .arrowDown, .gear, .people, .unread, .pinMark,
                                 .mainStar, .stop, .dots, .check, .close, .side]

    /// The bounds of every non-transparent pixel, in points at one pixel per point.
    private func ink(of image: UIImage) -> CGRect? {
        guard let cg = image.cgImage, let provider = cg.dataProvider?.data else { return nil }
        guard let bytes = CFDataGetBytePtr(provider), cg.bitsPerPixel == 32 else { return nil }
        let width = cg.width, height = cg.height, row = cg.bytesPerRow
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<height {
            for x in 0..<width {
                if bytes[y * row + x * 4 + 3] > 8 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    private func render(_ icon: Icon, size: CGFloat, ring: UIColor? = nil) -> CGRect? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            // Icon.draw reads UIGraphicsGetCurrentContext; push the renderer's own
            // context so the glyph lands in this bitmap wherever the test runs.
            UIGraphicsPushContext(context.cgContext)
            icon.draw(in: CGRect(x: 0, y: 0, width: size, height: size), color: .black, ring: ring)
            UIGraphicsPopContext()
        }
        return ink(of: image)
    }

    /// TeamList's hand-drawn glyphs share the same contract.
    private func renderView(_ view: UIView, size: CGFloat) -> CGRect? {
        view.tintColor = .black
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            // The hand-drawn views also read the current context, and view.draw is
            // only meaningful with one pushed: give them the bitmap's own.
            UIGraphicsPushContext(context.cgContext)
            view.draw(CGRect(x: 0, y: 0, width: size, height: size))
            UIGraphicsPopContext()
        }
        return ink(of: image)
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

    func testInkStaysCentredUnclippedAndUndistorted() {
        for icon in icons {
            var boxes: [CGRect] = []
            for size in sizes {
                guard let box = render(icon, size: size) else {
                    XCTFail("\(icon) at \(size)pt left no ink")
                    continue
                }
                boxes.append(box)
                assertCentred(box, in: size, "\(icon)")
            }
            let ratios = boxes.map { $0.height > 0 ? $0.width / $0.height : .greatestFiniteMagnitude }
            if let low = ratios.min(), let high = ratios.max() {
                XCTAssertLessThanOrEqual(high - low, 0.1,
                    "\(icon) changes shape between sizes: aspect \(low) to \(high)")
            }
        }
    }

    /// marks.tsx:87: the star's cut-out ring shares the frame, so the pair must
    /// still land centred.
    func testMainStarRingStaysCentred() {
        for size in sizes {
            guard let box = render(.mainStar, size: size, ring: .white) else {
                XCTFail("mainStar ring at \(size)pt left no ink")
                continue
            }
            assertCentred(box, in: size, "mainStar ring")
        }
    }

    func testOriginalGlyphsStayCentred() {
        let makers: [(String, () -> OriginalIconView)] = [
            ("sidebar", { OriginalSidebarIcon() }),
            ("chevronRight", { OriginalChevronRightIcon() }),
            ("side", { OriginalSideIcon() }),
            ("search", { OriginalSearchIcon() }),
        ]
        for (name, make) in makers {
            for size in sizes {
                guard let box = renderView(make(), size: size) else {
                    XCTFail("\(name) at \(size)pt left no ink")
                    continue
                }
                assertCentred(box, in: size, name)
            }
        }
    }
}

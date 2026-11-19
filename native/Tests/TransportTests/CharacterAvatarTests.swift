import XCTest
@testable import DSBot

/// marks.tsx is three things: lookOf's fallbacks, the characterMarkup SvgXml paints,
/// and the seats RoomAvatar cuts. These hold the first to the values characters.js
/// returned for the same ids, and the other two to the pixels they have to produce:
/// the same look twice, the eyes as holes, the mark whole at every size the app asks
/// for, and the gap a later seat cuts.
@MainActor
final class CharacterAvatarTests: XCTestCase {
    /// Four pixels per point, the ruler the icon geometry tests settled on: at one,
    /// a capsule's edge lands on a half pixel and every measurement wobbles.
    private static let sample: CGFloat = 4

    private struct Bitmap {
        let width: Int
        let height: Int
        let sample: CGFloat
        /// Which end of the buffer holds the top of the picture. Measured once by
        /// `rowsStartAtTop` instead of assumed: the drawing space has y down
        /// while the buffer's rows are its own business, and getting it the wrong way
        /// round moves every vertical assertion to the far end of the mark.
        let rowsStartAtTop: Bool
        let bytes: [UInt8]

        func alpha(column: Int, row: Int) -> UInt8 {
            guard column >= 0, column < width, row >= 0, row < height else { return 0 }
            return bytes[(row * width + column) * 4 + 3]
        }

        /// The buffer row holding a y in the view's own coordinates.
        func row(at y: CGFloat) -> Int {
            let drawn = Int((y * sample).rounded(.down))
            return rowsStartAtTop ? drawn : height - 1 - drawn
        }

        /// The top-left corner of a buffer row, in points.
        func y(ofRow row: Int) -> CGFloat {
            CGFloat(rowsStartAtTop ? row : height - 1 - row) / sample
        }

        func alpha(at point: CGPoint) -> UInt8 {
            alpha(column: Int((point.x * sample).rounded(.down)), row: row(at: point.y))
        }

        /// The box the drawing put ink in, in points, y down.
        func inkBox() -> CGRect? {
            var minX = Int.max, maxX = -1, minRow = Int.max, maxRow = -1
            for row in 0..<height {
                for column in 0..<width where alpha(column: column, row: row) > 8 {
                    minX = min(minX, column); maxX = max(maxX, column)
                    minRow = min(minRow, row); maxRow = max(maxRow, row)
                }
            }
            guard maxX >= 0 else { return nil }
            let top = y(ofRow: minRow), bottom = y(ofRow: maxRow) + 1 / sample
            return CGRect(x: CGFloat(minX) / sample, y: min(top, bottom),
                          width: CGFloat(maxX - minX + 1) / sample,
                          height: abs(bottom - top))
        }

        /// How much of a rect holds ink, as a share of its area.
        func coverage(of rect: CGRect) -> CGFloat {
            var filled = 0, total = 0
            let half = 0.5 / sample
            for row in 0..<height {
                for column in 0..<width {
                    let point = CGPoint(x: (CGFloat(column) + 0.5) / sample,
                                        y: y(ofRow: row) + half)
                    guard rect.contains(point) else { continue }
                    total += 1
                    if alpha(column: column, row: row) > 8 { filled += 1 }
                }
            }
            return total == 0 ? 0 : CGFloat(filled) / CGFloat(total)
        }
    }

    /// Measures which end of a bitmap's buffer holds the top of the picture. The
    /// answer steers every sample below, so it is measured rather than assumed: a
    /// context keeps rows in its own order even though the drawing space has y down.
    private static let rowsStartAtTop: Bool = {
        let side = 8
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = context.data else { return true }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(UIColor.white.cgColor)
        // A strip along y = 0, which the flip puts at the top of the picture.
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: 1))
        // Byte 3 is the alpha of the buffer's first pixel.
        return buffer.bindMemory(to: UInt8.self, capacity: side * side * 4)[3] > 0
    }()

    private func raster(_ size: CGFloat, _ paint: (CGContext) -> Void) -> Bitmap? {
        let side = Int((size * Self.sample).rounded())
        guard side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = context.data else { return nil }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: Self.sample, y: -Self.sample)
        UIGraphicsPushContext(context)
        paint(context)
        UIGraphicsPopContext()
        let bytes = buffer.bindMemory(to: UInt8.self, capacity: side * side * 4)
        return Bitmap(width: side, height: side, sample: Self.sample,
                      rowsStartAtTop: Self.rowsStartAtTop,
                      bytes: Array(UnsafeBufferPointer(start: bytes, count: side * side * 4)))
    }

    /// The production path: CharacterAvatarView.draw hands its bounds to the painter.
    private func render(_ look: CharacterMarks.Look, size: CGFloat) -> Bitmap? {
        let view = CharacterAvatarView(look: look)
        view.frame = CGRect(x: 0, y: 0, width: size, height: size)
        return raster(size) { _ in
            view.draw(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    private func renderRoom(_ members: [CharacterMarks.Look], size: CGFloat, plate: UIColor = .clear) -> Bitmap? {
        let view = RoomAvatarView(frame: .zero)
        view.frame = CGRect(x: 0, y: 0, width: size, height: size)
        view.plate = plate
        view.configure(members: members)
        return raster(size) { _ in
            view.draw(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    private func look(_ shape: String = "gumdrop", _ color: String = "blue") -> CharacterMarks.Look {
        CharacterMarks.look(shape: shape, color: color)
    }

    // MARK: - lookOf

    /// node -e: characters.js defaultShape / defaultColor for these ids. The ids
    /// cover ASCII, digits, a dash, an underscore, Han and a surrogate pair, because
    /// fnv1a reads UTF-16 units and Swift must read the same ones.
    func testAnIdDerivesItsOwnShapeAndColour() {
        let rows: [(id: String, shape: String, colour: String)] = [
            ("", "star", "cyan"),
            ("abc", "gumdrop", "cyan"),
            ("bot-1", "gumdrop", "blue"),
            ("b_9f3k", "acorn", "cyan"),
            ("机器人", "gumdrop", "violet"),
            ("🐳", "star", "orange"),
            ("z", "bunny", "violet"),
            ("main-0", "peanut", "red"),
            ("x9", "gumdrop", "red"),
        ]
        for row in rows {
            XCTAssertEqual(CharacterMarks.defaultShape(row.id), row.shape, "shape of \(row.id)")
            XCTAssertEqual(CharacterMarks.defaultColor(row.id), row.colour, "colour of \(row.id)")
        }
        XCTAssertEqual(CharacterMarks.defaultColors,
                       ["red", "orange", "yellow", "green", "cyan", "blue", "violet", "magenta"])
    }

    /// lookOf: a stored pair wins, then the id, then the fallback. JS reads "" as no
    /// id at all, so an empty id must not reach the deriver either.
    func testALookFallsBackTheWayTheDesktopDoes() {
        XCTAssertEqual(CharacterMarks.look(), CharacterMarks.Look(shape: "gumdrop", color: "black", image: nil))
        XCTAssertEqual(CharacterMarks.look(id: ""), CharacterMarks.Look(shape: "gumdrop", color: "black", image: nil))
        XCTAssertEqual(CharacterMarks.look(id: "abc"), CharacterMarks.Look(shape: "gumdrop", color: "cyan", image: nil))
        XCTAssertEqual(CharacterMarks.look(shape: "moon", id: "abc"),
                       CharacterMarks.Look(shape: "moon", color: "cyan", image: nil))
        XCTAssertEqual(CharacterMarks.look(shape: "nonesuch", id: "abc"),
                       CharacterMarks.Look(shape: "gumdrop", color: "cyan", image: nil))
        // "berry" is offered by the picker (manage.tsx:24) but defined nowhere in
        // characters.js, so it takes the same branch — keep it, it is not a typo.
        XCTAssertEqual(CharacterMarks.look(shape: "berry", id: "abc"),
                       CharacterMarks.Look(shape: "gumdrop", color: "cyan", image: nil))
        XCTAssertEqual(CharacterMarks.look(color: "#123456", id: "abc"),
                       CharacterMarks.Look(shape: "gumdrop", color: "#123456", image: nil))
        XCTAssertEqual(CharacterMarks.look(color: "aurora", id: "abc"),
                       CharacterMarks.Look(shape: "gumdrop", color: "aurora", image: nil))
        // isColor does not know the renamed inks, so lookOf swaps kimi for the id's own.
        XCTAssertEqual(CharacterMarks.look(color: "kimi", id: "abc"),
                       CharacterMarks.Look(shape: "gumdrop", color: "cyan", image: nil))
        XCTAssertEqual(CharacterMarks.look(id: "abc", image: "data:image/png;base64,AA").image,
                       "data:image/png;base64,AA")
    }

    // MARK: - The markup, as paths

    /// node -e: the number of <path> elements in each shape's layers.
    func testEveryShapeKeepsItsDecals() {
        let counts: [String: Int] = [
            "whale": 2, "star": 1, "moon": 2, "wave": 2, "squircle": 1, "zed": 2, "hex": 1,
            "gumdrop": 1, "peanut": 1, "saucer": 1, "bunny": 1, "kitty": 1, "beacon": 1,
            "plus": 1, "magnet": 1, "acorn": 1, "pebbles": 1, "cushion": 1, "ring": 1, "gem": 1,
        ]
        XCTAssertEqual(counts.count, CharacterMarks.shapes.count)
        for (id, shape) in CharacterMarks.shapes {
            let art = CharacterPaint.art(for: id)
            XCTAssertEqual(art.decals.count, counts[id], "\(id) decals")
            XCTAssertEqual(art.eyes.count, shape.eyes.count, "\(id) eyes")
            XCTAssertFalse(art.body.isEmpty, "\(id) body")
            XCTAssertTrue(art.body.usesEvenOddFillRule, "\(id) body fills even-odd")
            for decal in art.decals {
                XCTAssertTrue(decal.fill.hasPrefix("#"), "\(id) decal fill \(decal.fill)")
                XCTAssertGreaterThan(decal.alpha, 0, "\(id) decal alpha")
            }
        }
    }

    func testAHexColourParsesBothFormsTheMarkupUses() {
        XCTAssertEqual(CharacterPaint.hexColor("#fff"), CharacterPaint.hexColor("#FFFFFF"))
        XCTAssertEqual(CharacterPaint.hexColor("#000"), CharacterPaint.hexColor("#000000"))
        XCTAssertEqual(CharacterPaint.hexColor("#8A8F98"),
                       UIColor(red: 138 / 255, green: 143 / 255, blue: 152 / 255, alpha: 1))
        XCTAssertNil(CharacterPaint.hexColor("#8A8F9"))
        XCTAssertNil(CharacterPaint.hexColor("#8A8F9Z"))
        XCTAssertNil(CharacterPaint.hexColor(""))
    }

    /// inkFill: a hex is paint, a named ink takes its mode's value, an unknown name
    /// takes the ink table's gray — never a swatch and never the fallback label ink.
    func testANamedColourResolvesPerModeAndAnUnknownOneIsGray() {
        XCTAssertEqual(CharacterPaint.paint(for: "#123456", dark: true),
                       .solid(UIColor(red: 0x12 / 255, green: 0x34 / 255, blue: 0x56 / 255, alpha: 1)))
        XCTAssertEqual(CharacterPaint.paint(for: "violet", dark: false), .solid(CharacterPaint.hexColor("#8B5CF6")!))
        XCTAssertEqual(CharacterPaint.paint(for: "violet", dark: true), .solid(CharacterPaint.hexColor("#7C3AED")!))
        XCTAssertEqual(CharacterPaint.paint(for: "chartreuse", dark: false), .solid(CharacterPaint.hexColor("#8A8F98")!))
        XCTAssertEqual(CharacterPaint.paint(for: "chartreuse", dark: true), .solid(CharacterPaint.hexColor("#6E737B")!))
        XCTAssertEqual(CharacterPaint.paint(for: "", dark: false), .solid(CharacterPaint.hexColor("#8A8F98")!))
    }

    func testOnlyAuroraPaintsAGradient() {
        guard case .gradient(let stops) = CharacterPaint.paint(for: "aurora", dark: false) else {
            return XCTFail("aurora is a gradient")
        }
        XCTAssertEqual(stops.map(\.offset), [0, 0.42, 1])
        XCTAssertEqual(stops.map(\.color), [CharacterPaint.hexColor("#A4FFB0")!,
                                             CharacterPaint.hexColor("#00F0E4")!,
                                             CharacterPaint.hexColor("#2E9EF7")!])
        guard case .solid = CharacterPaint.paint(for: "blue", dark: false) else {
            return XCTFail("a named ink is solid")
        }
    }

    // MARK: - The picture

    func testTheSameLookDrawsTheSameBytes() {
        let first = render(look("whale", "deepseek"), size: 64)
        let second = render(look("whale", "deepseek"), size: 64)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.bytes, second?.bytes)
        // A different colour is a different picture, or the test above proves nothing.
        XCTAssertNotEqual(first?.bytes, render(look("whale", "rose"), size: 64)?.bytes)
    }

    /// The sampler has to agree with the context that drew the pixels. A read that
    /// disagrees moves every vertical assertion to the far end of the mark and finds
    /// paint where the mark has a hole — the shape the eye and the seat gap failed in.
    func testTheSamplerReadsRowsFromTheTop() {
        let size: CGFloat = 40
        guard let bitmap = raster(size, { context in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 4, y: 4, width: 8, height: 8))
        }) else { return XCTFail("no bitmap") }
        XCTAssertEqual(bitmap.alpha(at: CGPoint(x: 8, y: 8)), 255)
        XCTAssertEqual(bitmap.alpha(at: CGPoint(x: 8, y: 32)), 0, "the square sits at the top")
        XCTAssertEqual(bitmap.inkBox()?.minY ?? -1, 4, accuracy: 0.5)
    }

    /// The raster must keep an alpha channel and honour a clear blend, or a hole reads
    /// as paint and no assertion about the eyes could tell the two apart.
    func testTheRasterCanPunchAHole() {
        let size: CGFloat = 20
        guard let bitmap = raster(size, { context in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.setBlendMode(.clear)
            context.fill(CGRect(x: 6, y: 6, width: 8, height: 8))
            context.setBlendMode(.normal)
        }) else { return XCTFail("no bitmap") }
        XCTAssertEqual(bitmap.alpha(at: CGPoint(x: 10, y: 10)), 0, "the hole is a hole")
        XCTAssertEqual(bitmap.alpha(at: CGPoint(x: 2, y: 2)), 255, "the rest is still paint")
    }

    func testTheEyesAreCutOutOfTheBodyNotPaintedOn() {
        let size: CGFloat = 128
        guard let bitmap = render(look("gumdrop", "blue"), size: size) else { return XCTFail("no bitmap") }
        let eye = CharacterMarks.shapeOf("gumdrop").eyes[0]
        let centre = CGPoint(x: eye.cx * size / 100, y: eye.cy * size / 100)
        XCTAssertEqual(bitmap.alpha(at: centre), 0, "the eye is a hole through the mark")
        // Between the eyes and below them the body is solid: the hole is a hole, not
        // a picture with nothing drawn at all.
        XCTAssertGreaterThan(bitmap.alpha(at: CGPoint(x: 40, y: 60)), 200)
        XCTAssertGreaterThan(bitmap.alpha(at: CGPoint(x: 50, y: 80)), 200)
    }

    func testAMarkWithAPictureIsCroppedToItsCircle() {
        let square = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        guard let png = square.pngData() else { return XCTFail("no png") }
        let url = "data:image/png;base64," + png.base64EncodedString()
        let size: CGFloat = 48
        guard let bitmap = raster(size, { _ in
            CharacterPaint.draw(CharacterMarks.look(id: "abc", image: url),
                                in: CGRect(x: 0, y: 0, width: size, height: size), dark: false)
        }) else { return XCTFail("no bitmap") }
        XCTAssertGreaterThan(bitmap.alpha(at: CGPoint(x: 24, y: 24)), 200, "the picture covers the middle")
        XCTAssertEqual(bitmap.alpha(at: CGPoint(x: 1, y: 1)), 0, "the corners are outside the circle")
        XCTAssertEqual(bitmap.alpha(at: CGPoint(x: 46, y: 46)), 0)
    }

    /// cropTo fits the whole mark into the box at any size, so the ink's share of the
    /// box may not move with the size; a clipped or re-scaled mark moves it at once.
    func testTheMarkKeepsItsShapeAtEverySizeWithoutClipping() {
        let sizes: [CGFloat] = [24, 36, 44, 64]
        for shape in ["whale", "gumdrop", "star"] {
            guard let reference = render(look(shape, "blue"), size: 96)?.inkBox() else {
                return XCTFail("\(shape) at 96 drew nothing")
            }
            let normal = CGRect(x: reference.minX / 96, y: reference.minY / 96,
                                width: reference.width / 96, height: reference.height / 96)
            for size in sizes {
                guard let box = render(look(shape, "blue"), size: size)?.inkBox() else {
                    return XCTFail("\(shape) at \(size) drew nothing")
                }
                // Whole: ink that reaches the bitmap's edge was cut by it, whatever
                // the size; every shape is drawn inside its box with a margin.
                XCTAssertGreaterThan(box.minX, 0, "\(shape) \(size) is cut on the left")
                XCTAssertLessThan(box.maxX, size, "\(shape) \(size) is cut on the right")
                XCTAssertGreaterThan(box.minY, 0, "\(shape) \(size) is cut on the top")
                XCTAssertLessThan(box.maxY, size, "\(shape) \(size) is cut on the bottom")
                let scaled = CGRect(x: box.minX / size, y: box.minY / size,
                                    width: box.width / size, height: box.height / size)
                XCTAssertEqual(scaled.minX, normal.minX, accuracy: 0.02, "\(shape) \(size) x")
                XCTAssertEqual(scaled.minY, normal.minY, accuracy: 0.02, "\(shape) \(size) y")
                XCTAssertEqual(scaled.width, normal.width, accuracy: 0.02, "\(shape) \(size) width")
                XCTAssertEqual(scaled.height, normal.height, accuracy: 0.02, "\(shape) \(size) height")
            }
        }
    }

    func testAnUnknownShapeDrawsTheFallbackGumdrop() {
        let unknown = CharacterMarks.look(shape: "nonesuch", color: "blue")
        XCTAssertEqual(unknown.shape, "gumdrop")
        XCTAssertEqual(render(unknown, size: 40)?.bytes, render(look("gumdrop", "blue"), size: 40)?.bytes)
    }

    // MARK: - The room

    func testEverySeatOfAFourMemberRoomDrawsItsOwnMark() {
        let members = [look("whale", "deepseek"), look("star", "yellow"), look("moon", "violet"), look("bunny", "rose")]
        let size: CGFloat = 96
        guard let bitmap = renderRoom(members, size: size) else { return XCTFail("no bitmap") }
        let half = size / 2
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: half, y: 0), CGPoint(x: 0, y: half), CGPoint(x: half, y: half)] {
            let seat = CGRect(x: corner.x, y: corner.y, width: half, height: half)
            XCTAssertGreaterThan(bitmap.coverage(of: seat), 0.25, "seat at \(corner)")
        }
    }

    /// The gap is the later seat's own cut-out: a circle of 48% of its side plus
    /// frame/14 that eats into whatever it overlaps. Find a point the first seat
    /// paints and the second seat does not cover, and hold it empty in the room.
    func testALaterSeatCutsAGapIntoTheOneItOverlaps() {
        let size: CGFloat = 120
        let side = size * 2 / 3
        guard let bare = raster(size, { _ in
            CharacterPaint.draw(look("gumdrop", "blue"), in: CGRect(x: 0, y: 0, width: side, height: side), dark: false)
        }) else { return XCTFail("no bitmap") }
        guard let room = renderRoom([look("gumdrop", "blue"), look("gumdrop", "rose")], size: size) else {
            return XCTFail("no room")
        }
        let seats = AvatarMarks.seats(count: 2, frame: size)
        let cut = AvatarMarks.cutOut(seat: seats[1], frame: size)
        var sample: CGPoint?
        for row in 0..<bare.height {
            for column in 0..<bare.width {
                let point = CGPoint(x: (CGFloat(column) + 0.5) / bare.sample,
                                    y: bare.y(ofRow: row) + 0.5 / bare.sample)
                guard bare.alpha(column: column, row: row) > 200 else { continue }
                guard !seats[1].contains(point) else { continue }
                guard hypot(point.x - cut.centre.x, point.y - cut.centre.y) < cut.radius - 0.5 else { continue }
                sample = point
                break
            }
            if sample != nil { break }
        }
        guard let point = sample else {
            return XCTFail("no point the first seat paints under the second seat's cut-out")
        }
        XCTAssertEqual(room.alpha(at: point), 0, "the cut-out leaves the point behind the seat empty")
    }

    func testASingleMemberRoomShowsTheUsersOwnSeat() {
        let size: CGFloat = 96
        guard let alone = renderRoom([look("gumdrop", "blue")], size: size) else { return XCTFail("no room") }
        let seats = AvatarMarks.seats(count: 2, frame: size)
        // The second seat is a rim, not a mark: little ink, and none of it solid.
        XCTAssertLessThan(alone.coverage(of: seats[1]), 0.1)
        XCTAssertGreaterThan(alone.coverage(of: seats[0]), 0.25)
    }

    func testTheFifthMemberFoldsIntoAPlate() {
        let size: CGFloat = 96
        let members = (1...5).map { look("gumdrop", ["blue", "rose", "green", "yellow", "violet"][$0 - 1]) }
        guard let bitmap = renderRoom(members, size: size) else { return XCTFail("no bitmap") }
        let seats = AvatarMarks.seats(count: 4, frame: size)
        // The plate fills most of the seat; a fourth character would too, but it
        // would not reach this close to the seat's corner.
        XCTAssertGreaterThan(bitmap.coverage(of: seats[3].insetBy(dx: 6, dy: 6)), 0.6)
    }

    func testAnEmptyRoomShowsItsPlateOrNothing() {
        let size: CGFloat = 48
        guard let filled = renderRoom([], size: size, plate: .red) else { return XCTFail("no bitmap") }
        XCTAssertGreaterThan(filled.alpha(at: CGPoint(x: 24, y: 24)), 200)
        XCTAssertEqual(filled.alpha(at: CGPoint(x: 1, y: 1)), 0, "the plate is a circle")
        guard let empty = renderRoom([], size: size) else { return XCTFail("no bitmap") }
        XCTAssertNil(empty.inkBox(), "an empty room with no plate draws nothing")
    }
}

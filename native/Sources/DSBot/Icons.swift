import UIKit

/// An SVG path parser for the d-strings mobile/src/ui/icons.tsx carries: the same
/// command set react-native-svg understands, absolute and relative, with the
/// argument sets that repeat under a command until the next letter. The strings
/// are fixed inputs, so the tokenizer only needs the forms icons.tsx writes:
/// spaced numbers, and the packed kind where a sign or a second decimal point
/// starts the next number.
enum SVGPath {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    static func parse(_ d: String) -> UIBezierPath {
        let path = UIBezierPath()
        let tokens = tokenize(d)
        var cursor = 0
        var start = CGPoint.zero
        var current = CGPoint.zero
        var cubicControl: CGPoint?
        var quadControl: CGPoint?
        while cursor < tokens.count {
            guard case .command(let raw) = tokens[cursor] else { cursor += 1; continue }
            cursor += 1
            let relative = raw.isLowercase
            let kind = Character(String(raw).uppercased())
            if kind == "Z" {
                path.close()
                current = start
                cubicControl = nil
                quadControl = nil
                continue
            }
            // Extra argument sets repeat the command; after a moveto they read
            // as line-tos, the one repeat that changes meaning.
            var firstMove = kind == "M"
            while let arguments = readArguments(kind, tokens, at: cursor) {
                cursor += arguments.count
                switch kind {
                case "M":
                    let point = relative
                        ? CGPoint(x: current.x + arguments[0], y: current.y + arguments[1])
                        : CGPoint(x: arguments[0], y: arguments[1])
                    if firstMove {
                        path.move(to: point)
                        start = point
                        firstMove = false
                    } else {
                        path.addLine(to: point)
                    }
                    current = point
                    cubicControl = nil
                    quadControl = nil
                case "L":
                    let point = relative
                        ? CGPoint(x: current.x + arguments[0], y: current.y + arguments[1])
                        : CGPoint(x: arguments[0], y: arguments[1])
                    path.addLine(to: point)
                    current = point
                    cubicControl = nil
                    quadControl = nil
                case "H":
                    let point = CGPoint(x: relative ? current.x + arguments[0] : arguments[0], y: current.y)
                    path.addLine(to: point)
                    current = point
                    cubicControl = nil
                    quadControl = nil
                case "V":
                    let point = CGPoint(x: current.x, y: relative ? current.y + arguments[0] : arguments[0])
                    path.addLine(to: point)
                    current = point
                    cubicControl = nil
                    quadControl = nil
                case "C":
                    let control1 = relative
                        ? CGPoint(x: current.x + arguments[0], y: current.y + arguments[1])
                        : CGPoint(x: arguments[0], y: arguments[1])
                    let control2 = relative
                        ? CGPoint(x: current.x + arguments[2], y: current.y + arguments[3])
                        : CGPoint(x: arguments[2], y: arguments[3])
                    let point = relative
                        ? CGPoint(x: current.x + arguments[4], y: current.y + arguments[5])
                        : CGPoint(x: arguments[4], y: arguments[5])
                    path.addCurve(to: point, controlPoint1: control1, controlPoint2: control2)
                    current = point
                    cubicControl = control2
                    quadControl = nil
                case "S":
                    let reflection = cubicControl
                        .map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let control2 = relative
                        ? CGPoint(x: current.x + arguments[0], y: current.y + arguments[1])
                        : CGPoint(x: arguments[0], y: arguments[1])
                    let point = relative
                        ? CGPoint(x: current.x + arguments[2], y: current.y + arguments[3])
                        : CGPoint(x: arguments[2], y: arguments[3])
                    path.addCurve(to: point, controlPoint1: reflection, controlPoint2: control2)
                    current = point
                    cubicControl = control2
                    quadControl = nil
                case "Q":
                    let control = relative
                        ? CGPoint(x: current.x + arguments[0], y: current.y + arguments[1])
                        : CGPoint(x: arguments[0], y: arguments[1])
                    let point = relative
                        ? CGPoint(x: current.x + arguments[2], y: current.y + arguments[3])
                        : CGPoint(x: arguments[2], y: arguments[3])
                    path.addQuadCurve(to: point, controlPoint: control)
                    current = point
                    quadControl = control
                    cubicControl = nil
                case "T":
                    let control = quadControl
                        .map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let point = relative
                        ? CGPoint(x: current.x + arguments[0], y: current.y + arguments[1])
                        : CGPoint(x: arguments[0], y: arguments[1])
                    path.addQuadCurve(to: point, controlPoint: control)
                    current = point
                    quadControl = control
                    cubicControl = nil
                case "A":
                    let to = relative
                        ? CGPoint(x: current.x + arguments[5], y: current.y + arguments[6])
                        : CGPoint(x: arguments[5], y: arguments[6])
                    appendArc(
                        to: path, from: current, target: to,
                        radiusX: arguments[0], radiusY: arguments[1], rotation: arguments[2],
                        largeArc: arguments[3] != 0, sweep: arguments[4] != 0)
                    current = to
                    cubicControl = nil
                    quadControl = nil
                default:
                    break
                }
            }
        }
        return path
    }

    // MARK: - Tokens

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var index = d.startIndex
        while index < d.endIndex {
            let character = d[index]
            if character.isWhitespace || character == "," {
                index = d.index(after: index)
            } else if character.isLetter {
                tokens.append(.command(character))
                index = d.index(after: index)
            } else {
                var text = String(character)
                var seenDecimal = character == "."
                index = d.index(after: index)
                while index < d.endIndex {
                    let next = d[index]
                    if next.isWhitespace || next == "," || next.isLetter { break }
                    // The packed form: a sign, or a second decimal point, starts
                    // the next number rather than joining this one.
                    if next == "-" || next == "+" { break }
                    if next == "." && seenDecimal { break }
                    if next == "." { seenDecimal = true }
                    text.append(next)
                    index = d.index(after: index)
                }
                if let value = Double(text) { tokens.append(.number(CGFloat(value))) }
            }
        }
        return tokens
    }

    private static func readArguments(_ kind: Character, _ tokens: [Token], at index: Int) -> [CGFloat]? {
        let count: Int
        switch kind {
        case "M", "L", "T": count = 2
        case "H", "V": count = 1
        case "S", "Q": count = 4
        case "C": count = 6
        case "A": count = 7
        default: return nil
        }
        guard index + count <= tokens.count else { return nil }
        var values: [CGFloat] = []
        for offset in 0..<count {
            guard case .number(let value) = tokens[index + offset] else { return nil }
            values.append(value)
        }
        return values
    }

    // MARK: - Arcs

    /// The SVG endpoint arc as a center arc, by the spec's own conversion (F.6.5).
    /// Y grows downward on both sides, so the sweep flag flips when it meets
    /// UIBezierPath's clockwise.
    private static func appendArc(
        to path: UIBezierPath, from: CGPoint, target: CGPoint,
        radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat,
        largeArc: Bool, sweep: Bool
    ) {
        if from == target || radiusX == 0 || radiusY == 0 {
            path.addLine(to: target)
            return
        }
        var rx = abs(radiusX)
        var ry = abs(radiusY)
        let phi = rotation * .pi / 180
        let cosine = cos(phi)
        let sine = sin(phi)
        // The span in the ellipse's own frame, halved.
        let halfX = (from.x - target.x) / 2
        let halfY = (from.y - target.y) / 2
        let x1 = cosine * halfX + sine * halfY
        let y1 = -sine * halfX + cosine * halfY
        // Radii too small for the span are scaled up, the way the spec demands.
        let ratio = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if ratio > 1 {
            let factor = sqrt(ratio)
            rx *= factor
            ry *= factor
        }
        let sign: CGFloat = largeArc != sweep ? 1 : -1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let numerator = max(0, rx * rx * ry * ry - denominator)
        let coefficient = sign * sqrt(numerator / max(denominator, .ulpOfOne))
        let frameCenterX = coefficient * rx * y1 / ry
        let frameCenterY = coefficient * -ry * x1 / rx
        let unitStartX = (x1 - frameCenterX) / rx
        let unitStartY = (y1 - frameCenterY) / ry
        let unitEndX = (-x1 - frameCenterX) / rx
        let unitEndY = (-y1 - frameCenterY) / ry
        let startAngle = angle(ux: 1, uy: 0, vx: unitStartX, vy: unitStartY)
        var sweepAngle = angle(ux: unitStartX, uy: unitStartY, vx: unitEndX, vy: unitEndY)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }
        let middleX = (from.x + target.x) / 2
        let middleY = (from.y + target.y) / 2
        let center = CGPoint(
            x: cosine * frameCenterX - sine * frameCenterY + middleX,
            y: sine * frameCenterX + cosine * frameCenterY + middleY)
        // Sampled rather than handed to addArc: UIKit's clockwise flag means the
        // opposite direction once the y axis points down, and the endpoint angles
        // above already carry the direction the spec asks for. The samples join
        // the running contour instead of opening a new one, so a later close
        // lands on the glyph's own start point.
        let steps = max(8, Int(abs(sweepAngle) / (.pi / 128)))
        for step in 1...steps {
            let t = startAngle + sweepAngle * CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(
                x: center.x + rx * cos(t) * cosine - ry * sin(t) * sine,
                y: center.y + rx * cos(t) * sine + ry * sin(t) * cosine))
        }
        path.addLine(to: target)
    }

    private static func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        var value = acos(min(1, max(-1, dot / max(length, .ulpOfOne))))
        if ux * vy - uy * vx < 0 { value = -value }
        return value
    }
}

/// Every icon mobile/src/ui/icons.tsx draws. The d-strings are copied verbatim, so
/// an edit there becomes an edit here and nowhere else. All glyphs share the 20×20
/// viewBox; the size follows the RN file's own default when nobody overrides it.
enum Icon {
    case chevronLeft, chevronRight, sidebar, search, plus, arrowUp, arrowDown
    case gear, people, unread, pinMark, mainStar, stop, dots, check, close, side

    private static let star = "M10 2.4l2.29 5.04 5.51.63-4.09 3.74 1.11 5.42L10 14.5l-4.82 2.73 1.11-5.42L2.2 8.07l5.51-.63z"

    /// The render size icons.tsx passes when nobody overrides it.
    var defaultSize: CGFloat {
        switch self {
        case .chevronLeft, .chevronRight, .sidebar, .side: return 24
        case .gear: return 22
        case .pinMark: return 12
        case .mainStar: return 16
        case .check: return 15
        case .search, .plus, .arrowUp, .arrowDown, .people, .unread, .stop, .dots, .close: return 20
        }
    }

    /// strokeOf: a thin stroke goes soft once the glyph grows, so the weight follows
    /// the size the way the system icons do.
    static func strokeWidth(for size: CGFloat) -> CGFloat {
        if size >= 28 { return 2 }
        if size >= 26 { return 1.9 }
        if size >= 22 { return 1.8 }
        if size >= 18 { return 1.7 }
        return 1.6
    }

    func draw(in rect: CGRect, color: UIColor, ring: UIColor? = nil) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.scaleBy(x: rect.width / 20, y: rect.height / 20)
        let weight = Icon.strokeWidth(for: rect.width)
        switch self {
        case .chevronLeft:
            stroke(SVGPath.parse("M12.5 4.5L7 10l5.5 5.5"), color: color, weight: weight,
                   cap: .round, join: .round)
        case .chevronRight:
            stroke(SVGPath.parse("M7.5 4.5L13 10l-5.5 5.5"), color: color, weight: weight,
                   cap: .round, join: .round)
        case .sidebar:
            // icons.tsx leaves the caps alone here: butt ends on both parts.
            stroke(UIBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 14, height: 12), cornerRadius: 2.5),
                   color: color, weight: weight)
            stroke(SVGPath.parse("M8 4v12"), color: color, weight: weight)
        case .search:
            stroke(UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 11, height: 11)), color: color, weight: weight)
            stroke(SVGPath.parse("M13 13l4 4"), color: color, weight: weight, cap: .round)
        case .plus:
            stroke(SVGPath.parse("M10 4v12M4 10h12"), color: color, weight: weight, cap: .round)
        case .arrowUp:
            stroke(SVGPath.parse("M10 16V4M5 9l5-5 5 5"), color: color, weight: weight,
                   cap: .round, join: .round)
        case .arrowDown:
            stroke(SVGPath.parse("M10 4v12M5 11l5 5 5-5"), color: color, weight: weight,
                   cap: .round, join: .round)
        case .gear:
            stroke(SVGPath.parse("M10 7.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"),
                   color: color, weight: weight, cap: .round, join: .round)
            stroke(SVGPath.parse("M7.85 4.4l.29-1.87a7.7 7.7 0 0 1 3.72 0l.29 1.87a6 6 0 0 1 1.63.94l1.76-.69a7.7 7.7 0 0 1 1.86 3.23l-1.47 1.18a6 6 0 0 1 0 1.88l1.47 1.18a7.7 7.7 0 0 1-1.86 3.23l-1.76-.69a6 6 0 0 1-1.63.94l-.29 1.87a7.7 7.7 0 0 1-3.72 0l-.29-1.87a6 6 0 0 1-1.63-.94l-1.76.69a7.7 7.7 0 0 1-1.86-3.23l1.47-1.18a6 6 0 0 1 0-1.88L2.6 7.88a7.7 7.7 0 0 1 1.86-3.23l1.76.69a6 6 0 0 1 1.63-.94z"),
                   color: color, weight: weight, cap: .round, join: .round)
        case .people:
            stroke(UIBezierPath(ovalIn: CGRect(x: 4.5, y: 4, width: 6, height: 6)), color: color, weight: weight)
            stroke(SVGPath.parse("M2 16.5c.6-2.8 2.8-4.5 5.5-4.5s4.9 1.7 5.5 4.5"),
                   color: color, weight: weight, cap: .round)
            stroke(SVGPath.parse("M13 4.3a3 3 0 0 1 0 5.4M15 12.4c1.6.6 2.6 2 3 4.1"),
                   color: color, weight: weight, cap: .round)
        case .unread:
            stroke(SVGPath.parse("M10 3.5a4.5 4.5 0 0 0-4.5 4.5v3L4 13.5h12L14.5 11V8"),
                   color: color, weight: weight, cap: .round, join: .round)
            stroke(SVGPath.parse("M8.3 16a1.8 1.8 0 0 0 3.4 0"),
                   color: color, weight: weight, cap: .round, join: .round)
            stroke(SVGPath.parse("M15.5 3.2a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2z"),
                   color: color, weight: weight, cap: .round, join: .round)
        case .pinMark:
            // Both paths rotate 45° about the frame's centre, the way the RN transform does.
            context.translateBy(x: 10, y: 10)
            context.rotate(by: .pi / 4)
            context.translateBy(x: -10, y: -10)
            fill(SVGPath.parse("M8 2.5h4a.9.9 0 0 1 0 1.8h-.4v4.1c0 1.4 1.1 2.6 2.6 3.1l.7.3v1.5H5.1v-1.5l.7-.3c1.5-.5 2.6-1.7 2.6-3.1V4.3H8a.9.9 0 0 1 0-1.8z"), color: color)
            fill(SVGPath.parse("M9.35 13.3h1.3v3.6L10 18l-.65-1.1z"), color: color)
        case .mainStar:
            // The ring is the same star drawn larger and painted first, so its edge
            // stays whole at small sizes instead of a stroke that halves.
            if let ring {
                let scale = 1 + 4 / rect.width
                let shift = 10 * (1 - scale)
                context.saveGState()
                context.translateBy(x: shift, y: shift)
                context.scaleBy(x: scale, y: scale)
                fill(SVGPath.parse(Icon.star), color: ring)
                context.restoreGState()
            }
            fill(SVGPath.parse(Icon.star), color: color)
        case .stop:
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 3.5, y: 3.5, width: 13, height: 13), cornerRadius: 3).fill()
        case .dots:
            stroke(SVGPath.parse("M5 10h.01M10 10h.01M15 10h.01"), color: color, weight: weight,
                   cap: .round, join: .round)
        case .check:
            stroke(SVGPath.parse("M4.5 10.5l3.5 3.5 7.5-8"), color: color, weight: weight,
                   cap: .round, join: .round)
        case .close:
            stroke(SVGPath.parse("M5 5l10 10M15 5L5 15"), color: color, weight: weight, cap: .round)
        case .side:
            stroke(SVGPath.parse("M17 11.5a6.5 6.5 0 0 1-6.5 6.5H4l2-2.6A6.5 6.5 0 1 1 17 11.5Z"),
                   color: color, weight: weight, cap: .round, join: .round)
            stroke(SVGPath.parse("M8.8 8.8 11.2 11.2M11.2 8.8 8.8 11.2"), color: color, weight: weight,
                   cap: .round, join: .round)
        }
        context.restoreGState()
    }

    /// The glyph as an image, for the places UIKit wants one (list configurations,
    /// bar items) rather than a view. Template mode lets the caller keep tinting.
    func image(size: CGFloat? = nil, color: UIColor, ring: UIColor? = nil, template: Bool = false) -> UIImage {
        let side = size ?? defaultSize
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            draw(in: CGRect(x: 0, y: 0, width: side, height: side), color: color, ring: ring)
        }
        return template ? rendered.withRenderingMode(.alwaysTemplate) : rendered
    }

    // MARK: - Painting

    private func stroke(_ path: UIBezierPath, color: UIColor, weight: CGFloat,
                        cap: CGLineCap = .butt, join: CGLineJoin = .miter) {
        color.setStroke()
        path.lineWidth = weight
        path.lineCapStyle = cap
        path.lineJoinStyle = join
        path.stroke()
    }

    private func fill(_ path: UIBezierPath, color: UIColor) {
        color.setFill()
        path.fill()
    }

    /// The paths as parsed, in the 20×20 frame: for the tests, which keep every
    /// glyph inside its viewBox and count what the d-strings command.
    /// UIBezierPath turns a path with the mutating `apply`; there is no value
    /// returning copy, so the turned glyph is a copy that was applied to.
    private static func turned(_ path: UIBezierPath, by transform: CGAffineTransform) -> UIBezierPath {
        let copy = UIBezierPath(cgPath: path.cgPath)
        copy.apply(transform)
        return copy
    }

    func geometry() -> [UIBezierPath] {
        switch self {
        case .chevronLeft: return [SVGPath.parse("M12.5 4.5L7 10l5.5 5.5")]
        case .chevronRight: return [SVGPath.parse("M7.5 4.5L13 10l-5.5 5.5")]
        case .sidebar: return [UIBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 14, height: 12), cornerRadius: 2.5),
                                SVGPath.parse("M8 4v12")]
        case .search: return [UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 11, height: 11)),
                               SVGPath.parse("M13 13l4 4")]
        case .plus: return [SVGPath.parse("M10 4v12M4 10h12")]
        case .arrowUp: return [SVGPath.parse("M10 16V4M5 9l5-5 5 5")]
        case .arrowDown: return [SVGPath.parse("M10 4v12M5 11l5 5 5-5")]
        case .gear: return [SVGPath.parse("M10 7.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"),
                             SVGPath.parse("M7.85 4.4l.29-1.87a7.7 7.7 0 0 1 3.72 0l.29 1.87a6 6 0 0 1 1.63.94l1.76-.69a7.7 7.7 0 0 1 1.86 3.23l-1.47 1.18a6 6 0 0 1 0 1.88l1.47 1.18a7.7 7.7 0 0 1-1.86 3.23l-1.76-.69a6 6 0 0 1-1.63.94l-.29 1.87a7.7 7.7 0 0 1-3.72 0l-.29-1.87a6 6 0 0 1-1.63-.94l-1.76.69a7.7 7.7 0 0 1-1.86-3.23l1.47-1.18a6 6 0 0 1 0-1.88L2.6 7.88a7.7 7.7 0 0 1 1.86-3.23l1.76.69a6 6 0 0 1 1.63-.94z")]
        case .people: return [UIBezierPath(ovalIn: CGRect(x: 4.5, y: 4, width: 6, height: 6)),
                               SVGPath.parse("M2 16.5c.6-2.8 2.8-4.5 5.5-4.5s4.9 1.7 5.5 4.5"),
                               SVGPath.parse("M13 4.3a3 3 0 0 1 0 5.4M15 12.4c1.6.6 2.6 2 3 4.1")]
        case .unread: return [SVGPath.parse("M10 3.5a4.5 4.5 0 0 0-4.5 4.5v3L4 13.5h12L14.5 11V8"),
                               SVGPath.parse("M8.3 16a1.8 1.8 0 0 0 3.4 0"),
                               SVGPath.parse("M15.5 3.2a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2z")]
        case .pinMark:
            // draw(in:) turns this glyph 45° about the frame's centre, so the
            // geometry carries the same transform: otherwise the tests weigh a
            // straight path against a turned picture and never agree.
            let turn = CGAffineTransform(translationX: 10, y: 10)
                .rotated(by: .pi / 4)
                .translatedBy(x: -10, y: -10)
            return [Icon.turned(SVGPath.parse("M8 2.5h4a.9.9 0 0 1 0 1.8h-.4v4.1c0 1.4 1.1 2.6 2.6 3.1l.7.3v1.5H5.1v-1.5l.7-.3c1.5-.5 2.6-1.7 2.6-3.1V4.3H8a.9.9 0 0 1 0-1.8z"), by: turn),
                    Icon.turned(SVGPath.parse("M9.35 13.3h1.3v3.6L10 18l-.65-1.1z"), by: turn)]
        case .mainStar: return [SVGPath.parse(Icon.star)]
        case .stop: return [UIBezierPath(roundedRect: CGRect(x: 3.5, y: 3.5, width: 13, height: 13), cornerRadius: 3)]
        case .dots: return [SVGPath.parse("M5 10h.01M10 10h.01M15 10h.01")]
        case .check: return [SVGPath.parse("M4.5 10.5l3.5 3.5 7.5-8")]
        case .close: return [SVGPath.parse("M5 5l10 10M15 5L5 15")]
        case .side: return [SVGPath.parse("M17 11.5a6.5 6.5 0 0 1-6.5 6.5H4l2-2.6A6.5 6.5 0 1 1 17 11.5Z"),
                             SVGPath.parse("M8.8 8.8 11.2 11.2M11.2 8.8 8.8 11.2")]
        }
    }
}

extension UIBarButtonItem {
    /// A 44pt round icon button for a bar, the size ShellB gives its header
    /// controls; the label rides the button for accessibility.
    convenience init(icon: Icon, label: String, color: UIColor, target: Any?, action: Selector) {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.accessibilityLabel = label
        button.addTarget(target, action: action, for: .touchUpInside)
        let glyph = IconView(icon: icon, size: Glass.iconXL, color: color)
        glyph.frame.origin = CGPoint(x: 9, y: 9)
        button.addSubview(glyph)
        self.init(customView: button)
    }
}

/// One icon as a view: the size is the render size, the colour is whatever the
/// caller's palette says, and both can change on trait changes like any label.
final class IconView: UIView {
    var icon: Icon { didSet { setNeedsDisplay() } }
    var color: UIColor { didSet { setNeedsDisplay() } }
    /// mainStar only: the larger star painted under the fill.
    var ring: UIColor? { didSet { setNeedsDisplay() } }

    init(icon: Icon, size: CGFloat, color: UIColor = .label, ring: UIColor? = nil) {
        self.icon = icon
        self.color = color
        self.ring = ring
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        icon.draw(in: bounds, color: color, ring: ring)
    }
}


import UIKit

/// marks.tsx's Mark, painted by hand: the characterMarkup SvgXml renders on the
/// phone, walked here as paths. The body and its decals are characters.js path
/// data; the eyes are the markup's own mask, so they are cut out of everything
/// the body and the decals lay down rather than painted over them.
@MainActor
enum CharacterPaint {
    /// One `<path d="..." fill="..." fill-opacity="..."/>` of a shape's layers.
    struct Decal {
        let path: UIBezierPath
        let fill: String
        let alpha: CGFloat
    }

    /// A shape parsed once: the silhouette, its decals, and the eyes left open.
    struct Art {
        let body: UIBezierPath
        let decals: [Decal]
        let eyes: [UIBezierPath]
    }

    struct Stop: Equatable {
        let offset: CGFloat
        let color: UIColor
    }

    enum Paint: Equatable {
        case solid(UIColor)
        case gradient([Stop])
    }

    /// characters.js paints a gradient from the mark's top left to its bottom right,
    /// in the 100-unit box, whatever the seat is scaled to.
    static let gradientStart = CGPoint(x: 18, y: 10)
    static let gradientEnd = CGPoint(x: 78, y: 92)
    static let box: CGFloat = 100

    private static var arts: [String: Art] = [:]
    private static let photos = NSCache<NSString, UIImage>()
    /// The wire form of the ruler: three quoted fields, one path each.
    private static let decalPattern = try? NSRegularExpression(
        pattern: #"<path d="([^"]*)" fill="([^"]*)" fill-opacity="([^"]*)"/>"#)

    /// The shape's three parts, parsed on first use: the strings are constants.
    static func art(for shape: String) -> Art {
        let id = CharacterMarks.shapeId(shape)
        if let cached = arts[id] { return cached }
        let def = CharacterMarks.shapeOf(id)
        let body = SVGPath.parse(def.path ?? "")
        body.usesEvenOddFillRule = true
        var decals: [Decal] = []
        if let pattern = decalPattern {
            let matches = pattern.matches(in: def.layers, range: NSRange(def.layers.startIndex..., in: def.layers))
            for match in matches {
                guard let d = substring(def.layers, match.range(at: 1)),
                      let fill = substring(def.layers, match.range(at: 2)),
                      let opacity = substring(def.layers, match.range(at: 3)),
                      let alpha = Double(opacity) else { continue }
                let path = SVGPath.parse(d)
                path.usesEvenOddFillRule = true
                decals.append(Decal(path: path, fill: fill, alpha: CGFloat(alpha)))
            }
        }
        let art = Art(body: body, decals: decals, eyes: def.eyes.map(eyePath))
        arts[id] = art
        return art
    }

    private static func substring(_ source: String, _ range: NSRange) -> String? {
        Range(range, in: source).map { String(source[$0]) }
    }

    /// The markup's eye: a capsule of the eye's width, turned and placed as its
    /// `translate(cx cy) rotate(tilt)` says.
    private static func eyePath(_ eye: CharacterMarks.Eye) -> UIBezierPath {
        let rect = CGRect(x: -eye.width / 2, y: -eye.height / 2, width: eye.width, height: eye.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: eye.width / 2)
        path.apply(CGAffineTransform(translationX: eye.cx, y: eye.cy).rotated(by: eye.tilt * .pi / 180))
        return path
    }

    /// inkFill, resolved for one mode: a gradient where characters.js has stops, a
    /// hex as it stands, a known ink by its light or dark value, and gray otherwise.
    static func paint(for color: String, dark: Bool) -> Paint {
        if let stops = CharacterMarks.gradients[color] {
            return .gradient(stops.map {
                Stop(offset: $0.offset, color: hexColor($0.color) ?? .clear)
            })
        }
        if CharacterMarks.isHex(color) {
            return .solid(hexColor(color) ?? .clear)
        }
        let pair = CharacterMarks.inks[CharacterMarks.inkName(color)] ?? ["#8A8F98", "#6E737B"]
        return .solid(hexColor(pair[dark ? 1 : 0]) ?? .clear)
    }

    /// #rrggbb and the #rgb form the decal colours use, always opaque.
    static func hexColor(_ hex: String) -> UIColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let expanded: String
        switch digits.count {
        case 3: expanded = digits.map { "\($0)\($0)" }.joined()
        case 6: expanded = digits
        default: return nil
        }
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    /// marks.tsx:43-45: a look with a picture is the picture, cropped to its circle.
    static func photo(for image: String?) -> UIImage? {
        guard let image, image.hasPrefix("data:"), let comma = image.firstIndex(of: ",") else { return nil }
        let key = image as NSString
        if let cached = photos.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: String(image[image.index(after: comma)...])),
              let decoded = UIImage(data: data) else { return nil }
        photos.setObject(decoded, forKey: key)
        return decoded
    }

    static func hasPhoto(_ look: CharacterMarks.Look) -> Bool { photo(for: look.image) != nil }

    /// Draws one mark into rect, in the 100-unit box's own coordinates.
    static func draw(_ look: CharacterMarks.Look, in rect: CGRect, dark: Bool) {
        guard rect.width > 0, rect.height > 0, let context = UIGraphicsGetCurrentContext() else { return }
        if let photo = photo(for: look.image) {
            context.saveGState()
            UIBezierPath(ovalIn: rect).addClip()
            photo.draw(in: rect)
            context.restoreGState()
            return
        }
        let art = art(for: look.shape)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / box, y: rect.height / box)
        fill(art.body, paint: paint(for: look.color, dark: dark), in: context)
        for decal in art.decals {
            guard let color = hexColor(decal.fill) else { continue }
            context.setFillColor(color.cgColor)
            context.setAlpha(decal.alpha)
            context.addPath(decal.path.cgPath)
            context.fillPath(using: .evenOdd)
            context.setAlpha(1)
        }
        // The markup draws the eyes with the mask's black, which is not paint but a
        // hole: everything under it — the body and the shade alike — leaves.
        context.setBlendMode(.clear)
        for eye in art.eyes {
            context.addPath(eye.cgPath)
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func fill(_ path: UIBezierPath, paint: Paint, in context: CGContext) {
        switch paint {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.addPath(path.cgPath)
            context.fillPath(using: .evenOdd)
        case .gradient(let stops):
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(colorsSpace: space,
                                            colors: stops.map { $0.color.cgColor } as CFArray,
                                            locations: stops.map(\.offset)) else { return }
            context.saveGState()
            context.addPath(path.cgPath)
            context.clip()
            context.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])
            context.restoreGState()
        }
    }
}

/// marks.tsx:42-51 Mark: the character in a square, or the Bot's own picture cropped
/// to a circle. No plate and no rim — the markup has neither, and an Avatar's ring
/// is only the colour its star badge draws on, not a border.
final class CharacterAvatarView: UIView {
    var look: CharacterMarks.Look {
        didSet {
            guard look != oldValue else { return }
            setNeedsDisplay()
        }
    }

    init(look: CharacterMarks.Look = CharacterMarks.look()) {
        self.look = look
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        CharacterPaint.draw(look, in: bounds, dark: traitCollection.userInterfaceStyle == .dark)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // The ink is baked into the drawing, so a mode change repaints it.
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { setNeedsDisplay() }
    }
}

/// marks.tsx picks a mark by what it has: a Bot's character, or a room's cluster.
/// One view for both keeps every call site from owning that choice.
final class MarkView: UIView {
    private let character = CharacterAvatarView()
    private let cluster = RoomAvatarView(frame: .zero)
    /// The disc an empty room shows, in the ring colour of the place it sits in.
    var plate: UIColor = .clear {
        didSet { cluster.plate = plate }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for view in [character, cluster] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        // Nothing is drawn until a caller says what: an unconfigured mark is empty,
        // not a gumdrop.
        character.isHidden = true
        cluster.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(look: CharacterMarks.Look?, members: [CharacterMarks.Look] = []) {
        let showsCluster = !members.isEmpty
        character.isHidden = showsCluster || look == nil
        cluster.isHidden = !showsCluster
        if showsCluster {
            cluster.configure(members: members)
        } else if let look {
            character.look = look
        }
    }
}

extension CharacterMarks.Look {
    /// lookOf(bot) from the wire: the picture and shape under avatar, the colour at
    /// the top, and the id that derives both when a Bot carries neither.
    init(bot: JSONValue?) {
        self = CharacterMarks.look(shape: bot?["avatar"]?["shape"]?.stringValue,
                                   color: bot?["color"]?.stringValue,
                                   id: bot?["id"]?.stringValue,
                                   image: bot?["avatar"]?["image"]?.stringValue)
    }

    /// marks.tsx:116: a room's roster as marks, in the room's own order, with the
    /// members the team state does not carry left out.
    static func members(of room: JSONValue?, team: JSONValue?) -> [CharacterMarks.Look] {
        guard let ids = room?["members"]?.stringArrayValue,
              case .array(let bots)? = team?["bots"] else { return [] }
        return ids.compactMap { id in
            bots.first { $0["id"]?.stringValue == id }.map { CharacterMarks.Look(bot: $0) }
        }
    }
}
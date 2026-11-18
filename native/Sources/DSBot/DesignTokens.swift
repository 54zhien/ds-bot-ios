import UIKit

// values mirror mobile/src/ui/tokens.ts

private func dsHex(_ hex: String, alpha: CGFloat = 1) -> UIColor {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .clear }
    return UIColor(
        red: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255,
        alpha: alpha)
}

/// A theme's eight colors for one mode.
struct ThemeMode {
    let bg: UIColor
    let sidebar: UIColor
    let bubble: UIColor
    let card: UIColor
    let text: UIColor
    let user: UIColor
    let userText: UIColor
    let accent: UIColor
}

struct ThemePreset {
    let label: String
    let light: ThemeMode
    let dark: ThemeMode
}

enum Themes {
    // Built on demand instead of stored: UIKit colors are not Sendable, so a global
    // table would be a concurrency-check error under Swift 6.
    static func preset(_ id: String? = nil) -> ThemePreset {
        switch id ?? "deepseek" {
        case "mono":
            return ThemePreset(
                label: "Mono",
                light: ThemeMode(bg: dsHex("#ffffff"), sidebar: dsHex("#f9f9f9"), bubble: dsHex("#f0f0f0"), card: dsHex("#ffffff"), text: dsHex("#0d0d0d"), user: dsHex("#0d0d0d"), userText: dsHex("#ffffff"), accent: dsHex("#0d0d0d")),
                dark: ThemeMode(bg: dsHex("#0f0f0f"), sidebar: dsHex("#171717"), bubble: dsHex("#242424"), card: dsHex("#1c1c1c"), text: dsHex("#f4f4f4"), user: dsHex("#f4f4f4"), userText: dsHex("#0f0f0f"), accent: dsHex("#f4f4f4")))
        case "paper":
            return ThemePreset(
                label: "Paper",
                light: ThemeMode(bg: dsHex("#faf9f5"), sidebar: dsHex("#f3f0e8"), bubble: dsHex("#ebe7dc"), card: dsHex("#ffffff"), text: dsHex("#1f1e1b"), user: dsHex("#2b2a26"), userText: dsHex("#faf9f5"), accent: dsHex("#d97757")),
                dark: ThemeMode(bg: dsHex("#1f1e1b"), sidebar: dsHex("#262521"), bubble: dsHex("#34322d"), card: dsHex("#2a2925"), text: dsHex("#f3f0e8"), user: dsHex("#f3f0e8"), userText: dsHex("#1f1e1b"), accent: dsHex("#e08a6d")))
        case "moonlight":
            return ThemePreset(
                label: "Moonlight",
                light: ThemeMode(bg: dsHex("#f7f9fc"), sidebar: dsHex("#eef2f8"), bubble: dsHex("#e5ebf5"), card: dsHex("#ffffff"), text: dsHex("#121826"), user: dsHex("#1e3a8a"), userText: dsHex("#ffffff"), accent: dsHex("#1e86ff")),
                dark: ThemeMode(bg: dsHex("#0b1020"), sidebar: dsHex("#10172a"), bubble: dsHex("#1a2340"), card: dsHex("#141c33"), text: dsHex("#e8edf7"), user: dsHex("#3b6fd8"), userText: dsHex("#ffffff"), accent: dsHex("#4f9dff")))
        default:
            return ThemePreset(
                label: "DeepSeek",
                light: ThemeMode(bg: dsHex("#fcfcfc"), sidebar: dsHex("#f7f7f7"), bubble: dsHex("#eeeeee"), card: dsHex("#ffffff"), text: dsHex("#141414"), user: dsHex("#070707"), userText: dsHex("#fcfcfc"), accent: dsHex("#4d6bfe")),
                dark: ThemeMode(bg: dsHex("#141414"), sidebar: dsHex("#1b1b1b"), bubble: dsHex("#262626"), card: dsHex("#1f1f1f"), text: dsHex("#f2f2f2"), user: dsHex("#f2f2f2"), userText: dsHex("#141414"), accent: dsHex("#5b7bff")))
        }
    }

    static func label(_ id: String?) -> String { preset(id).label }
}

enum Inks {
    // Character inks as hex pairs, so the table stays Sendable; colors are made per use.
    private static let table: [String: (light: String, dark: String)] = [
        "deepseek": ("#4D6BFE", "#6A84FF"), "charcoal": ("#141416", "#F1F2F4"),
        "graphite": ("#2D2D2D", "#D6D6DA"), "rose": ("#EC2F6B", "#FF5A7A"),
        "sky": ("#0AA8D6", "#2EE6E0"), "tangerine": ("#FF6900", "#FF8A2E"),
        "cobalt": ("#082DFF", "#5C78FF"), "black": ("#000000", "#FFFFFF"),
        "brown": ("#9A6B44", "#7C5332"), "red": ("#FF3E51", "#E02135"),
        "orange": ("#FF6B1A", "#FF5E00"), "yellow": ("#FFB020", "#F59E0B"),
        "green": ("#10B981", "#059669"), "cyan": ("#06B6D4", "#0891B2"),
        "blue": ("#2563EB", "#3B82F6"), "violet": ("#8B5CF6", "#7C3AED"),
        "magenta": ("#F43F85", "#E11D74"), "gray": ("#8A8F98", "#6E737B"),
        "aurora": ("#00B8D4", "#2EE6E0"),
    ]
    // An accent saved by a preset takes the preset's dark value, like names do.
    static let accentInkIds = ["deepseek", "charcoal", "graphite", "rose", "sky", "tangerine", "cobalt"]

    static func hex(_ id: String, dark: Bool) -> String? {
        guard let pair = table[id] else { return nil }
        return dark ? pair.dark : pair.light
    }

    static func named(_ id: String, dark: Bool) -> UIColor {
        dsHex(hex(id, dark: dark) ?? table["gray"]!.dark)
    }

    /// A Bot's color: a named ink, a #rrggbb value, or gray.
    static func bot(_ color: String?, dark: Bool) -> UIColor {
        guard let color else { return dsHex(table["gray"]!.dark) }
        if let named = hex(color, dark: dark) { return dsHex(named) }
        return color.hasPrefix("#") ? dsHex(color) : dsHex(table["gray"]!.dark)
    }

    static func accent(_ accent: String, dark: Bool) -> UIColor {
        guard dark, let pair = table.first(where: { $0.value.light.caseInsensitiveCompare(accent) == .orderedSame }),
              accentInkIds.contains(pair.key) else { return dsHex(accent) }
        return dsHex(pair.value.dark)
    }

    /// WCAG relative luminance of a #rrggbb value.
    static func luminance(_ hex: String) -> CGFloat {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt32(digits, radix: 16) else { return 0 }
        let weights: [CGFloat] = [0.2126, 0.7152, 0.0722]
        var total: CGFloat = 0
        for (index, shift) in [16, 8, 0].enumerated() {
            let channel = CGFloat((value >> UInt32(shift)) & 0xff) / 255
            total += (channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)) * weights[index]
        }
        return total
    }

    static func rgba(_ hex: String, _ alpha: CGFloat) -> UIColor { dsHex(hex, alpha: alpha) }

    /// Stands in for CSS color-mix.
    static func mix(_ a: String, _ b: String, _ weightOfA: CGFloat) -> UIColor {
        let digits = { (hex: String) in Array(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex) }
        let left = digits(a), right = digits(b)
        guard left.count == 6, right.count == 6, let one = UInt32(String(left), radix: 16), let two = UInt32(String(right), radix: 16) else { return dsHex(a) }
        var value: UInt32 = 0
        for shift in [16, 8, 0] {
            let a = CGFloat((one >> UInt32(shift)) & 0xff)
            let b = CGFloat((two >> UInt32(shift)) & 0xff)
            value |= UInt32((a * weightOfA + b * (1 - weightOfA)).rounded()) << UInt32(shift)
        }
        return dsHex(String(format: "#%06x", value))
    }

    /// Text on an accent: near-black or white, whichever reads better.
    static func onAccent(_ accent: String) -> UIColor {
        let dark = luminance("#141414") + 0.05
        return pow(luminance(accent) + 0.05, 2) > 1.05 * dark ? dsHex("#141414") : .white
    }
}

/// The resolved surface colors a screen draws with.
struct Palette {
    let ink: UIColor
    let ink2: UIColor
    let ink3: UIColor
    let bubble: UIColor
    let sidebar: UIColor
    let main: UIColor
    let card: UIColor
    let line: UIColor
    let line2: UIColor
    let lineWeak: UIColor
    let hover: UIColor
    let active: UIColor
    let accent: UIColor
    let accentInk: UIColor
    let user: UIColor
    let userInk: UIColor
    let tagBg: UIColor
    let tagInk: UIColor
    let knob: UIColor
    let danger: UIColor
    let green: UIColor
    let star: UIColor

    static func make(dark: Bool, themeId: String? = nil, accent: String? = nil) -> Palette {
        let preset = Themes.preset(themeId)
        let mode = dark ? preset.dark : preset.light
        let text = mode.text
        let use = accent.map { Inks.accent($0, dark: dark) } ?? mode.accent
        return Palette(
            ink: text,
            ink2: text.withAlphaComponent(0.6),
            ink3: text.withAlphaComponent(0.36),
            bubble: mode.bubble,
            sidebar: mode.sidebar,
            main: mode.bg,
            card: mode.card,
            line: text.withAlphaComponent(0.08),
            line2: text.withAlphaComponent(0.15),
            lineWeak: text.withAlphaComponent(0.1),
            hover: dark ? dsHex("#a0a0a0", alpha: 0.12) : dsHex("#777777", alpha: 0.09),
            active: dark ? dsHex("#a0a0a0", alpha: 0.2) : dsHex("#777777", alpha: 0.17),
            accent: use,
            accentInk: Inks.onAccent(rgbHex(use)),
            user: mode.user,
            userInk: mode.userText,
            tagBg: text.withAlphaComponent(dark ? 0.09 : 0.06),
            tagInk: text.withAlphaComponent(0.58),
            knob: .white,
            danger: dsHex("#e02135"),
            green: dsHex("#00c972"),
            star: dsHex("#ff9800"))
    }

    /// The same color as #rrggbb, for the helpers that work on hex strings.
    private static func rgbHex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02x%02x%02x",
                      Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

/// Phone type scale: settled sizes for touch, weights only 400/500/600.
struct Typography {
    let size: CGFloat
    let lineHeight: CGFloat
    let weight: UIFont.Weight

    var font: UIFont { .systemFont(ofSize: size, weight: weight) }
    var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraph]
    }
    var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }
}

enum TypeScale {
    static let rowName = Typography(size: 16, lineHeight: 22, weight: .regular)
    static let rowPreview = Typography(size: 14, lineHeight: 20, weight: .regular)
    static let bubble = Typography(size: 16, lineHeight: 24, weight: .regular)
    static let headerTitle = Typography(size: 17, lineHeight: 24, weight: .semibold)
    static let largeTitle = Typography(size: 28, lineHeight: 34, weight: .semibold)
    static let settingsRow = Typography(size: 16, lineHeight: 22, weight: .regular)
    static let small = Typography(size: 13, lineHeight: 18, weight: .regular)
    static let caption = Typography(size: 12, lineHeight: 16, weight: .regular)
    static func mono(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

enum Radius {
    static let tag: CGFloat = 4
    static let item: CGFloat = 6
    static let input: CGFloat = 8
    static let row: CGFloat = 10
    static let card: CGFloat = 12
    static let option: CGFloat = 12
    static let dialog: CGFloat = 16
    static let bubble: CGFloat = 18
    static let composer: CGFloat = 22
    static let composerLong: CGFloat = 18
    static let pill: CGFloat = 999
}

struct Shadow {
    let color: UIColor
    let offset: CGSize
    let radius: CGFloat
    let opacity: Float

    // Computed, not stored: a shared UIColor-backed constant trips Swift 6 concurrency.
    static var none: Shadow { Shadow(color: .clear, offset: .zero, radius: 0, opacity: 0) }
    static var level1: Shadow { Shadow(color: .black, offset: CGSize(width: 0, height: 2), radius: 8, opacity: 0.06) }
    static var level2: Shadow { Shadow(color: .black, offset: CGSize(width: 0, height: 10), radius: 20, opacity: 0.1) }
    static var level3: Shadow { Shadow(color: .black, offset: CGSize(width: 0, height: 8), radius: 28, opacity: 0.14) }
    static var level4: Shadow { Shadow(color: .black, offset: CGSize(width: 0, height: 24), radius: 80, opacity: 0.24) }

    func apply(to layer: CALayer) {
        layer.shadowColor = color.cgColor
        layer.shadowOffset = offset
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
    }
}

/// Liquid Glass metrics: every glass surface takes its sizes from here.
enum Glass {
    static let control: CGFloat = 44
    static let controlSmall: CGFloat = 40
    static let icon: CGFloat = 22
    static let iconLarge: CGFloat = 24
    static let iconXL: CGFloat = 26
    static let pill: CGFloat = 44
    static let gap: CGFloat = 8
    static let margin: CGFloat = 16
}

/// One place that turns the team's saved theme into a palette, so every screen
/// agrees on the colours the user picked on the computer.
@MainActor enum ThemeStore {
    static let changed = Notification.Name("DSBotThemeChanged")
    private static var themeId: String?
    private static var accentHex: String?

    /// prefs.theme is a preset id, or system/absent to follow the appearance.
    static func update(from state: JSONValue) {
        let nextTheme = state["prefs"]?["theme"]?.stringValue
        let nextAccent = state["prefs"]?["accent"]?.stringValue
        guard nextTheme != themeId || nextAccent != accentHex else { return }
        themeId = nextTheme == "system" ? nil : nextTheme
        accentHex = nextAccent
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func palette(trait: UITraitCollection) -> Palette {
        palette(dark: trait.userInterfaceStyle == .dark)
    }

    static func palette(dark: Bool) -> Palette {
        Palette.make(dark: dark, themeId: themeId, accent: accentHex)
    }
}

enum Metrics {
    /// The floating chat header is the status bar plus the 44pt bar plus 8 below it.
    static func headerHeight(insetTop: CGFloat) -> CGFloat { insetTop + Glass.control + 8 }

    /// Detail pages: one floating bar plus the fade above the content.
    static let pageBar: CGFloat = 60
    static let pageBarTight: CGFloat = 56
    static func pageHeaderHeight(insetTop: CGFloat, tight: Bool = false) -> CGFloat {
        insetTop + (tight ? pageBarTight : pageBar)
    }

    /// A sheet header: the grabber's 14pt lead plus the 52pt row.
    static let sheetHead: CGFloat = 66


    /// The drawer footer fade: the 44pt control, its 16pt lead and 36pt of run-out.
    static let gearFade: CGFloat = Glass.control + 16 + 36

    /// A resting composer is inset and lifted by R - h/2, so its end circles share the
    /// display corner's centre. Clamped: never sneak toward the middle, never hug the edge.
    static func concentricInset(screenR: CGFloat, height: CGFloat) -> CGFloat {
        screenR == 0 ? 16 : min(32, max(12, screenR - height / 2))
    }

    /// Approximate display corner radius: iOS devices with a home indicator round the
    /// display at about 55pt, SE-class screens are square. Swap in a real value once the
    /// platform exposes one.
    // The bounds are passed in: UIScreen.main is main-actor isolated, and these metrics
    // are read from layout code that is not.
    static func screenRadius(bottomInset: CGFloat, bounds: CGRect) -> CGFloat {
        if min(bounds.width, bounds.height) >= 600 { return 18 }
        return bottomInset >= 20 ? 55 : 0
    }

    enum Composer {
        /// max(50, 22 + 20) + 12: the resting capsule, so anything lining up with it can
        /// ask for the same number instead of keeping its own copy.
        static let resting: CGFloat = max(50, 22 + 20) + 12

        /// Left inset of the composer: the standard margin while editing, the concentric
        /// one at rest.
        static func inset(screenR: CGFloat, screenWidth: CGFloat, expanded: Bool) -> CGFloat {
            if expanded { return Glass.margin }
            let tight = Metrics.concentricInset(screenR: screenR, height: resting)
            return screenWidth - 2 * tight - 88 >= 120 ? tight : Glass.margin
        }
    }
}

/// The 9.1 springs as UIKit parameters: omega = sqrt(k/m), zeta = c / (2 sqrt(k m)).
struct Spring {
    let stiffness: CGFloat
    let damping: CGFloat
    let mass: CGFloat

    init(_ w: CGFloat, _ z: CGFloat) {
        mass = 1
        stiffness = w * w
        damping = 2 * z * w
    }

    var omega: CGFloat { sqrt(stiffness / mass) }
    var dampingRatio: CGFloat { damping / (2 * sqrt(stiffness * mass)) }
    /// Time for the envelope to fall to 1/1000 of its start.
    var settling: TimeInterval { TimeInterval(3.5 / (dampingRatio * omega)) }

    func timing() -> UISpringTimingParameters {
        UISpringTimingParameters(dampingRatio: dampingRatio)
    }
}

enum Springs {
    static let shape = Spring(20, 0.78)
    static let tap = Spring(30, 0.8)
    static let list = Spring(22, 0.8)
    static let stretch = Spring(18, 0.56)
    static let pop = Spring(22, 0.49)
}

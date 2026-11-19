import UIKit

/// Resolves a zen typography role into the numbers the ported geometry consumes.
///
/// resolver authored here; every size/lineHeight/weight below is copied from
/// Zen-Agent App/Typography/Typography.swift:64-65 (pointSize 17, textStyle .body,
/// weight nil) and :85-94 (the `default:` branch: tracking 0, lineSpacing 0).
///
/// zen resolves the same role through a bundled variable font
/// (`AnthropicSansWebVariable-TextRegular`, face chosen at :27-36, `wght` axis at :52-54)
/// and scales it with `UIFontMetrics` at :107-108. That font is not shipped here, so the
/// family falls to the system font and the weight to its default; the size still scales
/// through `UIFontMetrics`, so Dynamic Type behaves as it does in zen.
enum ZenTypeMetrics {
    struct Metrics {
        let font: UIFont
        let lineHeight: CGFloat
        let tracking: CGFloat
    }

    static func metrics(for role: ZenTypographyRole,
                        compatibleWith traits: UITraitCollection? = nil) -> Metrics {
        // Only .interfaceBody has numbers with a source: the geometry passes nothing else,
        // and 17 / .body / 0 / 0 above are its values. A new role needs its size, line
        // height and weight checked against Typography.swift before it is used here.
        _ = role
        let base = UIFont.systemFont(ofSize: 17)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
        return Metrics(font: font, lineHeight: font.lineHeight, tracking: 0)
    }
}

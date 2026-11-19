import UIKit

/// Resolves a zen typography role into the numbers the ported geometry consumes.
///
/// resolver authored here; the numbers themselves come from `ZenTypography`, which is zen's
/// `App/Typography/Typography.swift` renamed and moved verbatim: sizes at :68-86, tracking and
/// line spacing at :93-97, Dynamic Type scaling at :111-113 through `UIFontMetrics`. There is one
/// set of values in this tree, and this file reads it rather than repeating it.
///
/// zen resolves the same role through a bundled variable font
/// (`AnthropicSansWebVariable-TextRegular`, face chosen at :27-36, `wght` axis at :52-54). That
/// font is not shipped here, so the family falls to the system font and the weight to its
/// default; the size still scales through `UIFontMetrics`, so Dynamic Type behaves as in zen.
enum ZenTypeMetrics {
    struct Metrics {
        let font: UIFont
        let lineHeight: CGFloat
        let tracking: CGFloat
    }

    static func metrics(for role: ZenTypographyRole,
                        compatibleWith traits: UITraitCollection? = nil) -> Metrics {
        let font = ZenTypography.uiFont(for: role, compatibleWith: traits)
        let spacing = ZenTypography.readingSpacing(for: role)
        return Metrics(font: font,
                       lineHeight: font.lineHeight + spacing.lineSpacing,
                       tracking: spacing.tracking)
    }
}

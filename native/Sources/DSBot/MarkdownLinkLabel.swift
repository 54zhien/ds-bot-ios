import UIKit

final class MarkdownLinkLabel: UILabel {
    private var linkTap: UITapGestureRecognizer?

    override var attributedText: NSAttributedString? { didSet { updateLinkTap() } }
    override var text: String? { didSet { updateLinkTap() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(openLink(_:)))
        tap.isEnabled = false
        linkTap = tap
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func canOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private func updateLinkTap() {
        guard let text = attributedText, text.length > 0 else { linkTap?.isEnabled = false; return }
        var found = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        linkTap?.isEnabled = found
    }

    @objc private func openLink(_ gesture: UITapGestureRecognizer) {
        guard let text = attributedText, text.length > 0 else { return }
        let styled = NSMutableAttributedString(attributedString: text)
        var missingFonts: [NSRange] = []
        styled.enumerateAttribute(.font, in: NSRange(location: 0, length: styled.length), options: []) { value, range, _ in
            if value == nil { missingFonts.append(range) }
        }
        for range in missingFonts { styled.addAttribute(.font, value: font as Any, range: range) }
        let storage = NSTextStorage(attributedString: styled)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: bounds.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = numberOfLines
        container.lineBreakMode = lineBreakMode
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let used = manager.usedRect(for: container)
        let horizontal: CGFloat
        switch textAlignment {
        case .center: horizontal = (bounds.width - used.width) / 2
        case .right: horizontal = bounds.width - used.width
        default: horizontal = 0
        }
        let point = gesture.location(in: self)
        let local = CGPoint(x: point.x - horizontal, y: point.y - (bounds.height - used.height) / 2)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                .contains(local) else { return }
        let index = manager.characterIndexForGlyph(at: glyph)
        guard index < text.length else { return }
        let attribute = text.attribute(.link, at: index, effectiveRange: nil)
        let url = attribute as? URL ?? (attribute as? String).flatMap(URL.init(string:))
        guard let url, Self.canOpen(url) else { return }
        UIApplication.shared.open(url)
    }
}

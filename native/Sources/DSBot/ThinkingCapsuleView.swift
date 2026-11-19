import UIKit

/// phrases.ts:5-23, workPhrase: what a Bot is doing, in the words the desktop uses.
/// The tool families are tested in the order the file lists them, because a name like
/// web_search answers to two of them and only the first one is what it means.
enum WorkPhrase {
    private static let families: [(pattern: String, key: String)] = [
        ("web_?search|search_?web", "Searching online"),
        ("fetch|browse|browser|web", "Reading a page"),
        ("shell|bash|pwsh|powershell|exec|command|terminal", "Running shell commands"),
        ("^(read|view|cat)\\b|read_", "Opening a file"),
        ("write|edit|patch|create_file", "Writing a file"),
        ("recall|memory|remember", "Checking memory"),
    ]

    /// Every key this table can hand to NativeLanguage. The guard test scans the
    /// sources for literals, and these arrive through a variable, so it reads them here.
    static var keys: [String] {
        families.map { $0.key } + ["Thinking about it", "On it",
                               "Switching working folder", "Moving to a fresh conversation"]
    }

    /// Its own words, else the tool family and its target, else the fallback. The
    /// sentence's tail is trimmed so the caller's ellipsis is the only one on the line.
    static func text(_ doing: JSONValue) -> String {
        if doing["switching"] == .bool(true) {
            return NativeLanguage.text(doing["folder"] == .bool(true)
                ? "Switching working folder" : "Moving to a fresh conversation")
        }
        let own = (doing["said"]?.stringValue ?? doing["note"]?.stringValue ?? "")
            .replacingOccurrences(of: "[\\s.。…]+$", with: "", options: .regularExpression)
        if !own.isEmpty { return own }
        let tool = (doing.stringValue ?? doing["tool"]?.stringValue ?? "").lowercased()
        if tool.isEmpty { return NativeLanguage.text("Thinking about it") }
        let family = families.first {
            tool.range(of: $0.pattern, options: .regularExpression) != nil
        }?.key
        let label = NativeLanguage.text(family ?? "On it")
        let target = doing["target"]?.stringValue ?? ""
        return target.isEmpty ? label : "\(label) · \(target)"
    }
}

/// What the capsule shows: the line, and the mark to put beside it. Built from the
/// same team state the older status row reads, so swapping the row for the capsule
/// changes the picture and nothing else.
struct ThinkingCapsulePresentation: Equatable {
    let text: String
    let look: CharacterMarks.Look?

    init(text: String, look: CharacterMarks.Look?) {
        self.text = text
        self.look = look
    }

    /// Chat.tsx:256: a session reads its own work entry, a room reads the first one in
    /// its list and names the Bot that is doing it. No entry means the Bot is idle.
    init?(target: ChatTarget, state: JSONValue) {
        let doing: JSONValue
        let name: String
        switch target.kind {
        case .bot:
            guard let value = state["work"]?["bots"]?[target.id] ?? state["activity"]?[target.id],
                  value != .null else { return nil }
            doing = value
            name = ""
        case .room:
            guard case .array(let work)? = state["work"]?["rooms"]?[target.id],
                  let first = work.first else { return nil }
            doing = first
            let botID = first["botId"]?.stringValue ?? ""
            name = (ThinkingCapsulePresentation.name(of: botID, in: state) ?? "") + " · "
        }
        text = name + WorkPhrase.text(doing) + "…"
        switch target.kind {
        case .bot:
            look = ThinkingCapsulePresentation.look(of: target.id, in: state)
        case .room:
            let botID = doing["botId"]?.stringValue ?? ""
            look = ThinkingCapsulePresentation.look(of: botID, in: state)
        }
    }

    private static func name(of id: String, in state: JSONValue) -> String? {
        bot(id, in: state)?["name"]?.stringValue
    }

    private static func look(of id: String, in state: JSONValue) -> CharacterMarks.Look? {
        guard let bot = bot(id, in: state) else { return nil }
        return CharacterMarks.Look(bot: bot)
    }

    private static func bot(_ id: String, in state: JSONValue) -> JSONValue? {
        guard !id.isEmpty, case .array(let bots)? = state["bots"] else { return nil }
        return bots.first { $0["id"]?.stringValue == id }
    }
}

/// A Bot that is working says what it is doing in a capsule above the composer.
/// RN draws the same pair without a container — dock.tsx:306-320, a 36pt row with a
/// 28pt mark — so the line and the mark come from there, and the pill, its glass and
/// its shadow are the phone design's own.
final class ThinkingCapsuleView: UIView {
    /// The ceiling the capsule may not pass: a status line, not a card.
    static let height: CGFloat = 32
    private static let markSize: CGFloat = 20
    private static let lead: CGFloat = 6
    private static let trail: CGFloat = 12
    private static let gap: CGFloat = 8
    // zen-Agent/App/Conversation/ComposerKeyboardMenuPresenter.swift:161 (reveal,
    // 0.28s easeOut) and :204 (dismiss, 0.23s easeIn). The rise is 4pt because the
    // pill is 32 tall; zen's 14 is a whole menu sheet's travel.
    private static let rise: CGFloat = 4
    private static let fadeIn: TimeInterval = 0.28
    private static let fadeOut: TimeInterval = 0.23
    private static let fontSize: CGFloat = 14
    private static let fontSizeCeiling: CGFloat = 16

    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let mark = CharacterAvatarView(look: CharacterMarks.look())
    private let label = UILabel()
    private var markWidth: NSLayoutConstraint?
    private var markGap: NSLayoutConstraint?
    private var widthLimit: NSLayoutConstraint?
    private var measuredWidth: NSLayoutConstraint?
    private var animator: UIViewPropertyAnimator?

    /// Fired once the capsule has shown or hidden itself, so a layout that reserves
    /// its room can move with the fade instead of guessing when it ends.
    var onVisibilityChange: (() -> Void)?

    /// The widest the capsule may get; the wiring points it at the composer. The pill
    /// states its own width, so a caller caps it here rather than pinning both edges.
    var maximumWidth: CGFloat? {
        didSet {
            widthLimit?.isActive = false
            widthLimit = nil
            if let maximumWidth {
                let limit = widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth)
                limit.isActive = true
                widthLimit = limit
            }
            // Clearing the cap has to lift the width it set, not leave it behind.
            updateMeasuredWidth()
        }
    }

    /// The line's own width, so a test can tell a pill with no width from a cut line.
    var textWidth: CGFloat { label.intrinsicContentSize.width }

    /// Whether the line is drawn whole: the frame against the line, never against the
    /// cap. A pill with no width of its own reads the same as a cut line, so the tests
    /// that read this one state the frame it was measured in.
    var textFits: Bool { label.bounds.width + 0.5 >= label.intrinsicContentSize.width }

    /// Whether the mark is on screen, again for the tests that check the two shapes.
    var showsMark: Bool { !mark.isHidden }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        // A status line, not a control: the tap under it belongs to the messages.
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        isHidden = true
        layer.cornerRadius = Self.height / 2
        surface.isUserInteractionEnabled = false
        surface.layer.cornerRadius = Self.height / 2
        surface.layer.masksToBounds = true
        addSubview(surface)

        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        // Compression stays at the default: the label resisting it is the only thing that
        // asks the pill for a width. Lowered, the label still lays out but the pill has
        // nothing to size from and comes out zero wide.
        addSubview(mark)
        addSubview(label)

        // No stack view between them: a stack reports no size its superview can take a
        // width from, and this pill has no width constraint above it. Pinned straight
        // through, the label's own line is the width. A mark that is not shown gives its
        // room back through the constants rather than leaving a 20pt hole.
        let markWidth = mark.widthAnchor.constraint(equalToConstant: 0)
        let markGap = label.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 0)
        self.markWidth = markWidth
        self.markGap = markGap
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            mark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.lead),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.heightAnchor.constraint(equalToConstant: Self.markSize),
            markWidth,
            markGap,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trail),
        ])
        applyPalette()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A line to show, or nil when the Bot has gone idle. Nothing shows without both
    /// a line and a Bot, so an empty string hides the capsule like a nil does.
    func configure(_ presentation: ThinkingCapsulePresentation?) {
        guard let presentation, !presentation.text.isEmpty else { hide(); return }
        label.text = presentation.text
        accessibilityLabel = presentation.text
        applyMarkRoom(shown: presentation.look != nil)
        if let look = presentation.look { mark.look = look }
        // The line decides the width, so it is measured once the text is in place.
        updateMeasuredWidth()
        show()
    }

    /// A hidden view keeps its constraints, so the mark's room is carried by the two
    /// constants instead of by visibility: no mark, no 28pt of empty leading edge.
    private func applyMarkRoom(shown: Bool) {
        mark.isHidden = !shown
        markWidth?.constant = shown ? Self.markSize : 0
        markGap?.constant = shown ? Self.gap : 0
        updateMeasuredWidth()
    }

    /// Nothing above the pill constrains its width, and a stack view cannot report one,
    /// so the pill states its own: the line plus the furniture, capped by maximumWidth.
    /// Inferred layout left it free to collapse to zero, which looks exactly like a
    /// truncated line and hid the difference from every test that only checked a cap.
    private func updateMeasuredWidth() {
        let room = Self.lead + (mark.isHidden ? 0 : Self.markSize + Self.gap) + Self.trail
        let wanted = label.intrinsicContentSize.width + room
        let capped = maximumWidth.map { min(wanted, $0) } ?? wanted
        measuredWidth?.isActive = false
        let width = widthAnchor.constraint(equalToConstant: max(capped, room))
        width.isActive = true
        measuredWidth = width
    }

    // MARK: - Moving in and out

    /// A view that is not on screen yet has nothing to animate, and the tests read the
    /// settled state; Reduce Motion asks for the same thing.
    private var animates: Bool { window != nil && !UIAccessibility.isReduceMotionEnabled }

    private func show() {
        guard isHidden else { return }
        isHidden = false
        guard animates else {
            alpha = 1
            transform = .identity
            onVisibilityChange?()
            return
        }
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: Self.rise)
        let animation = UIViewPropertyAnimator(duration: Self.fadeIn, curve: .easeOut) {
            self.alpha = 1
            self.transform = .identity
        }
        animator = animation
        animation.addCompletion { [weak self] _ in
            self?.animator = nil
            self?.onVisibilityChange?()
        }
        animation.startAnimation()
    }

    private func hide() {
        guard !isHidden else { return }
        guard animates else {
            isHidden = true
            alpha = 1
            transform = .identity
            onVisibilityChange?()
            return
        }
        let animation = UIViewPropertyAnimator(duration: Self.fadeOut, curve: .easeIn) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: Self.rise)
        }
        animator = animation
        animation.addCompletion { [weak self] _ in
            guard let self else { return }
            self.animator = nil
            self.isHidden = true
            self.alpha = 1
            self.transform = .identity
            self.onVisibilityChange?()
        }
        animation.startAnimation()
    }

    // MARK: - Paint

    // The rim and the shadow are CGColor snapshots, so both are set here and re-set on
    // a trait or theme change; the label takes its colour from the same palette.
    private func applyPalette() {
        let palette = ThemeStore.palette(trait: traitCollection)
        label.textColor = palette.ink2
        applyFont()
        // zen-Agent/App/Conversation/ComposerHostView.swift:209 spells the style out.
        // The fallback takes the composer's own materials (NativeComposerView.swift:170)
        // rather than zen's .regularMaterial, because the two surfaces sit edge to edge.
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect(style: .regular)
            surface.layer.borderWidth = 0
        } else {
            let dark = traitCollection.userInterfaceStyle == .dark
            surface.effect = UIBlurEffect(style: dark ? .systemThickMaterial : .systemUltraThinMaterial)
            surface.layer.borderWidth = 1
            surface.layer.borderColor = palette.line.cgColor
        }
        Shadow.level1.apply(to: layer)
    }

    // Scaled by hand rather than with adjustsFontForContentSizeCategory: the font needs a
    // ceiling to stay inside 32pt, and that switch cannot carry one.
    private func applyFont() {
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: Self.fontSize), maximumPointSize: Self.fontSizeCeiling)
        updateMeasuredWidth()
    }

    @objc private func themeChanged() { applyPalette() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous)
            || traitCollection.preferredContentSizeCategory != previous?.preferredContentSizeCategory {
            applyPalette()
        }
    }
}

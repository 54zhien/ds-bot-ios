import UIKit

/// The chat header's floating glass, as mobile/src/nav/ShellB.tsx draws it: a
/// passthrough container, 44pt controls and the pills between them.
/// RN's pointerEvents="box-none" equivalent: only real controls catch touches.
final class PassthroughHeader: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        controlHit(self, at: point)
    }

    /// The controls sit in a wrapping row whose frame spans the header's blank
    /// gaps; only controls and gesture bearers may answer, not the row itself.
    private func controlHit(_ view: UIView, at point: CGPoint) -> Bool {
        for child in view.subviews {
            guard child.isUserInteractionEnabled, !child.isHidden else { continue }
            // The point is converted into the child's own space, so the frame it is
            // tested against must be the child's bounds: frame lives in the parent's
            // space, and mixing the two made every control away from x = 0 miss.
            let local = view.convert(point, to: child)
            guard child.bounds.insetBy(dx: -8, dy: -8).contains(local) else { continue }
            if child is UIControl { return true }
            if let gestures = child.gestureRecognizers, !gestures.isEmpty { return true }
            if controlHit(child, at: local) { return true }
        }
        return false
    }
}

/// GlassControl from mobile/src/ui/glass.tsx: 44pt of glass with a glyph in the
/// middle and, when asked, the 8pt pending dot on the glyph's corner.
final class GlassControlView: UIControl {
    var showsDot = false { didSet { dot.isHidden = !showsDot } }
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let dot = UIView()

    init(label: String, icon: UIView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = .button

        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.layer.cornerRadius = Glass.control / 2
        surface.layer.borderWidth = 1
        surface.layer.masksToBounds = true
        // A glass surface that takes touches would swallow them before the control
        // ever tracks: the control must be the hit view, so the blur stays passive.
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        layer.cornerRadius = Glass.control / 2

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        icon.backgroundColor = .clear
        surface.contentView.addSubview(icon)

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer.cornerRadius = 4
        dot.isHidden = true
        surface.contentView.addSubview(dot)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Glass.control),
            heightAnchor.constraint(equalToConstant: Glass.control),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            // The dot's centre sits on the glyph's top-right corner.
            dot.centerXAnchor.constraint(equalTo: icon.trailingAnchor),
            dot.centerYAnchor.constraint(equalTo: icon.topAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        // RN dims a pressed control to 0.7 instead of tinting it.
        addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(restored), for: [.touchDragExit, .touchCancel])
        addTarget(self, action: #selector(restored), for: .touchUpInside)
        applyPalette()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // CGColor snapshots follow neither traits nor theme switches, so repaint on both.
    private func applyPalette() {
        let p = ThemeStore.palette(trait: traitCollection)
        applySurface()
        surface.layer.borderColor = p.line.cgColor
        dot.backgroundColor = p.accent
    }

    /// Liquid glass on 26 and up: it carries its own highlight and refraction, so it
    /// takes no rim. The material fallback keeps the 1pt line the phone design uses.
    private func applySurface() {
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect()
            surface.layer.borderWidth = 0
        } else {
            surface.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            surface.layer.borderWidth = 1
        }
    }

    @objc private func themeChanged() { applyPalette() }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyPalette()
        }
    }

    @objc private func pressed() { alpha = 0.7 }
    @objc private func restored() { alpha = 1 }
}

/// GlassPill from mobile/src/ui/glass.tsx: a capsule of glass at a given height,
/// horizontal content, and the 1pt rim the phone design uses.
final class GlassPillView: UIView {
    let content: UIStackView
    private let surface: UIVisualEffectView

    init(height: CGFloat) {
        surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        surface.layer.cornerRadius = height / 2
        surface.layer.borderWidth = 1
        surface.layer.masksToBounds = true
        content = UIStackView()
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = Glass.gap
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // Same reason as the control: the pill sits on top of a button-bearing
        // view, so the blur is passive and the content joins the pill directly.
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        addSubview(content)
        surface.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: surface.contentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
        ])
        applyPalette()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A pill is decoration except for the buttons it carries: answering for itself
    /// would hide the control underneath, which is the tap the user meant.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    // The rim is a CGColor snapshot; repaint it when traits or the theme move.
    private func applyPalette() {
        applySurface()
        surface.layer.borderColor = ThemeStore.palette(trait: traitCollection).line.cgColor
    }

    private func applySurface() {
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect()
            surface.layer.borderWidth = 0
        } else {
            surface.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            surface.layer.borderWidth = 1
        }
    }

    @objc private func themeChanged() { applyPalette() }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyPalette()
        }
    }
}

/// Frosted glass that fades out: a blur with the page's own colour laid over it, both
/// cut by one alpha mask. The mask is what does the fading — a colour ramp can only
/// smear the page's colour, and at the top of the header it reads as a band; blurring
/// the content and taking the blur away gradually reads as the content dissolving.
///
/// Three stops, monotonic, no step between them: fully opaque from the top, one ramp at
/// the end down to nothing. The ramp is capped at 40% of the height so the top 60% is
/// always fully blurred, whatever height the caller gives it.
final class FadeOverlayView: UIView {
    /// The stretch the mask takes to reach zero.
    private static let ramp: CGFloat = 24
    /// Enough page colour over the blur to hold the theme, not enough to be a fill.
    private static let wash: CGFloat = 0.18

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let washView = UIView()
    private let maskLayer = CAGradientLayer()

    /// For the tests: where the mask's stops landed, and the colour laid over the blur.
    var maskLocations: [NSNumber] { maskLayer.locations ?? [] }
    var washAlpha: CGFloat { washView.backgroundColor?.cgColor.alpha ?? 0 }

    init() {
        super.init(frame: .zero)
        // Translation stays on here: whoever installs this view decides. Off, and nothing
        // holds the size a bare instance is handed once a layout pass runs.
        isUserInteractionEnabled = false
        blur.isUserInteractionEnabled = false
        washView.isUserInteractionEnabled = false
        for view in [blur, washView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(color: UIColor) {
        washView.backgroundColor = color.withAlphaComponent(Self.wash)
        applyStops()
    }

    /// Recomputes the mask for the current bounds. Called from configure and from layout,
    /// and callable on its own so a test does not have to rely on a layout pass happening
    /// in a headless window.
    func refreshMask() { applyStops() }

    /// The three stops for a given height, pure so the arithmetic can be checked without a
    /// laid-out view: opaque from the top, one ramp at the end down to zero, and a ramp that
    /// never eats more than 40% of the height.
    static func stops(forHeight height: CGFloat) -> [NSNumber] {
        // A view with no height has nothing to fade yet. It still gets stops - callers read
        // [1] unconditionally, and an empty array is an index crash, not a missing value.
        guard height > 1 else { return [0, 1, 1] }
        let ramp = min(Self.ramp, height * 0.4)
        return [0, NSNumber(value: Double((height - ramp) / height)), 1]
    }

    private func applyStops() {
        // Colours before the height is known: a mask without them draws nothing, and the first
        // pass after init can be one that runs while the view is still zero-sized.
        maskLayer.colors = [UIColor.white.cgColor, UIColor.white.cgColor,
                            UIColor.white.withAlphaComponent(0).cgColor]
        maskLayer.locations = Self.stops(forHeight: bounds.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        applyStops()
        CATransaction.commit()
    }
}

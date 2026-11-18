import UIKit

/// The chat header's floating glass, as mobile/src/nav/ShellB.tsx draws it: a
/// passthrough container, 44pt controls and the pills between them.
/// RN's pointerEvents="box-none" equivalent: only real controls catch touches.
final class PassthroughHeader: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { child in
            child.isUserInteractionEnabled && !child.isHidden && child.frame.insetBy(dx: -8, dy: -8).contains(point)
        }
    }
}

/// GlassControl from mobile/src/ui/glass.tsx: 44pt of glass with a glyph in the
/// middle and, when asked, the 8pt pending dot on the glyph's corner.
final class GlassControlView: UIControl {
    var showsDot = false { didSet { dot.isHidden = !showsDot } }
    private let dot = UIView()

    init(label: String, icon: UIView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = .button

        let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.layer.cornerRadius = Glass.control / 2
        surface.layer.borderWidth = 1
        surface.layer.masksToBounds = true
        addSubview(surface)
        layer.cornerRadius = Glass.control / 2

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        icon.backgroundColor = .clear
        surface.contentView.addSubview(icon)

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = ThemeStore.palette(trait: traitCollection).accent
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func pressed() { alpha = 0.7 }
    @objc private func restored() { alpha = 1 }
}

/// GlassPill from mobile/src/ui/glass.tsx: a capsule of glass at a given height,
/// horizontal content, and the 1pt rim the phone design uses.
final class GlassPillView: UIView {
    let content: UIStackView

    init(height: CGFloat) {
        let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
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
        addSubview(surface)
        surface.contentView.addSubview(content)
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A plain-colour fade, the same device the drawer's bottom uses: one colour from
/// solid to nothing over the given height, longer than the system's soft edge.
final class FadeOverlayView: UIView {
    private let gradient = CAGradientLayer()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(color: UIColor) {
        gradient.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}

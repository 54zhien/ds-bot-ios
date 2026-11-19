import UIKit

// UIKit rewrite of Zen-Agent App/Workspace/SidebarRailView.swift (180 lines);
// geometry values taken from SidebarRailLayout/SidebarProgressPresentation verbatim,
// shape/draw code re-authored for UIKit.
//
// What came from where:
//   :30-35   contentWidth 64, controlSize 56, iconSize 25, minimumLeadingInset 16,
//            topSafeAreaPadding 12, bottomSafeAreaPadding 16
//   :46-49   leading = max(windowInsets.leading, 16)
//            top     = max(cornerRadius - 28, windowInsets.top + 12)
//            bottom  = windowInsets.bottom + 16
//   :40      width   = contentWidth + leading * 2
//   :54-61   settingsPlacement: a 36pt corner or wider puts Settings on the display
//            corner's centre, shifted by (radius - 28) - (leading + 4)
//   :67-76   edge hairline alpha 0.16; rail opacity 0.25 + 0.75 * progress
//   :92-124  new / search (grouped) / recent in one capsule, files in its own
//            circle, settings alone at the bottom, spacing 8
//   :174-179 dim 0.35 when unavailable, press scale 0.92
// The rail is never the thing that takes the swipe: the interaction owns the gesture
// and this column only draws.

/// :29-62, verbatim.
struct SidebarRailLayout {
    static let contentWidth: CGFloat = 64
    static let controlSize: CGFloat = 56
    static let iconSize: CGFloat = 25
    static let minimumLeadingInset: CGFloat = 16
    static let topSafeAreaPadding: CGFloat = 12
    static let bottomSafeAreaPadding: CGFloat = 16

    let leading: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    var width: CGFloat { Self.contentWidth + leading * 2 }

    init(windowInsets: NSDirectionalEdgeInsets, cornerRadius: CGFloat) {
        leading = max(windowInsets.leading, Self.minimumLeadingInset)
        top = max(cornerRadius - Self.controlSize / 2, windowInsets.top + Self.topSafeAreaPadding)
        bottom = windowInsets.bottom + Self.bottomSafeAreaPadding
    }

    /// :54-61. Settings shares the display corner's centre while the corner is wide
    /// enough to hold a control; a smaller corner keeps the column slot.
    func settingsPlacement(windowCornerRadius radius: CGFloat,
                           isRightToLeft: Bool = false) -> (bottom: CGFloat, leadingShift: CGFloat) {
        let half = Self.controlSize / 2
        guard radius.isFinite, radius >= half + 8 else { return (bottom, 0) }
        let columnLeading = leading + (Self.contentWidth - Self.controlSize) / 2
        let shift = (radius - half) - columnLeading
        return (radius - half, isRightToLeft ? -shift : shift)
    }
}

/// :64-77, verbatim: the hairline the split divider fades into, and the rail's own
/// opacity as it slides.
enum SidebarProgressPresentation {
    static let edgeOpacity: CGFloat = 0.16

    static func edgeColor(traits: UITraitCollection) -> UIColor {
        UIColor.label.resolvedColor(with: traits).withAlphaComponent(edgeOpacity)
    }

    static func opacity(forProgress progress: Double) -> Double {
        let clamped = progress.isFinite ? min(1, max(0, progress)) : 0
        return 0.25 + 0.75 * clamped
    }
}

/// :79-166 as a UIKit column.
final class SidebarRailView: UIView {
    /// :81-88. A control that is not available dims instead of disappearing; a moving
    /// rail is inert without being dimmed.
    var onAction: ((String) -> Void)?
    var onSelect: ((String) -> Void)?

    var isInteractive = true { didSet { updateEnabled() } }
    var availableActions: Set<String> = [] { didSet { updateEnabled() } }
    var availableRoutes: Set<String> = [] { didSet { updateEnabled() } }

    private let layout: SidebarRailLayout
    private let column = UIStackView()
    private let settingsButton = RailButton(symbol: "gearshape", identifier: "sidebar-settings")
    private lazy var settings = SidebarRailGlass(button: settingsButton)
    private var settingsBottom: NSLayoutConstraint!
    private var settingsLeading: NSLayoutConstraint!
    private let feedback = UIImpactFeedbackGenerator(style: .medium)
    private(set) var controls: [RailButton] = []
    private var kinds: [ObjectIdentifier: Kind] = [:]

    private enum Kind { case action(String), route(String) }

    init(layout: SidebarRailLayout, size: CGSize) {
        self.layout = layout
        super.init(frame: CGRect(x: 0, y: 0, width: layout.width, height: size.height))
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "sidebar-rail"

        // :95-105: the column keeps its place; a window too short to hold every control
        // scrolls rather than clipping one away.
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)

        // :116-124: the three conversation controls share one capsule, then files.
        let newChat = RailButton(symbol: "message", identifier: "new-conversation-new")
        let search = RailButton(symbol: "magnifyingglass", identifier: "sidebar-search")
        let recent = RailButton(symbol: "clock.arrow.circlepath", identifier: "new-conversation-recent")
        let capsule = SidebarRailGlass(cornerRadius: SidebarRailLayout.controlSize / 2)
        for button in [newChat, search, recent] { capsule.content.addArrangedSubview(button) }
        column.addArrangedSubview(capsule)

        let filesButton = RailButton(symbol: "folder", identifier: "sidebar-files")
        column.addArrangedSubview(SidebarRailGlass(button: filesButton))

        // :106: settings rides at the bottom, outside the column.
        addSubview(settings)
        settingsBottom = settings.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -layout.bottom)
        settingsLeading = settings.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.leading)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.leading),
            scroll.widthAnchor.constraint(equalToConstant: SidebarRailLayout.contentWidth),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: layout.top),
            scroll.bottomAnchor.constraint(equalTo: settings.topAnchor, constant: -8),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            column.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            column.widthAnchor.constraint(equalToConstant: SidebarRailLayout.contentWidth),
            settingsBottom,
            settingsLeading,
        ])

        register(newChat, as: .action("new"))
        register(search, as: .route("search"))
        register(recent, as: .action("recent"))
        register(filesButton, as: .route("files"))
        register(settingsButton, as: .route("settings"))
        controls = [newChat, search, recent, filesButton, settingsButton]
        for button in controls {
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        }
        accessibilityElements = controls
        availableActions = ["new", "recent"]
        availableRoutes = ["search", "files", "settings"]
        updateEnabled()
        feedback.prepare()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func register(_ button: RailButton, as kind: Kind) {
        kinds[ObjectIdentifier(button)] = kind
    }

    /// :54-61. Settings moves to the display corner's centre while the corner holds
    /// it, otherwise it keeps the column's leading edge.
    func placeSettings(windowCornerRadius radius: CGFloat, isRightToLeft: Bool = false) {
        let placement = layout.settingsPlacement(windowCornerRadius: radius, isRightToLeft: isRightToLeft)
        settingsBottom.constant = -placement.bottom
        settingsLeading.constant = layout.leading + placement.leadingShift
    }

    /// :73-76, the rail fades as it slides.
    func apply(progress: Double) {
        alpha = CGFloat(SidebarProgressPresentation.opacity(forProgress: progress))
    }

    private func updateEnabled() {
        for button in controls {
            let available: Bool
            switch kinds[ObjectIdentifier(button)] {
            case .action(let id): available = availableActions.contains(id)
            case .route(let id): available = availableRoutes.contains(id)
            case .none: available = false
            }
            button.unavailable = !available
            button.isEnabled = isInteractive && available
        }
    }

    @objc private func tapped(_ sender: RailButton) {
        guard sender.isEnabled else { return }
        feedback.impactOccurred()
        switch kinds[ObjectIdentifier(sender)] {
        case .action(let id): onAction?(id)
        case .route(let id): onSelect?(id)
        case .none: break
        }
    }
}

/// :121 / :150: the glass behind one control (a circle) or behind the grouped column
/// (a capsule). iOS 26's liquid glass carries its own highlight; the material
/// fallback keeps the 1pt rim the phone design uses.
final class SidebarRailGlass: UIView {
    let content = UIStackView()
    let button: RailButton?
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))

    /// A lone control: 56pt of circle glass around its own button.
    init(button: RailButton) {
        self.button = button
        super.init(frame: .zero)
        build(cornerRadius: SidebarRailLayout.controlSize / 2)
        content.addArrangedSubview(button)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: SidebarRailLayout.controlSize),
            heightAnchor.constraint(equalToConstant: SidebarRailLayout.controlSize),
        ])
    }

    /// The grouped column: a capsule 56pt wide whose height is its three controls.
    init(cornerRadius: CGFloat) {
        button = nil
        super.init(frame: .zero)
        build(cornerRadius: cornerRadius)
        widthAnchor.constraint(equalToConstant: SidebarRailLayout.controlSize).isActive = true
    }

    private func build(cornerRadius: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.layer.cornerRadius = cornerRadius
        surface.layer.masksToBounds = true
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect(style: .regular)
        } else {
            surface.layer.borderWidth = 1
            surface.layer.borderColor = Self.rim(for: traitCollection).cgColor
        }
        addSubview(surface)
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.contentView.addSubview(content)
        NSLayoutConstraint.activate([
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

    /// The rim is a CGColor snapshot, so it is taken from the palette every time the
    /// appearance changes rather than once at init.
    private static func rim(for traits: UITraitCollection) -> UIColor {
        UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.08)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
        surface.layer.borderColor = Self.rim(for: traitCollection).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// :160-165 (controlIcon) and :174-179 (the button style): a 56pt square with a 25pt
/// symbol, a dim when unavailable, a 0.28 press spring.
final class RailButton: UIControl {
    private let icon = UIImageView()
    var unavailable = false { didSet { alpha = unavailable ? 0.35 : 1 } }

    init(symbol: String, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(systemName: symbol,
                             withConfiguration: UIImage.SymbolConfiguration(
                                pointSize: SidebarRailLayout.iconSize, weight: .regular))
        icon.contentMode = .center
        icon.tintColor = .label
        icon.isUserInteractionEnabled = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        accessibilityIdentifier = identifier
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = RailButton.label(for: symbol)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: SidebarRailLayout.controlSize),
            heightAnchor.constraint(equalToConstant: SidebarRailLayout.controlSize),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addTarget(self, action: #selector(pressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside,
                                                           .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet { accessibilityTraits = isEnabled ? .button : [.button, .notEnabled] }
    }

    /// :137/156: the control is labelled with the words the screen shows.
    private static func label(for symbol: String) -> String {
        switch symbol {
        case "message": return NativeLanguage.text("New conversation")
        case "magnifyingglass": return NativeLanguage.text("Search")
        case "clock.arrow.circlepath": return NativeLanguage.text("Recent conversations")
        case "folder": return NativeLanguage.text("Files")
        case "gearshape": return NativeLanguage.text("Settings")
        default: return symbol
        }
    }

    /// :170-179. SwiftUI's bounce has no UIKit twin; damping 0.7 at the same 0.28 is
    /// the nearest spring, and Reduce Motion drops the scale as zen does.
    @objc private func pressed() {
        animate(scale: 0.92)
    }

    @objc private func released() {
        animate(scale: 1)
    }

    private func animate(scale: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            icon.transform = CGAffineTransform(scaleX: scale, y: scale)
            return
        }
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.icon.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}

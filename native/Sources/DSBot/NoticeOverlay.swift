import UIKit

/// The in-app notice banner, one window-level layer above every screen and
/// sheet, the way the RN shell draws it (mobile/src/nav/ShellB.tsx:272-313).
/// The chat view used to own the banner, and the first presented sheet buried
/// it; from window level a notice stays visible while Settings is open.
@MainActor
final class NoticeOverlay {
    static let shared = NoticeOverlay()

    private var container: PassthroughView?
    private let banner = UIButton(type: .system)
    private var generation = 0
    private var onTap: (() -> Void)?
    private var onAutoHide: (() -> Void)?

    private init() {
        banner.titleLabel?.numberOfLines = 2
        banner.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        banner.contentHorizontalAlignment = .leading
        banner.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        banner.layer.cornerRadius = 12
        banner.layer.borderWidth = 1
        banner.addAction(UIAction { [weak self] _ in self?.tapped() }, for: .touchUpInside)
    }

    func show(text: String, onTap: (() -> Void)?, onAutoHide: (() -> Void)?) {
        attach()
        guard let container else { return }
        self.onTap = onTap
        self.onAutoHide = onAutoHide
        banner.setTitle(text, for: .normal)
        restyle()
        container.isHidden = false
        generation += 1
        let mine = generation
        // RN dismisses after 8 s; the generation guard keeps an expired timer
        // from clearing a newer banner (ShellB.tsx:303).
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.generation == mine, let layer = self.container, !layer.isHidden else { return }
            layer.isHidden = true
            self.onAutoHide?()
        }
    }

    private func tapped() {
        container?.isHidden = true
        onTap?()
    }

    /// One layer, on the frontmost window and only there: a repeat call while
    /// the layer already hangs on that window is a no-op, and the layer never
    /// belongs to a view controller's view hierarchy.
    private func attach() {
        guard let window = Self.keyWindow(), window !== container?.window else { return }
        let layer = ensureContainer()
        if layer.superview != nil { layer.removeFromSuperview() }
        window.addSubview(layer)
        NSLayoutConstraint.activate([
            layer.topAnchor.constraint(equalTo: window.topAnchor),
            layer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            layer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            layer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
        ])
    }

    private func ensureContainer() -> PassthroughView {
        if let container { return container }
        let made = PassthroughView()
        made.isHidden = true
        made.translatesAutoresizingMaskIntoConstraints = false
        banner.translatesAutoresizingMaskIntoConstraints = false
        made.addSubview(banner)
        // safeArea + 8 at the top, 12 at the sides: the shell margins RN uses.
        // The layer pins to the window and never listens to the keyboard, so a
        // banner does not ride up with the composer.
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: made.safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: made.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: made.trailingAnchor, constant: -12),
        ])
        // Colours follow the team theme and are re-fetched, not baked at build.
        NotificationCenter.default.addObserver(
            forName: ThemeStore.changed, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.restyle() } }
        container = made
        return made
    }

    private func restyle() {
        let palette = ThemeStore.palette(trait: container?.window?.traitCollection ?? .current)
        banner.backgroundColor = palette.card
        banner.setTitleColor(palette.ink, for: .normal)
        banner.layer.borderColor = palette.accent.cgColor
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .compactMap(\.keyWindow)
            .first
    }

    /// The layer claims no touches of its own: only the banner's frame answers,
    /// everything around it falls through to whatever is on screen behind.
    private final class PassthroughView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            subviews.contains { $0.frame.contains(point) }
        }
    }
}

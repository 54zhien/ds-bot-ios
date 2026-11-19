import UIKit

/// The wiring between the gesture, the state machine and the page.
/// ConversationSurfaceHost.swift:500-531 is the same three pieces on zen's side: the
/// state machine owns progress, the transport carries the page, and the decoration
/// fades it. Nothing here decides how far the page goes: the wiring hands in a travel
/// in points, which is the drawer's own width, the number the old panel used for its
/// slide.
@MainActor
final class SidebarHost {
    let state = SidebarDragState()
    let interaction = WorkspaceSidebarInteraction()
    private let decoration = SidebarSurfaceDecoration()
    private weak var page: SidebarTransportView?
    private var showsDrawer = false

    /// How far the page travels when the sidebar is fully open, in points.
    var travel: CGFloat = 0
    var isRightToLeft = false
    /// Reduce Motion is read live in the app; the tests answer it themselves.
    var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The drawer rides the same open flag the gesture drives: opening presents the
    /// panel, closing dismisses it, and only the flag decides — never a second source.
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    /// Installs the interaction over the moving page and points it at the window. The
    /// anchor lives inside the page so it travels with the content; the touch maths stay
    /// in window coordinates, as they must once the page starts moving.
    func install(host: AnyObject, window: UIWindow, page: SidebarTransportView) {
        self.page = page
        page.addSubview(interaction)
        interaction.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            interaction.topAnchor.constraint(equalTo: page.topAnchor),
            interaction.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            interaction.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            interaction.trailingAnchor.constraint(equalTo: page.trailingAnchor),
        ])
        interaction.configure(state: state, travel: max(1, travel), isRightToLeft: isRightToLeft) {
            [weak self, weak host, weak window] in
            guard let self, let host, let window else { return nil }
            return WorkspaceSidebarNativeContext(hostID: ObjectIdentifier(host),
                                                 paneID: ObjectIdentifier(host),
                                                 window: window,
                                                 allowsOpening: true, allowsClosing: true,
                                                 surfaceView: self.page)
        }
        state.onChange = { [weak self] in self?.reflect() }
    }

    /// One source of motion: the page translates to progress * travel and nothing else
    /// moves. A settlement animates there; without one, progress is followed directly.
    func reflect() {
        guard let page else { return }
        let sign: CGFloat = isRightToLeft ? -1 : 1
        let target = CGFloat(state.progress) * travel * sign
        if let settlement = state.settlementID {
            SidebarSettlement.run(offset: target, on: page, reduceMotion: reduceMotion) { [weak self] in
                self?.state.completeSettlement(settlement)
            }
        } else {
            page.translate(to: target)
        }
        decoration.applyAppearance(surface: page, progress: CGFloat(state.progress),
                                   traits: page.traitCollection)
        syncDrawer()
    }

    private func syncDrawer() {
        guard state.isOpen != showsDrawer else { return }
        showsDrawer = state.isOpen
        if showsDrawer { onOpen?() } else { onClose?() }
    }
}

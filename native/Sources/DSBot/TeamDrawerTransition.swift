import UIKit

final class TeamDrawerTransition: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        TeamDrawerPresentationController(presentedViewController: presented, presenting: presenting)
    }

}

final class TeamDrawerPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let scrim = UIControl()
    private let fade = CAGradientLayer()

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let bounds = containerView?.bounds else { return .zero }
        return CGRect(x: 0, y: 0, width: min(bounds.width * 0.85, 340), height: bounds.height)
    }

    override var shouldRemovePresentersView: Bool { false }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        scrim.frame = containerView.bounds
        scrim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        scrim.alpha = 0
        scrim.accessibilityLabel = NativeLanguage.text("Close team list")
        scrim.addTarget(self, action: #selector(close), for: .touchUpInside)
        containerView.insertSubview(scrim, at: 0)
        if let panel = presentedView {
            let dark = panel.traitCollection.userInterfaceStyle == .dark
            let sidebar = ThemeStore.palette(dark: dark).sidebar
            fade.colors = [sidebar.withAlphaComponent(0).cgColor, sidebar.cgColor]
            fade.locations = [0, 1]
            panel.layer.addSublayer(fade)
        }
        // The list melts into the fade and the gear rides above it, so the gear is
        // added once the fade sublayer is in place: addSubview lands on top of it.
        if let list = presentedViewController as? TeamListViewController {
            list.installFooterGear()
        }
        // The drawer is presented without an animation of its own, so the coordinator is
        // often nil here. Without this branch the scrim stays invisible, which reads as
        // "the drawer has no dimming" rather than as a bug.
        let coordinator = presentedViewController.transitionCoordinator
        if Self.scrimNeedsSettingByHand(coordinator) {
            scrim.alpha = 1
        } else {
            coordinator?.animate(alongsideTransition: { _ in self.scrim.alpha = 1 })
        }
    }

    /// A present with no animation has no coordinator to ride along with, and the scrim
    /// has to be set by hand. Named so the rule is testable and so nobody "simplifies"
    /// the branch away: TeamDrawerScrimTests holds both sides of it.
    static func scrimNeedsSettingByHand(_ coordinator: UIViewControllerTransitionCoordinator?) -> Bool {
        coordinator == nil
    }

    // The panel's own slide lived here: a pan that moved presentedView and a swipe that
    // dismissed it. Both were replaced by the transport — the page moves and the drawer
    // stays still — and the swipe that closes is the page's reverse gesture. Scrim,
    // corner radius, the footer fade and the gear stay exactly as they were.

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.scrim.alpha = 0
        })
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        scrim.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
        let bounds = containerView?.bounds ?? .zero
        let radius = Metrics.screenRadius(bottomInset: containerView?.safeAreaInsets.bottom ?? 0, bounds: bounds)
        presentedView?.layer.cornerRadius = radius
        presentedView?.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        presentedView?.clipsToBounds = true
        guard let panel = presentedView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = CGRect(x: 0, y: panel.bounds.height - Metrics.gearFade, width: panel.bounds.width, height: Metrics.gearFade)
        CATransaction.commit()
    }

    @objc private func close() { presentedViewController.dismiss(animated: true) }
}


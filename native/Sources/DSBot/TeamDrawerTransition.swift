import UIKit

final class TeamDrawerTransition: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        TeamDrawerPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        TeamDrawerAnimator(opening: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        TeamDrawerAnimator(opening: false)
    }
}

private final class TeamDrawerPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let scrim = UIControl()
    // The panel's own drag: installed once, only its enabled flag changes, so a
    // dismissal never leaves the edge without a recogniser.
    private let pan = UIPanGestureRecognizer()
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
            pan.addTarget(self, action: #selector(drag))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            pan.isEnabled = false
            panel.addGestureRecognizer(pan)
            let dark = panel.traitCollection.userInterfaceStyle == .dark
            let sidebar = Palette.make(dark: dark).sidebar
            fade.colors = [sidebar.withAlphaComponent(0).cgColor, sidebar.cgColor]
            fade.locations = [0, 1]
            panel.layer.addSublayer(fade)
        }
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.scrim.alpha = 1
        })
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        pan.isEnabled = completed
    }

    /// Leftward drags only, so the list keeps its vertical scrolling.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === pan, let panel = presentedView else { return true }
        let velocity = pan.velocity(in: panel)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
    }

    /// mobile/src/nav/Drawer.tsx: the panel follows the finger, and past half the width
    /// or a fast flick it goes away.
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let panel = presentedView, let container = containerView else { return }
        let width = max(1, panel.bounds.width)
        let x = min(0, max(-width, gesture.translation(in: container).x))
        switch gesture.state {
        case .changed:
            panel.transform = CGAffineTransform(translationX: x, y: 0)
            scrim.alpha = 1 + x / width
        case .ended, .cancelled:
            let flick = gesture.velocity(in: container).x < -350
            if flick || x < -width / 2 {
                pan.isEnabled = false
                UIView.animate(withDuration: 0.22, animations: {
                    panel.transform = CGAffineTransform(translationX: -width, y: 0)
                    self.scrim.alpha = 0
                }, completion: { _ in
                    panel.transform = .identity
                    self.presentedViewController.dismiss(animated: false)
                })
            } else {
                let spring = Springs.shape
                UIView.animate(withDuration: spring.settling, delay: 0, usingSpringWithDamping: spring.dampingRatio,
                               initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    panel.transform = .identity
                    self.scrim.alpha = 1
                }
            }
        default:
            break
        }
    }

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

private final class TeamDrawerAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let opening: Bool

    init(opening: Bool) { self.opening = opening }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.38
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let controllerKey: UITransitionContextViewControllerKey = opening ? .to : .from
        let viewKey: UITransitionContextViewKey = opening ? .to : .from
        guard let controller = context.viewController(forKey: controllerKey),
              let panel = context.view(forKey: viewKey) else {
            context.completeTransition(false)
            return
        }
        if opening {
            context.containerView.addSubview(panel)
            panel.frame = controller.presentationController?.frameOfPresentedViewInContainerView
                ?? context.finalFrame(for: controller)
            panel.transform = CGAffineTransform(translationX: -panel.bounds.width, y: 0)
        }
        let finish = {
            panel.transform = self.opening
                ? .identity : CGAffineTransform(translationX: -panel.bounds.width, y: 0)
        }
        let complete: (Bool) -> Void = { _ in
            if !self.opening { panel.removeFromSuperview() }
            context.completeTransition(!context.transitionWasCancelled)
        }
        if UIAccessibility.isReduceMotionEnabled {
            finish()
            complete(true)
        } else {
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                           usingSpringWithDamping: 0.78, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: finish, completion: complete)
        }
    }
}

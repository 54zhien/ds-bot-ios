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

private final class TeamDrawerPresentationController: UIPresentationController {
    private let scrim = UIControl()

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
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.scrim.alpha = 1
        })
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
        presentedView?.layer.cornerRadius = 24
        presentedView?.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        presentedView?.clipsToBounds = true
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
        let key: UITransitionContextViewControllerKey = opening ? .to : .from
        guard let controller = context.viewController(forKey: key),
              let panel = context.view(forKey: key) else {
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

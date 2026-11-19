// deviation: host-provided helper standing in for the iOS 26 glass calls in
// App/Conversation/ComposerMenuPanel.swift:16,20,49, ComposerKeyboardMenuPresenter.swift:14,98,143
// and ComposerMenuDetailPresenter.swift:17,83; the zen files stay otherwise verbatim.
//
// `UIGlassEffect` and `UIView.cornerConfiguration` are iOS 26 API. The app deploys to 16.4, so
// those call sites go through this helper: the glass path below is zen's own call, kept verbatim,
// and the fallback is ours - a system material and a plain continuous-corner mask, which is what
// zen's geometry amounts to on a device that has no glass at all.

import UIKit

enum ZenGlass {
    static func material(interactive: Bool = false) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = interactive
            return glass
        } else {
            return UIBlurEffect(style: .systemThinMaterial)
        }
    }

    static func corners(_ view: UIView, radius: CGFloat) {
        if #available(iOS 26.0, *) {
            view.cornerConfiguration = .corners(radius: .fixed(Double(radius)))
        } else {
            view.layer.cornerRadius = radius
            view.layer.cornerCurve = .continuous
            view.layer.masksToBounds = true
        }
    }

    static func capsule(_ view: UIView) {
        if #available(iOS 26.0, *) {
            view.cornerConfiguration = .capsule()
        } else {
            view.layer.cornerRadius = view.bounds.height / 2
            view.layer.cornerCurve = .continuous
            view.layer.masksToBounds = true
        }
    }

    /// zen asks for a radius concentric with the container's; without glass the container radius
    /// is the closest available answer, so both paths take the same argument.
    static func concentric(_ view: UIView, minimum: CGFloat) {
        corners(view, radius: minimum)
    }
}

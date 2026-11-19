// ported verbatim from Zen-Agent App/App/WindowCornerGeometry.swift (25 lines)
// deviation: availability guard added for our iOS 16.4 deployment target; zen’s body otherwise unchanged.

import UIKit

/// Resolve public container-concentric geometry for the actual scene window.
@MainActor
final class WindowCornerGeometry {
    private weak var cachedWindow: UIWindow?
    private var cachedBounds: CGRect?
    private var cachedRadius: CGFloat = 0

    func radius(in window: UIWindow) -> CGFloat {
        if cachedWindow === window, cachedBounds == window.bounds { return cachedRadius }
        let reference = UIView(frame: window.bounds)
        reference.backgroundColor = .clear
        reference.isUserInteractionEnabled = false
        reference.isAccessibilityElement = false
        reference.accessibilityElementsHidden = true
        let radius: CGFloat
        if #available(iOS 26.0, *) {
            // zen's own body, unchanged.
            reference.cornerConfiguration = .uniformCorners(radius: .containerConcentric())
            window.addSubview(reference)
            reference.layoutIfNeeded()
            radius = reference.effectiveRadius(corner: .topLeft)
        } else {
            // deviation: our fallback, not zen code. Before iOS 26 there is no
            // concentric-corner API, so the window's own radius is the only honest
            // answer; it is usually zero and the composer draws square corners.
            reference.layer.cornerRadius = window.layer.cornerRadius
            reference.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            window.addSubview(reference)
            reference.layoutIfNeeded()
            radius = reference.layer.cornerRadius
        }
        reference.removeFromSuperview()
        cachedWindow = window
        cachedBounds = window.bounds
        cachedRadius = radius.isFinite ? max(0, radius) : 0
        return cachedRadius
    }
}

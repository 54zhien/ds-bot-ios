// ported from Zen-Agent App/Conversation/ComposerMenuPanel.swift (62 lines)
// deviation: the iOS 26 glass calls are routed through ZenGlass (see Boundary/ZenGlassStandIn.swift);
// everything else is zen's own text.

import SwiftUI
import UIKit

/// Each level owns its material. The root's content scales on a fixed layout
/// canvas so opening does not reflow labels or change their final alignment.
@MainActor
final class ComposerMenuPanel {
    let glass: UIVisualEffectView
    let content: UIHostingController<ComposerActionMenuView>
    private let material: UIVisualEffect
    private(set) var contentSize = CGSize.zero
    private let expandedRadius: CGFloat

    init(rootView: ComposerActionMenuView, expandedRadius: CGFloat) {
        self.expandedRadius = expandedRadius
        let effect = ZenGlass.material()
        material = effect
        glass = UIVisualEffectView(effect: effect)
        ZenGlass.corners(glass, radius: expandedRadius)
        glass.contentView.clipsToBounds = true
        content = UIHostingController(rootView: rootView)
        content.view.backgroundColor = .clear
        content.safeAreaRegions = []
    }

    func install(in parent: UIViewController) {
        parent.addChild(content)
        parent.view.addSubview(glass)
        glass.contentView.addSubview(content.view)
        content.didMove(toParent: parent)
    }

    func measure(in maximumSize: CGSize) -> CGSize {
        let fitted = content.sizeThatFits(in: maximumSize)
        contentSize = CGSize(width: maximumSize.width, height: min(maximumSize.height, ceil(fitted.height)))
        return contentSize
    }

    func showMaterial(_ visible: Bool) {
        // Animate the effect itself so UIKit materializes the glass without
        // fading the entire visual-effect hierarchy through an offscreen pass.
        glass.effect = visible ? material : nil
    }

    func place(_ frame: CGRect, radius: CGFloat? = nil, contentAlpha: CGFloat = 1,
               contentScale: CGFloat = 1) {
        glass.frame = frame
        ZenGlass.corners(glass, radius: radius ?? expandedRadius)
        content.view.bounds = CGRect(origin: .zero, size: contentSize)
        content.view.center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        content.view.transform = CGAffineTransform(scaleX: contentScale, y: contentScale)
        content.view.alpha = contentAlpha
    }

    func remove() {
        content.willMove(toParent: nil)
        content.view.removeFromSuperview()
        content.removeFromParent()
        glass.removeFromSuperview()
    }
}
import UIKit

/// iOS 26 blurs the top edge of a scroll view itself: `UIScrollEdgeEffect(.soft)` smears what
/// scrolls under the glass header and trails off, which is the picture `FadeOverlayView` was
/// built to imitate. The hand-rolled view stays for iOS 17-25, which has no such API.
@MainActor
enum ChatTopEdgeEffect {
    /// True when the system draws the top edge, so the fallback has to stay out of its way.
    static var ownedBySystem: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func apply(to scrollView: UIScrollView, fallback: UIView) {
        if #available(iOS 26.0, *) {
            // `.hard` is the hard cutoff with a dividing line - the band the reader turned
            // down. `.soft` is the gradual one.
            scrollView.topEdgeEffect.style = .soft
        }
        fallback.isHidden = ownedBySystem
    }
}

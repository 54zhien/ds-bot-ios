import UIKit

// Zen-Agent App/Workspace/ConversationSurfaceHost.swift:506-531: the page rides on a
// transport ancestor that moves content and its shadow as one horizontal unit, and a
// settlement is a 0.22s easeOut UIViewPropertyAnimator that reports back when it lands.
// Reduce Motion jumps instead (:518-529).
//
// The distance is not invented here: zen's caller hands in an offset in points and the
// interaction's progress separately, so this view takes both the same way and keeps no
// opinion about how far a page should slide.

/// The ancestor the page translates on. It holds no content of its own and applies one
/// transform, so nothing inside it learns that the sidebar exists.
final class SidebarTransportView: UIView {
    private(set) var offset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        // The page underneath keeps its own clips and shadows; this view only moves.
        clipsToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// :508. One horizontal unit: content and shadow move together because they are the
    /// same view, not because two animators agree.
    func translate(to offset: CGFloat, animated: Bool = false) {
        guard animated else {
            UIView.performWithoutAnimation { setOffset(offset.isFinite ? offset : 0) }
            return
        }
        let animator = UIViewPropertyAnimator(duration: SidebarSettlement.duration, curve: .easeOut) {
            self.setOffset(offset.isFinite ? offset : 0)
        }
        animator.startAnimation()
    }

    /// The model change on its own, with no animation opinion of its own: the caller
    /// wraps it in either performWithoutAnimation or an animator.
    func setOffset(_ value: CGFloat) {
        let next = value.isFinite ? value : 0
        offset = next
        transform = CGAffineTransform(translationX: next, y: 0)
    }
}

/// :518-531: a settlement either jumps (Reduce Motion) or runs 0.22s easeOut, and either
/// way it reports the id it was given so a stale ending cannot release a newer gesture.
enum SidebarSettlement {
    /// :531, the only duration that appears in the transport.
    static let duration: TimeInterval = 0.22

    static func run(offset: CGFloat, on transport: SidebarTransportView,
                    reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
                    completion: @escaping () -> Void) {
        guard !reduceMotion else {
            transport.translate(to: offset)
            // Land on the next turn, so the caller's layout settles first: zen yields
            // before reporting (:523-528) and a synchronous report would arrive inside
            // the same run loop as the jump.
            Task { @MainActor in
                await Task.yield()
                completion()
            }
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            transport.setOffset(offset)
        }
        animator.addCompletion { position in
            guard position == .end else { return }
            completion()
        }
        animator.startAnimation()
    }
}

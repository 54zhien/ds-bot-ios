import Foundation

/// The arithmetic behind a list that does not move under its reader: rows arriving
/// above keep the focus in place, and the newest rows follow only a reader who is
/// already at the bottom. The React Native list gets this from
/// maintainVisibleContentPosition and autoscrollToTopThreshold; UIKit has neither,
/// so both judgments live here as plain numbers a test can check.
enum ScrollAnchor {
    /// Rows were added above the viewport: the offset moves down by exactly what the
    /// content grew, so the same rows stay under the thumb.
    static func offset(keepingFocus oldOffset: CGFloat, oldHeight: CGFloat, newHeight: CGFloat) -> CGFloat {
        oldOffset + (newHeight - oldHeight)
    }

    /// Whether the reader is with the newest rows: close enough to the bottom that
    /// new messages should follow, far enough up that dragging them down is wrong.
    /// An empty list counts as at the bottom, so a chat that just opened follows.
    static func atBottom(contentSize: CGFloat, offset: CGFloat, viewport: CGFloat, within distance: CGFloat = 120) -> Bool {
        contentSize - offset - viewport <= distance
    }
}

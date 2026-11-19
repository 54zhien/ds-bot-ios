import Foundation

/// The sidebar's own drag state, lifted from Zen-Agent
/// App/Workspace/WorkspaceNavigationState.swift:23-83: the flags the gesture code
/// reads and the three steps it drives. Zen's class also carries its surface layer —
/// overlays, pending actions, reselection hooks — and the interaction never reads any
/// of that, so none of it comes along.
final class SidebarDragState {
    private(set) var progress: Double = 0
    private(set) var isOpen = false
    private(set) var isDragging = false
    private(set) var settlementID: UUID?
    private(set) var gestureID: UUID?

    /// WorkspaceNavigationState.swift:41, with the overlay term dropped: we have no
    /// overlay layer to hold the content in place.
    var blocksLift: Bool { isDragging || progress > 0 || settlementID != nil }

    /// :44. Same guard as begin, then the sidebar counts as open at once.
    @discardableResult
    func open(eligible: Bool) -> Bool {
        guard eligible, !isDragging, settlementID == nil else { return false }
        isOpen = true
        progress = 1
        settlementID = UUID()
        return true
    }

    /// :51. Closing leaves a settlement behind whenever anything was showing, so the
    /// caller animates out and reports back through completeSettlement.
    func close() {
        if progress > 0 || isOpen { settlementID = UUID() }
        isDragging = false
        isOpen = false
        progress = 0
        gestureID = nil
    }

    /// :58. A gesture may not start while another is settling.
    @discardableResult
    func begin(eligible: Bool) -> Bool {
        guard eligible, !isDragging, settlementID == nil else { return false }
        isDragging = true
        gestureID = UUID()
        return true
    }

    /// :65. Progress reads the open flag plus the drag, so one formula covers a pull
    /// from either side; a gesture with no travel behind it ends as cancelled.
    func drag(displacement: Double, travel: Double) {
        guard isDragging else { return }
        guard displacement.isFinite, travel.isFinite, travel > 0 else {
            end(velocity: 0, travel: 1, cancelled: true)
            return
        }
        progress = min(1, max(0, (isOpen ? 1 : 0) + displacement / travel))
    }

    /// :74. A flick counts for 0.12 of a travel on top of where the finger stopped,
    /// which is what lets a short fast pull open the sidebar.
    func end(velocity: Double, travel: Double, cancelled: Bool) {
        guard isDragging else { return }
        if !cancelled, velocity.isFinite, travel.isFinite, travel > 0 {
            isOpen = progress + velocity / travel * 0.12 >= 0.5
        }
        isDragging = false
        gestureID = nil
        progress = isOpen ? 1 : 0
        settlementID = UUID()
    }

    /// :94. The animation reports back with the id it was given, so a stale ending
    /// cannot release a newer gesture.
    func completeSettlement(_ id: UUID) {
        guard settlementID == id else { return }
        settlementID = nil
    }

    /// :122. Losing the scene ends input ownership, not the page: the sidebar keeps
    /// the state it was showing.
    func suspendInteractions() {
        isDragging = false
        gestureID = nil
        settlementID = nil
        progress = isOpen ? 1 : 0
    }

    /// :130, without the reselection and overlay parts.
    func reset() {
        close()
        settlementID = nil
    }
}

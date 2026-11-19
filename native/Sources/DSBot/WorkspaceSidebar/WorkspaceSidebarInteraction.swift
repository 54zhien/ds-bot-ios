import UIKit

// Verbatim port of Zen-Agent App/Workspace/WorkspaceSidebarInteraction.swift (416
// lines), minus two things that cannot come over:
//
//   * WorkspaceSidebarGestureBridge (:30-47) is a UIViewRepresentable whose only job is
//     to put the gesture anchor inside a SwiftUI hierarchy. We have no SwiftUI host, so
//     the anchor is added as a subview and configured directly. That removes a bridge,
//     not logic.
//   * WorkspaceNavigationState (:18 there) stays behind as our own SidebarDragState; the
//     eleven members this file reads are the drag machine, not zen's navigation layer.
//
// Everything else is zen's: the window-level recognisers (:128-147), the admission and
// priority arbitration (:196-312), and the two changed() paths that drive progress
// (:314-409). The numbers are zen's too — the rail strip is one travel wide (:210), the
// horizontal test is |x| > |y| * 1.1 (:272).

@MainActor
struct WorkspaceSidebarNativeContext {
    let hostID: ObjectIdentifier
    let paneID: ObjectIdentifier
    let window: UIWindow
    let allowsOpening: Bool
    let allowsClosing: Bool
    weak var surfaceView: UIView?
    let additionalClosingViews: [UIView]

    init(hostID: ObjectIdentifier, paneID: ObjectIdentifier, window: UIWindow,
         allowsOpening: Bool, allowsClosing: Bool = true, surfaceView: UIView? = nil,
         additionalClosingViews: [UIView] = []) {
        self.hostID = hostID
        self.paneID = paneID
        self.window = window
        self.allowsOpening = allowsOpening
        self.allowsClosing = allowsClosing
        self.surfaceView = surfaceView
        self.additionalClosingViews = additionalClosingViews
    }

    func containsClosingView(_ view: UIView) -> Bool {
        let roots = additionalClosingViews + [surfaceView].compactMap { $0 }
        return view.window === window && roots.contains { view === $0 || view.isDescendant(of: $0) }
    }
}

/// One scene transport for the active host. The anchor itself never receives touches.
@MainActor
final class WorkspaceSidebarInteraction: UIView, UIGestureRecognizerDelegate {
    private let edge: UIScreenEdgePanGestureRecognizer
    private let reverse = UIPanGestureRecognizer()
    private let closeTap = UITapGestureRecognizer()
    private weak var attachedWindow: UIWindow?
    private weak var attachedEdgeView: UIView?
    private struct WindowGeometry: Equatable {
        let bounds: CGRect
        let edgeBounds: CGRect
        let orientation: UIInterfaceOrientation
        init(_ window: UIWindow, edgeView: UIView) {
            bounds = window.bounds
            edgeBounds = edgeView.bounds
            orientation = window.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown
        }
    }
    private var attachedGeometry: WindowGeometry?
    private var dragState: SidebarDragState?
    private var readContext: (() -> WorkspaceSidebarNativeContext?)?
    private var travel: CGFloat = 60
    private var sign: CGFloat = 1
    private typealias Owner = (host: ObjectIdentifier, pane: ObjectIdentifier, window: ObjectIdentifier)
    private var captured: Owner?
    private var capturedGestureID: UUID?
    private var tapOwner: Owner?
    private var edgeTouchOwner: Owner?
    private var edgeTouchOrigin: CGPoint?
    private var edgeRejected = false

    /// DEBUG only, and settable from the wiring: zen forwards the same lines to its
    /// navigation object's nativeEvents (:172-176), which we deliberately do not carry.
    #if DEBUG
    var debugRecord: ((String) -> Void)?
    #endif

    override convenience init(frame: CGRect) {
        self.init(frame: frame, edge: UIScreenEdgePanGestureRecognizer())
    }

    init(frame: CGRect, edge: UIScreenEdgePanGestureRecognizer) {
        self.edge = edge
        super.init(frame: frame)
        for recognizer in [edge, reverse, closeTap] {
            recognizer.delegate = self
            // The shifted surface tap must not also become a timeline blank tap that
            // dismisses the retained editor. Rail controls are excluded below.
            recognizer.cancelsTouchesInView = true
            recognizer.addTarget(self, action: #selector(changed(_:)))
        }
        edge.maximumNumberOfTouches = 1
        reverse.maximumNumberOfTouches = 1
        closeTap.require(toFail: reverse)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(state: SidebarDragState, travel: CGFloat, isRightToLeft: Bool,
                   context: @escaping () -> WorkspaceSidebarNativeContext?) {
        dragState = state
        readContext = context
        self.travel = max(1, travel)
        sign = isRightToLeft ? -1 : 1
        let edges: UIRectEdge = isRightToLeft ? .right : .left
        if edge.edges != edges {
            // Cancel the old direction before changing the native edge policy.
            detach()
            edge.edges = edges
        }
        attach()
        if edgeTouchOwner != nil, !sameOwner(edgeTouchOwner) {
            edgeTouchOwner = nil
            edgeTouchOrigin = nil
        }
        if captured != nil, !sameOwner(captured) {
            if dragState?.gestureID == capturedGestureID { dragState?.reset() }
            captured = nil
            capturedGestureID = nil
        }
    }

    override func didMoveToWindow() { super.didMoveToWindow(); attach() }
    override func layoutSubviews() { super.layoutSubviews(); attach() }

    /// :128-147. The edge recogniser goes on the scene's root view when it is reachable
    /// and falls back to the window; the closing pair always goes on the window, because
    /// the surface moves under a page that is not the recogniser's ancestor.
    private func attach() {
        let edgeView: UIView? = window.map { window in
            if let root = window.rootViewController?.viewIfLoaded,
               root.window === window, isDescendant(of: root) { return root }
            return window
        }
        let geometry = window.flatMap { window in edgeView.map { WindowGeometry(window, edgeView: $0) } }
        guard window !== attachedWindow || edgeView !== attachedEdgeView || geometry != attachedGeometry else { return }
        detach()
        guard let window, let edgeView else { return }
        attachedWindow = window
        attachedEdgeView = edgeView
        attachedGeometry = geometry
        edgeView.addGestureRecognizer(edge)
        for recognizer in [reverse, closeTap] { window.addGestureRecognizer(recognizer) }
        record("attach bounds=\(window.bounds),edgeView=\(type(of: edgeView)),edgeBounds=\(edgeView.bounds),orientation=\(geometry?.orientation.rawValue ?? 0),edge=\(edge.edges.rawValue)")
    }

    func detach() {
        attachedEdgeView?.removeGestureRecognizer(edge)
        for recognizer in [reverse, closeTap] { attachedWindow?.removeGestureRecognizer(recognizer) }
        attachedWindow = nil
        attachedEdgeView = nil
        attachedGeometry = nil
        captured = nil
        capturedGestureID = nil
        tapOwner = nil
        edgeTouchOwner = nil
        edgeTouchOrigin = nil
        edgeRejected = false
        if let dragState, dragState.blocksLift || dragState.isOpen { dragState.reset() }
    }

    private func sameOwner(_ captured: Owner?) -> Bool {
        guard let captured, let current = readContext?(), current.window === attachedWindow else { return false }
        return captured.host == current.hostID && captured.pane == current.paneID
            && captured.window == ObjectIdentifier(current.window)
    }

    private func record(_ message: @autoclosure () -> String) {
        #if DEBUG
        debugRecord?(message())
        #endif
    }

    private func kind(_ gesture: UIGestureRecognizer) -> String {
        gesture === edge ? "edge" : gesture === reverse ? "reverse" : "tap"
    }

    // MARK: - Admission

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === edge { edgeTouchOwner = nil; edgeTouchOrigin = nil; edgeRejected = false }
        guard let window = attachedWindow, let current = readContext?(), current.window === window,
              convert(bounds, to: window).contains(touch.location(in: window)) else { return false }
        if gestureRecognizer === edge {
            let eligible = dragState?.isOpen == false && current.allowsOpening
            let x = touch.location(in: window).x
            let distance = sign > 0 ? x - window.bounds.minX : window.bounds.maxX - x
            // Limit the failure priority to this touch's leading rail strip; the system
            // screen-edge recogniser still decides its own edge radius (:208-213).
            if eligible, distance >= 0, distance <= travel {
                edgeTouchOwner = (current.hostID, current.paneID, ObjectIdentifier(window))
                edgeTouchOrigin = touch.location(in: window)
            }
            return eligible
        }
        guard dragState?.isOpen == true, current.allowsClosing,
              let hit = touch.view, current.containsClosingView(hit) else { return false }
        if gestureRecognizer === reverse {
            // A selection inside the text view owns the drag (:221-227).
            var node: UIView? = hit
            while let view = node {
                if let editor = view as? UITextView, editor.selectedTextRange?.isEmpty == false { return false }
                node = view.superview
            }
        }
        let x = touch.location(in: window).x
        let distance = sign > 0 ? x - window.bounds.minX : window.bounds.maxX - x
        guard distance >= travel else { return false }
        if gestureRecognizer === closeTap {
            tapOwner = (current.hostID, current.paneID, ObjectIdentifier(window))
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let dragState, let current = readContext?(), current.window === attachedWindow,
              !dragState.isDragging, dragState.settlementID == nil else { return false }
        if gestureRecognizer === closeTap {
            return dragState.isOpen && current.allowsClosing && sameOwner(tapOwner)
        }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        var direction = pan.velocity(in: current.window)
        if gestureRecognizer === edge {
            guard !dragState.isOpen, current.allowsOpening, sameOwner(edgeTouchOwner) else { return false }
            if direction == .zero { direction = edgeDisplacement(pan, in: current.window) }
            // UIKit may ask before either motion sample exists: admit provisionally and
            // let the changed path wait for real horizontal motion (:260-269).
            if direction == .zero { return true }
        }
        guard direction.x.isFinite, direction.y.isFinite, abs(direction.x) > abs(direction.y) * 1.1 else {
            return false
        }
        return gestureRecognizer === edge ? (!dragState.isOpen && current.allowsOpening && direction.x * sign > 0)
            : (dragState.isOpen && current.allowsClosing && direction.x * sign < 0)
    }

    private func edgeDisplacement(_ pan: UIPanGestureRecognizer, in window: UIWindow) -> CGPoint {
        guard let origin = edgeTouchOrigin else { return .zero }
        let point = pan.location(in: window)
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// :288-312. Window-level recognisers must say which content gestures lose to them,
    /// or a system back swipe or a horizontal list wins the same touch.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard otherGestureRecognizer !== edge, otherGestureRecognizer !== reverse,
              otherGestureRecognizer !== closeTap,
              !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer),
              let dragState, !dragState.isDragging, dragState.settlementID == nil,
              let current = readContext?(), current.window === attachedWindow,
              let otherView = otherGestureRecognizer.view, otherView.window === current.window else { return false }
        if gestureRecognizer === edge {
            return !dragState.isOpen && current.allowsOpening
                && sameOwner(edgeTouchOwner)
                && otherView.isDescendant(of: current.window)
        }
        if gestureRecognizer === closeTap {
            return dragState.isOpen && current.allowsClosing && current.containsClosingView(otherView)
        }
        return false
    }

    // MARK: - Driving progress

    @objc private func changed(_ recognizer: UIGestureRecognizer) {
        guard let dragState else { return }
        defer {
            if recognizer === edge,
               recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                edgeTouchOwner = nil
                edgeTouchOrigin = nil
                edgeRejected = false
            }
        }
        if recognizer === closeTap {
            if recognizer.state == .ended, sameOwner(tapOwner), readContext?()?.allowsClosing == true {
                dragState.close()
            }
            tapOwner = nil
            return
        }
        guard let pan = recognizer as? UIPanGestureRecognizer, let current = readContext?(),
              current.window === attachedWindow else {
            if dragState.gestureID == capturedGestureID, capturedGestureID != nil { dragState.reset() }
            captured = nil
            capturedGestureID = nil
            return
        }
        if recognizer === edge {
            changedEdge(pan, context: current, state: dragState)
            return
        }
        let allowed = current.allowsClosing
        let displacement = pan.translation(in: current.window).x
        switch pan.state {
        case .began:
            guard dragState.begin(eligible: allowed) else { return }
            captured = (current.hostID, current.paneID, ObjectIdentifier(current.window))
            capturedGestureID = dragState.gestureID
            dragState.drag(displacement: Double(displacement * sign), travel: Double(travel))
        case .changed, .ended:
            guard let capturedGestureID, dragState.gestureID == capturedGestureID else {
                captured = nil
                self.capturedGestureID = nil
                return
            }
            guard sameOwner(captured), allowed else {
                dragState.reset()
                captured = nil
                self.capturedGestureID = nil
                return
            }
            // A release can carry the last displacement without a changed callback.
            dragState.drag(displacement: Double(displacement * sign), travel: Double(travel))
            if pan.state == .ended {
                dragState.end(velocity: Double(pan.velocity(in: current.window).x * sign),
                              travel: Double(travel), cancelled: false)
                captured = nil
                self.capturedGestureID = nil
            }
        case .cancelled, .failed:
            if dragState.gestureID == capturedGestureID, capturedGestureID != nil {
                dragState.end(velocity: 0, travel: Double(travel), cancelled: true)
            }
            captured = nil
            capturedGestureID = nil
        default: break
        }
    }

    /// :374-409. The edge recogniser has no began sample to trust: it measures from the
    /// touch that was admitted, in window coordinates, so the surface moving under the
    /// finger does not feed back into the number.
    private func changedEdge(_ pan: UIPanGestureRecognizer, context: WorkspaceSidebarNativeContext,
                             state: SidebarDragState) {
        switch pan.state {
        case .began, .changed, .ended:
            guard !edgeRejected else { return }
            guard sameOwner(edgeTouchOwner), context.allowsOpening, !state.isOpen else {
                rejectEdge(state)
                return
            }
            let delta = edgeDisplacement(pan, in: context.window)
            guard delta.x.isFinite, delta.y.isFinite else { rejectEdge(state); return }
            if capturedGestureID == nil {
                guard delta != .zero else { return }
                guard abs(delta.x) > abs(delta.y) * 1.1, delta.x * sign > 0,
                      state.begin(eligible: true) else { rejectEdge(state); return }
                captured = (context.hostID, context.paneID, ObjectIdentifier(context.window))
                capturedGestureID = state.gestureID
            }
            guard state.gestureID == capturedGestureID, sameOwner(captured) else {
                rejectEdge(state)
                return
            }
            state.drag(displacement: Double(delta.x * sign), travel: Double(travel))
            if pan.state == .ended {
                state.end(velocity: Double(pan.velocity(in: context.window).x * sign),
                          travel: Double(travel), cancelled: false)
                captured = nil
                capturedGestureID = nil
            }
        case .cancelled, .failed:
            if state.gestureID == capturedGestureID, capturedGestureID != nil {
                state.end(velocity: 0, travel: Double(travel), cancelled: true)
            }
            captured = nil
            capturedGestureID = nil
        default: break
        }
    }

    private func rejectEdge(_ state: SidebarDragState) {
        edgeRejected = true
        if state.gestureID == capturedGestureID, capturedGestureID != nil { state.reset() }
        captured = nil
        capturedGestureID = nil
    }
}

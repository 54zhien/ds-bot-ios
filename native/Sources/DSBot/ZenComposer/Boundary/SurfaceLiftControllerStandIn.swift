// deviation: host-provided stand-in for Zen-Agent App/Workspace/SurfaceLiftController.swift:7
// and App/Workspace/WorkspaceSurfaceView.swift:4-9 (its environment key); zen UI stays verbatim.
//
// zen's controller owns the pane-to-card Lift gesture over the workspace surface. This app hosts
// the composer inside the chat page and has no workspace surface, so the handle exists only to
// satisfy the type: it arms nothing, drags nothing and settles nothing. Every member returns the
// refusing answer, which is the same outcome as zen passing nil.

import SwiftUI

@MainActor
final class SurfaceLiftController {
    private(set) var state = SurfaceLiftState()

    func canArm(_ input: SurfaceLiftEligibility) -> Bool { false }

    func arm(_ input: SurfaceLiftEligibility, conversationID: String? = nil) -> Bool { false }

    func drag(displacement: CGSize, eligibility: SurfaceLiftEligibility,
              locationInWindow: CGPoint? = nil) -> Bool { false }

    func end(cancelled: Bool = false, animated: Bool = true) -> SurfaceLiftState.Settlement? { nil }

    func invalidate() {}

    func setSelection(sourceID: String, active: Bool) {}
}

private struct SurfaceLiftControllerKey: EnvironmentKey {
    static let defaultValue: SurfaceLiftController? = nil
}

extension EnvironmentValues {
    var surfaceLiftController: SurfaceLiftController? {
        get { self[SurfaceLiftControllerKey.self] }
        set { self[SurfaceLiftControllerKey.self] = newValue }
    }
}

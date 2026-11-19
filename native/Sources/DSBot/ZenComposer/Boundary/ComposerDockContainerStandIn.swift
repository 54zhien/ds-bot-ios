// deviation: host-provided stand-in for Zen-Agent App/Workspace/WorkspaceComposerDock.swift:183;
// zen UI stays verbatim.
//
// zen's dock is the real container that lays the composer at the workspace bottom.
// ComposerHostView.swift:471 only probes `superview is ComposerDockContainer`, so the marker type
// is enough here. We never put the host inside one: that branch is always false for us, and the
// bottom-fade viewport falls through to the plain bounds path.

import UIKit

final class ComposerDockContainer: UIView {}

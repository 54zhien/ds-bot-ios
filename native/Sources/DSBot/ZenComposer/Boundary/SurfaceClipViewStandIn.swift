// deviation: host-provided stand-in for Zen-Agent App/Workspace/ConversationSurfaceHost.swift:1043;
// zen UI stays verbatim.
//
// zen's clip view is the real card that clips a lifted conversation surface.
// ComposerHostView.swift:482 only probes `as? SurfaceClipView` while walking its ancestors, so the
// marker type is enough here. Our host never sits inside one: the loop finds nothing, that branch
// is always false, and the bottom-fade viewport stays at the composer's own bounds.

import UIKit

final class SurfaceClipView: UIView {}

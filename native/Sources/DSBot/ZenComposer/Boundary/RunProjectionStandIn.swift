// deviation: host-provided stand-in for Zen-Agent App/Runtime/RunProjection.swift:3; zen UI stays
// verbatim.
//
// zen derives this from its own run store. ComposerContextAction.swift:30/38/39 reads three
// members only: `.isActive`, `.runID` and `.canStop`. The app's relay-backed run state fills this
// struct at the wiring layer, so no `RunState`, `EndReason` or persistence code is pulled in here.

struct RunProjection: Equatable, Sendable {
    let runID: String
    let isActive: Bool
    let canStop: Bool
}

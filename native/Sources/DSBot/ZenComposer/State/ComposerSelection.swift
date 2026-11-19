// ported verbatim from Zen-Agent App/Conversation/ComposerSelection.swift (4 lines)
// Needed by ComposerDraftState:13; the first layer named this type before the
// type itself was ported, so the tree did not compile until it arrived here.
/// Draft 内的选择范围。空范围表示光标。
struct ComposerSelection: Equatable, Sendable {
    let range: Range<Int>
}

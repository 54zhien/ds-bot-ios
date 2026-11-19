// deviation: host-provided stand-in for Zen-Agent App/Conversation/ConversationTimeline.swift:66
// and App/Persistence/Records.swift:312; zen UI stays verbatim.
//
// QuoteShelfView.swift:15-23 reads four members off this pair: `.id`, `.snapshot`,
// `.sourceConversationID`, `.sourceMessageID`, `.sourcePartID` and `.sourceIsAvailable`. In zen
// the reference is the GRDB record `MessageQuoteReferenceRecord`, and reaching it through
// ConversationTimeline pulls Records.swift (486 lines, `import GRDB`) plus RequestConfigSeed
// (200) - a dependency this project does not have and does not want. The two shapes below keep
// the shelf verbatim and move the app's own quote model in at the wiring layer.

struct MessageQuoteReferenceRecord: Equatable, Sendable {
    let id: String
    let snapshot: String
    let sourceConversationID: String
    let sourceMessageID: String
    let sourcePartID: String
}

struct QuoteReferencePresentation: Equatable, Sendable {
    let reference: MessageQuoteReferenceRecord
    let sourceIsAvailable: Bool
}

// ported verbatim from Zen-Agent App/Typography/Typography.swift:7-17 (11 lines)
// renamed TypographyRole -> ZenTypographyRole to avoid colliding with DSBot's own names.
enum ZenTypographyRole: CaseIterable {
    case interfaceTitle
    case interfaceBody
    case interfaceCaption
    case conversationPrompt
    case conversationBody
    case conversationHeading
    case conversationQuote
    case codeInline
    case codeBlock
}

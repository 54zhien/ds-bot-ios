import Foundation

/// Rows that arrived as message events and wait for the read that confirms them.
/// The React Native chat appends the event's item to the page and lets the next
/// read replace it (Chat.tsx:252-261); this buffer holds the same rows here so the
/// list can show them before the read lands.
///
/// A row whose sourceKey the loaded page already carries drops out instead of
/// drawing twice: the sourceKey leads with the sequence, the very field RN's own
/// dedup checks, so the two rules cannot disagree.
struct ChatFeedBuffer {
    private(set) var rows: [ChatRow] = []

    /// One event's item, or nil when it names another chat, carries no item, or
    /// repeats one already pending. Returns the row to show until the read lands.
    mutating func feed(_ data: JSONValue, for sessionID: String?) -> ChatRow? {
        guard let sessionID,
              data["sessionId"]?.stringValue == sessionID,
              let item = data["item"], item != .null else { return nil }
        let row = ChatRow(item)
        if rows.contains(where: { $0.sourceKey == row.sourceKey }) { return nil }
        rows.append(row)
        return row
    }

    /// The rows worth showing next to what is already loaded. A row the loaded page
    /// already carries means the poll won the race: the confirmed one wins.
    func pending(among loaded: [ChatRow]) -> [ChatRow] {
        rows.filter { row in !loaded.contains { $0.sourceKey == row.sourceKey } }
    }

    /// The read that landed replaces everything the events brought.
    mutating func clear() {
        rows = []
    }
}

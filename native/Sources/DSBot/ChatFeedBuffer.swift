import Foundation

/// Rows that arrived as message events and wait for the read that confirms them.
/// The React Native chat appends the event's item to the page and lets the next
/// read replace it (Chat.tsx:252-261); this buffer holds the same rows here so the
/// list can show them before the read lands.
///
/// Dedup keys on the chat plus its sequence, the field RN's own check reads
/// (Chat.tsx:255). The row's text is deliberately not part of the key: an event
/// that carries the same sequence with different wording is the same message.
struct ChatFeedBuffer {
    private(set) var rows: [ChatRow] = []
    private var seen: Set<String> = []

    private static func key(_ sessionID: String, _ item: JSONValue, _ row: ChatRow) -> String {
        if let seq = item["seq"]?.intValue { return "\(sessionID)|\(seq)" }
        return "\(sessionID)|key:\(row.sourceKey)"
    }

    /// One event's item, or nil when it names another chat, carries no item, or
    /// repeats one already pending. Returns the row to show until the read lands.
    mutating func feed(_ data: JSONValue, for sessionID: String?) -> ChatRow? {
        guard let sessionID,
              data["sessionId"]?.stringValue == sessionID,
              let item = data["item"], item != .null else { return nil }
        let row = ChatRow(item)
        let key = ChatFeedBuffer.key(sessionID, item, row)
        guard seen.insert(key).inserted else { return nil }
        rows.append(row)
        return row
    }

    /// The rows worth showing next to what is already loaded. A row the loaded page
    /// already carries means the poll won the race: the confirmed one wins.
    func pending(among loaded: [ChatRow]) -> [ChatRow] {
        let carried = Set(loaded.map { $0.sourceKey })
        return rows.filter { !carried.contains($0.sourceKey) }
    }

    /// The read that landed replaces everything the events brought.
    mutating func clear() {
        rows = []
        seen = []
    }
}

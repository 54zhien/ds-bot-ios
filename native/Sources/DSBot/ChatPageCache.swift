import Foundation

/// The newest page of a conversation, kept in memory only: coming back to a Bot or a
/// group shows its messages on the first frame while a fresh read brings anything new.
/// The React Native app keeps the same pages (team/chat-cache.ts), a fixed count,
/// least recently used evicted, and nothing here is written to disk.
final class ChatPageCache {
    struct Entry {
        let older: [ChatRow]
        let rows: [ChatRow]
        let cursor: JSONValue?
        let sessionID: String?
        let fetchedAt: Date
    }

    /// `<host>:<kind>:<id>`, the shape the chat key writes, so both sides of the
    /// cache agree without the view controller being involved.
    static func key(host: String?, target: ChatTarget) -> String? {
        guard let host, !host.isEmpty else { return nil }
        return "\(host):\(target.kind == .room ? "room" : "bot"):\(target.id)"
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let limit: Int
    private let maxAge: TimeInterval
    private let now: () -> Date

    init(
        limit: Int = 16,
        maxAge: TimeInterval = 5 * 60,
        now: @escaping () -> Date = { Date() }
    ) {
        self.limit = max(1, limit)
        self.maxAge = maxAge
        self.now = now
    }

    /// A store refreshes the page and moves the chat to the most recent end; the
    /// least recently used chat beyond the limit is dropped.
    func store(key: String, older: [ChatRow], rows: [ChatRow], cursor: JSONValue?, sessionID: String?) {
        guard !key.isEmpty else { return }
        touch(key)
        entries[key] = Entry(
            older: older, rows: rows, cursor: cursor, sessionID: sessionID, fetchedAt: now()
        )
        while order.count > limit {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    /// A hit refreshes the use order and hands the page back. A page older than the
    /// age limit is dropped instead of shown: half-old rows flash worse than a wait.
    func retrieve(_ key: String) -> Entry? {
        guard let entry = entries[key] else { return nil }
        if now().timeIntervalSince(entry.fetchedAt) > maxAge {
            entries.removeValue(forKey: key)
            order.removeAll { $0 == key }
            return nil
        }
        touch(key)
        return entry
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

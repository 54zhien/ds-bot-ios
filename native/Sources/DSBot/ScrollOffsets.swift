import Foundation

/// Chat.tsx:57-66 keeps each chat's reading position in memory, capped at fifty
/// chats, and returns to it when the chat comes back. Nothing here is written to
/// disk, and the page cache is deliberately left alone: it holds page data, and a
/// reading position is not part of it.
struct ScrollOffsetBook {
    let capacity: Int
    private var order: [String] = []
    private var offsets: [String: CGFloat] = [:]

    init(capacity: Int = 50) {
        self.capacity = capacity
    }

    /// Recording a chat again makes it the newest, as a Map does when its key is
    /// deleted and set again; the oldest chat falls out at the cap.
    mutating func keep(_ offset: CGFloat, for key: String) {
        order.removeAll { $0 == key }
        order.append(key)
        offsets[key] = offset
        while order.count > capacity {
            let oldest = order.removeFirst()
            offsets.removeValue(forKey: oldest)
        }
    }

    /// A chat with no recorded position opens at the newest message.
    func offset(for key: String) -> CGFloat? {
        offsets[key]
    }
}

/// A position waiting for the chat it belongs to. The restore must land before
/// the bottom-follow judgement, or the chat snaps to the newest row and the
/// restore never shows; carrying the key along is what keeps a position from
/// being handed to a different chat.
struct PendingScroll: Equatable {
    private(set) var key: String?
    private(set) var offset: CGFloat?

    mutating func expect(_ offset: CGFloat?, for key: String?) {
        self.key = offset == nil ? nil : key
        self.offset = offset
    }

    /// Answers for the chat it was recorded for and forgets either way, so a
    /// position taken from one chat can never be applied to the next.
    mutating func take(for chatKey: String?) -> CGFloat? {
        defer { key = nil; offset = nil }
        guard let key, let offset, key == chatKey else { return nil }
        return offset
    }
}

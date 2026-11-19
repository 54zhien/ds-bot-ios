import Foundation

/// ShellB.tsx keeps the last chat under 'dsbot.lastChat' as {kind, id}; the
/// native side holds the same key and value shape, so the two builds agree on
/// what a saved chat is. The target's display name is never persisted: a
/// renamed Bot keeps its saved entry, and the caller refills the name from the
/// team state it already holds.
enum LastChatStore {
    static let key = "dsbot.lastChat"

    /// ShellB.tsx:167: every target switch saves the chat the user opened.
    static func save(_ target: ChatTarget) {
        let entry: [String: String] = ["kind": target.kind == .bot ? "bot" : "room", "id": target.id]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: key)
    }

    /// The saved target for launch. A value that does not parse counts as no
    /// saved chat (ShellB.tsx:328) and is left alone for the next save to
    /// overwrite.
    static func load() -> ChatTarget? {
        guard let text = UserDefaults.standard.string(forKey: key),
              let data = text.data(using: .utf8),
              let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let id = entry["id"], !id.isEmpty
        else { return nil }
        switch entry["kind"] {
        case "bot": return ChatTarget(kind: .bot, id: id, name: "")
        case "room": return ChatTarget(kind: .room, id: id, name: "")
        default: return nil
        }
    }

    /// ShellB.tsx:175-180: a saved chat the team no longer has is dropped and
    /// the Main-Bot fallback takes over. The caller's `stillKnown` decides from
    /// the team state in hand; a target that fails it is cleared here.
    static func restore(stillKnown: (ChatTarget) -> Bool) -> ChatTarget? {
        guard let saved = load() else { return nil }
        guard stillKnown(saved) else {
            clear()
            return nil
        }
        return saved
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

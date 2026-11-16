import Foundation

/// The mobile API returns an envelope around every endpoint's value.
enum BotAPI {
    static func call(
        _ endpoint: String, payload: JSONValue = .object([:]), on session: LinkSession
    ) async throws -> JSONValue {
        let reply = try await session.call("bot", params: .object([
            "endpoint": .string(endpoint),
            "payload": payload,
        ]))
        guard reply["ok"] == .bool(true), let value = reply["value"] else {
            let message = reply["error"]?["message"]?.stringValue ?? "The computer could not load this chat."
            throw NSError(domain: "DSBot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return value
    }
}

struct ChatPage {
    let sessionID: String?
    let items: [ChatRow]
    let cursor: JSONValue?

    init(_ value: JSONValue) {
        sessionID = value["sessionId"]?.stringValue
        if case .array(let items)? = value["items"] {
            self.items = items.map(ChatRow.init)
        } else {
            items = []
        }
        cursor = value["cursor"]
    }
}

struct ChatRow {
    let kind: String
    let name: String
    let text: String
    let time: Date?

    init(_ value: JSONValue) {
        kind = value["kind"]?.stringValue ?? "event"
        name = value["name"]?.stringValue ?? ""
        let body = value["text"]?.stringValue ?? ""
        let parts: [String]
        if case .array(let texts)? = value["texts"] {
            parts = texts.compactMap(\.stringValue).filter { !$0.isEmpty }
        } else {
            parts = []
        }
        let title = value["title"]?.stringValue ?? value["question"]?["question"]?.stringValue ?? ""
        let imageCount = value["images"]?.intValue ?? 0
        let base = !parts.isEmpty ? parts.joined(separator: "\n\n") : !body.isEmpty ? body : title
        if imageCount > 0 {
            text = base.isEmpty ? "Photos: \(imageCount)" : "\(base)\nPhotos: \(imageCount)"
        } else if !base.isEmpty {
            text = base
        } else {
            switch kind {
            case "steps": text = "Work steps"
            case "view": text = "View"
            case "answer": text = "Answer"
            case "closed": text = "Answered"
            case "divider": text = "Earlier conversation"
            default: text = kind.capitalized
            }
        }
        if case .number(let milliseconds)? = value["time"] {
            time = Date(timeIntervalSince1970: milliseconds / 1_000)
        } else {
            time = nil
        }
    }

    var isUser: Bool { kind == "user" }
    var isNotice: Bool { kind == "event" || kind == "divider" || kind == "relay" }
    var author: String {
        if isUser { return "You" }
        if !name.isEmpty { return name }
        if kind == "bot" || kind == "post" { return "Bot" }
        return kind.capitalized
    }
}

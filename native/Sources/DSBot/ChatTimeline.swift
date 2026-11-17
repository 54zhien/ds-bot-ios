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
            let code = reply["error"]?["code"]?.stringValue
            let reason = code.map { "\($0): \(message)" } ?? message
            throw NSError(domain: "DSBot", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
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

struct ChatFile {
    let title: String
    let value: JSONValue
}

struct ChatRow {
    let kind: String
    let name: String
    let text: String
    let messageText: String
    let imageCount: Int
    let imageRefs: [String]
    let files: [ChatFile]
    let stepSummary: String?
    let stepDetails: [String]
    let time: Date?
    let sourceKey: String
    let localID: UUID?
    let failed: Bool
    let failureReason: String?

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
        if case .array(let refs)? = value["imageRefs"] {
            imageRefs = refs.compactMap { $0["attachmentId"]?.stringValue }
        } else { imageRefs = [] }
        var attached: [ChatFile] = []
        if case .array(let references)? = value["files"] {
            attached = references.compactMap { reference in
                guard let name = reference["name"]?.stringValue else { return nil }
                return ChatFile(title: name, value: reference)
            }
        }
        let direct = value["file"]
        let whole = direct?["attachmentId"]?.stringValue != nil ? direct : value["whole"]?["file"]
        if let whole, whole["attachmentId"]?.stringValue != nil {
            attached.append(ChatFile(title: "Read full message", value: whole))
        }
        files = attached
        if kind == "steps" {
            let tools: [JSONValue]
            if case .array(let entries)? = value["tools"] { tools = entries } else { tools = [] }
            let count = tools.count
            let seconds = (value["ms"]?.intValue ?? 0) / 1_000
            stepSummary = "Used \(count) \(count == 1 ? "tool" : "tools")"
                + (seconds > 0 ? " · thought for \(seconds)s" : "")
            stepDetails = tools.map { tool in
                let label = tool["label"]?.stringValue ?? tool["name"]?.stringValue ?? "Tool"
                return label + (tool["ok"] == .bool(false) ? " — failed" : "")
            }
        } else {
            stepSummary = nil
            stepDetails = []
        }
        let refCount = imageRefs.count
        let count = refCount > 0 ? refCount : value["images"]?.intValue ?? 0
        imageCount = count
        let base = !parts.isEmpty ? parts.joined(separator: "\n\n") : !body.isEmpty ? body : title
        messageText = base
        var display = base
        if kind == "closed" {
            let prompt = value["question"]?["question"]?.stringValue ?? title
            let state = value["closed"]?.stringValue == "replied" ? "Answered by message" : "Dismissed"
            display = prompt.isEmpty ? state : "\(prompt)\n\(state)"
        } else if kind == "answer", case .array(let answers)? = value["answers"] {
            let responses = answers.compactMap { answer -> String? in
                let selected = answer["selected"]?.stringArrayValue ?? []
                let custom = answer["custom"]?.stringValue ?? ""
                let reply = (selected + (custom.isEmpty ? [] : [custom])).joined(separator: ", ")
                return reply.isEmpty ? nil : reply
            }
            if !responses.isEmpty { display = responses.joined(separator: "\n") }
        }
        if count > 0 {
            text = display.isEmpty ? "Photos: \(count)" : "\(display)\nPhotos: \(count)"
        } else if !display.isEmpty {
            text = display
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
        let sequence = value["seq"]?.intValue.map { String($0) } ?? ""
        let timestamp = value["time"]?.intValue.map { String($0) } ?? ""
        let turn = value["turn"]?.intValue.map { String($0) } ?? ""
        sourceKey = "\(sequence)|\(timestamp)|\(turn)|\(kind)|\(text)"
        localID = nil
        failed = false
        failureReason = nil
    }

    init(localID: UUID, text: String, imageCount: Int, failureReason: String?) {
        kind = "user"
        name = ""
        messageText = text
        self.imageCount = imageCount
        imageRefs = []
        files = []
        stepSummary = nil
        stepDetails = []
        self.text = imageCount == 0 ? text : text.isEmpty ? "Photos: \(imageCount)" : "\(text)\nPhotos: \(imageCount)"
        time = Date()
        sourceKey = "local-\(localID.uuidString)"
        self.localID = localID
        failed = failureReason != nil
        self.failureReason = failureReason
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

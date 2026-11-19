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
            let message = reply["error"]?["message"]?.stringValue ?? NativeLanguage.text("The computer could not load this chat.")
            let wire = reply["error"]?["code"]?.stringValue
            throw TransportError(TransportError.code(forWire: wire), message, wireCode: wire)
        }
        return value
    }
}

struct ChatPage {
    let sessionID: String?
    let items: [ChatRow]
    let cursor: JSONValue?

    init(_ value: JSONValue, inRoom: Bool = false) {
        sessionID = value["sessionId"]?.stringValue
        if case .array(let items)? = value["items"] {
            self.items = items.compactMap { item in
                if item["kind"]?.stringValue == "relay", ChatEventText.relay(item["reply"]) == nil { return nil }
                var row = ChatRow(item)
                row.inRoom = inRoom
                return row
            }
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

enum ChatEventText {
    static func round(name: String, event: String?, text: String?, code: String?) -> String? {
        guard let event else { return nil }
        let values = ["name": name, "reason": text ?? code ?? "", "text": text ?? ""]
        switch event {
        case "failed": return NativeLanguage.text("{name} could not answer: {reason}", values)
        case "lookup": return NativeLanguage.text(text == nil || text == ""
            ? "{name} looked up its own chat" : "{name} looked up its own chat for “{text}”", values)
        case "missed": return NativeLanguage.text("{name} didn't answer in time", values)
        case "admin-passed": return NativeLanguage.text("{name} did not answer or call anyone; call a member with @Name", values)
        case "resumed": return NativeLanguage.text("{name} was cut off by a restart and picked its work back up", values)
        case "cut": return NativeLanguage.text("{name} was cut off by a restart again and stopped", values)
        case "approval": return NativeLanguage.text("{name} paused for your approval", values)
        case "working": return NativeLanguage.text("{name} started on it", values)
        case "folder", "schedule": return text ?? ""
        case "stopped": return NativeLanguage.text("You stopped {name}'s work", values)
        case "done": return NativeLanguage.text("{name} finished its work", values)
        default: return nil
        }
    }

    static func relay(_ reply: JSONValue?) -> String? {
        guard let reply else { return nil }
        let kind = reply["kind"]?.stringValue ?? reply["event"]?.stringValue
        let name = reply["name"]?.stringValue ?? NativeLanguage.text("a Bot")
        if kind == "paused" {
            let names = (reply["names"]?.stringArrayValue ?? []).joined(separator: NativeLanguage.text(" and "))
            let count = reply["count"]?.intValue ?? 0
            if reply["idle"] == .bool(true) {
                let all = ([name] + (reply["names"]?.stringArrayValue ?? []))
                    .joined(separator: NativeLanguage.text(" and "))
                return NativeLanguage.text("{names} went back and forth {count} times without progress and paused. Write here to go on",
                                           ["names": all, "count": String(count)])
            }
            return NativeLanguage.text("Paused after {count} Bot relays. Waiting: {names}",
                                       ["count": String(count), "names": names])
        }
        return round(name: name, event: kind, text: reply["text"]?.stringValue,
                     code: reply["code"]?.stringValue)
    }
}

/// im-platforms.js: the display names a via tag shows. items.tsx:272 uses them
/// as-is, without translating the platform's own name.
enum IMPlatforms {
    static let names = [
        "telegram": "Telegram", "weixin": "WeChat", "feishu": "Feishu / Lark",
        "dingtalk": "DingTalk", "wecom": "WeCom", "qq": "QQ",
        "discord": "Discord", "slack": "Slack",
    ]

    static func name(_ id: String) -> String? { names[id] }
}

/// items.tsx:286-291 draws a room row from its member: the avatar, the name in
/// that member's colour, and an Admin mark on the member who leads the room. The
/// roster lives in the team state rather than in the chat page, so the rows are
/// decorated after they are built.
enum RoomRowData {
    static func decorate(_ rows: inout [ChatRow], bots: [JSONValue], adminBotID: String?) {
        guard !rows.isEmpty else { return }
        var roster: [String: JSONValue] = [:]
        for bot in bots {
            if let id = bot["id"]?.stringValue { roster[id] = bot }
        }
        for index in rows.indices {
            guard let member = rows[index].botID else { continue }
            let bot = roster[member]
            rows[index].memberName = bot?["name"]?.stringValue
            rows[index].memberColor = bot?["color"]?.stringValue
            rows[index].memberAvatar = bot?["avatar"]
            rows[index].isAdmin = adminBotID == member
        }
    }
}

struct ChatRow {
    let kind: String
    let name: String
    let text: String
    let messageText: String
    let imageCount: Int
    let imageRefs: [String]
    let localImageData: [Data]
    let files: [ChatFile]
    let viewRecord: JSONValue?
    /// The settled card this item draws, when it draws one; items.tsx's own branch.
    let settled: SettledCard?
    let stepSummary: String?
    let stepDetails: [String]
    let time: Date?
    /// The IM platform a user message came in over, when it did (parts.js:1799
    /// viaOf reads it from the event's source rpcId).
    let via: String?
    let sourceKey: String
    let localID: UUID?
    let failed: Bool
    let failureReason: String?
    /// True when the next row continues this Bot's run, so this row draws no stamp.
    /// Chat.tsx stampOf puts a run's time on its last bubble only.
    var stampFolded = false
    /// True in a room, where Chat.tsx shows no stamps at all. Set by the page, since
    /// an item's own fields cannot tell a room reply from a one-to-one reply.
    var inRoom = false
    /// The member who spoke, when the item names one; a room post carries it and a
    /// one-to-one reply does not.
    let botID: String?
    /// items.tsx:286-291 draws the member from the roster, so the row keeps what
    /// the team state said: name, colour and avatar, plus whether this member
    /// leads the room. Filled by RoomRowData; the renderer decides what to show.
    var memberName: String?
    var memberColor: String?
    var memberAvatar: JSONValue?
    var isAdmin = false

    /// The roster can answer with a null avatar, which is not a picture. The test
    /// lives here so the renderer asks once instead of writing `== .null` again.
    var hasMemberAvatar: Bool { memberAvatar != nil && memberAvatar != .null }

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
        localImageData = []
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
            attached.append(ChatFile(title: NativeLanguage.text("Read full message"), value: whole))
        }
        files = attached
        if kind == "view", let root = value["view"], root != .null {
            viewRecord = .object(["title": .string(title), "view": root])
        } else { viewRecord = nil }
        settled = SettledCard(item: value)
        if kind == "steps" {
            let tools: [JSONValue]
            if case .array(let entries)? = value["tools"] { tools = entries } else { tools = [] }
            let count = tools.count
            let seconds = (value["ms"]?.intValue ?? 0) / 1_000
            var summary = count == 1
                ? NativeLanguage.text("Used {count} tool", ["count": String(count)])
                : NativeLanguage.text("Used {count} tools", ["count": String(count)])
            if seconds > 0 {
                summary += NativeLanguage.text(" · thought for {seconds}s", ["seconds": String(seconds)])
            }
            stepSummary = summary
            stepDetails = tools.map { tool in
                let label = tool["label"]?.stringValue ?? tool["name"]?.stringValue ?? NativeLanguage.text("Tool")
                return label + (tool["ok"] == .bool(false) ? NativeLanguage.text(" — failed") : "")
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
        if kind == "relay" {
            display = ChatEventText.relay(value["reply"]) ?? ""
        } else if kind == "event" {
            if value["role"]?.stringValue == "paused" {
                display = NativeLanguage.text("Paused after {count} Bot relays. Waiting: {names}",
                                              ["count": String(value["ms"]?.intValue ?? 0), "names": body])
            } else if let event = ChatEventText.round(name: name.isEmpty ? NativeLanguage.text("a Bot") : name,
                                                      event: value["event"]?.stringValue, text: body,
                                                      code: value["code"]?.stringValue) {
                display = event
            } else {
                let role = value["role"]?.stringValue ?? ""
                let action = ["request": "asked for work", "reply": "replied", "report": "reported back",
                              "stopped": "stopped"][role] ?? role
                display = NativeLanguage.text("{name} {event}",
                                              ["name": name.isEmpty ? NativeLanguage.text("a Bot") : name,
                                               "event": NativeLanguage.text(action)])
            }
        } else if kind == "closed" {
            let prompt = value["question"]?["question"]?.stringValue ?? title
            let state = value["closed"]?.stringValue == "replied"
                ? NativeLanguage.text("Answered by message") : NativeLanguage.text("Dismissed")
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
            text = display
        } else if !display.isEmpty {
            text = display
        } else {
            switch kind {
            case "steps": text = NativeLanguage.text("Work steps")
            case "view": text = NativeLanguage.text("View")
            case "answer": text = NativeLanguage.text("Answer")
            case "closed": text = NativeLanguage.text("Answered")
            case "divider": text = NativeLanguage.text("Earlier conversation")
            default: text = kind.capitalized
            }
        }
        if case .number(let milliseconds)? = value["time"] {
            time = Date(timeIntervalSince1970: milliseconds / 1_000)
        } else {
            time = nil
        }
        via = value["via"]?.stringValue
        botID = value["botId"]?.stringValue
        let sequence = value["seq"]?.intValue.map { String($0) } ?? ""
        let timestamp = value["time"]?.intValue.map { String($0) } ?? ""
        let turn = value["turn"]?.intValue.map { String($0) } ?? ""
        sourceKey = "\(sequence)|\(timestamp)|\(turn)|\(kind)|\(text)"
        localID = nil
        failed = false
        failureReason = nil
    }

    init(localID: UUID, text: String, localImageData: [Data], failureReason: String?) {
        kind = "user"
        name = ""
        messageText = text
        imageCount = localImageData.count
        imageRefs = []
        self.localImageData = localImageData
        files = []
        viewRecord = nil
        settled = nil
        stepSummary = nil
        stepDetails = []
        self.text = text
        time = Date()
        via = nil
        botID = nil
        sourceKey = "local-\(localID.uuidString)"
        self.localID = localID
        failed = failureReason != nil
        self.failureReason = failureReason
    }

    var isUser: Bool { kind == "user" }
    var isNotice: Bool { kind == "event" || kind == "divider" || kind == "relay" }

    /// items.tsx:244 photosOnly: photos with no text and no file chips show
    /// bare, without a bubble around them.
    var photosOnly: Bool {
        isUser && messageText.isEmpty && files.isEmpty
            && (!imageRefs.isEmpty || !localImageData.isEmpty)
    }

    /// items.tsx:272 t('via {platform}'), with im-platforms.js's display name
    /// falling back to the raw id the way RN's `?? item.via` does.
    static func viaTagText(_ via: String) -> String {
        NativeLanguage.text("via {platform}", ["platform": IMPlatforms.name(via) ?? via])
    }

    var author: String {
        if isUser { return NativeLanguage.text("You") }
        if !name.isEmpty { return name }
        if kind == "bot" || kind == "post" { return "Bot" }
        return kind.capitalized
    }
}

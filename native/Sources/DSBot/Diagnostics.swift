import Foundation

/// What the phone saw, written down so a report from a device can be read without a
/// debugger attached. A chat that stays empty while the status bar says online is the
/// case this exists for: the reply itself is never shown, only what it was made of.
actor Diagnostics {
    static let shared = Diagnostics()

    private struct Call {
        var method: String
        var endpoint: String?
        var milliseconds: Int
        var errorCode: String?
        var errorMessage: String?
    }

    private static let callLimit = 20
    private static let invalidLimit = 20

    private var calls: [Call] = []
    private var invalidMessages: [String] = []
    private var lastState: [String: Any]?
    private var lastHandshake: [String: Any]?
    private var lastLinkError: String?

    func recordCall(
        method: String, endpoint: String?, milliseconds: Int,
        errorCode: String?, errorMessage: String?, reply: JSONValue?
    ) {
        calls.append(Call(
            method: method, endpoint: endpoint, milliseconds: milliseconds,
            errorCode: errorCode, errorMessage: errorMessage
        ))
        if calls.count > Diagnostics.callLimit { calls.removeFirst(calls.count - Diagnostics.callLimit) }
        // The reply shape is the only way to tell a host that sent nothing from a phone
        // that could not read what it sent.
        if endpoint == "state", let reply {
            lastState = Diagnostics.describeFields(of: reply["value"] ?? reply)
        }
    }

    func recordHandshake(sent: Data, received: Data) {
        lastHandshake = [
            "sent": Diagnostics.jsonObject(sent),
            "received": Diagnostics.jsonObject(received),
        ]
    }

    func recordInvalidMessage(_ text: String) {
        invalidMessages.append(text)
        if invalidMessages.count > Diagnostics.invalidLimit {
            invalidMessages.removeFirst(invalidMessages.count - Diagnostics.invalidLimit)
        }
    }

    func recordLinkError(_ message: String) {
        lastLinkError = message
    }

    /// The whole dump as one JSON text, small enough to paste into a chat.
    func text() -> String {
        var document: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "app": Diagnostics.appInfo(),
            "calls": calls.map { call -> [String: Any] in
                var entry: [String: Any] = [
                    "method": call.method,
                    "ms": call.milliseconds,
                    "ok": call.errorCode == nil,
                ]
                if let endpoint = call.endpoint { entry["endpoint"] = endpoint }
                if let code = call.errorCode { entry["code"] = code }
                if let message = call.errorMessage { entry["message"] = message }
                return entry
            },
        ]
        if let lastState { document["state"] = ["keys": lastState] }
        if let lastHandshake { document["handshake"] = lastHandshake }
        if !invalidMessages.isEmpty { document["invalidMessages"] = invalidMessages }
        if let lastLinkError { document["linkError"] = lastLinkError }
        let scrubbed = Redaction.scrub(document) as? [String: Any] ?? document
        guard let data = try? JSONSerialization.data(
            withJSONObject: scrubbed, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes the dump beside the app's documents and hands back the file it wrote.
    func save() throws -> URL {
        try DiagnosticsStore.write(text())
    }

    // MARK: - Shapes

    private static func appInfo() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        return [
            "version": info?["CFBundleShortVersionString"] as? String ?? "",
            "build": info?["CFBundleVersion"] as? String ?? "",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "language": Locale.current.identifier,
        ]
    }

    /// One level down: for every top-level key, its type and how much it carries. A full
    /// state reply is far too large to paste, and its key names are the part that tells
    /// whether the host sent bots at all.
    private static func describeFields(of value: JSONValue) -> [String: Any] {
        guard case .object(let fields) = value else { return ["(not an object)": describe(value)] }
        var described: [String: Any] = [:]
        for (name, item) in fields { described[name] = describe(item) }
        return described
    }

    private static func describe(_ value: JSONValue) -> [String: Any] {
        switch value {
        case .array(let items): return ["type": "array", "count": items.count]
        case .object(let fields): return ["type": "object", "keys": fields.count]
        case .string(let text): return ["type": "string", "length": text.count]
        case .number: return ["type": "number"]
        case .bool: return ["type": "bool"]
        case .null: return ["type": "null"]
        }
    }

    /// A hello that is not JSON is not written out at all: a broken one could carry a code
    /// in clear text.
    private static func jsonObject(_ data: Data) -> Any {
        guard !data.isEmpty else { return "<empty>" }
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            return "<not JSON, \(data.count) bytes>"
        }
        return Redaction.scrub(value)
    }
}

/// Replaces the values of the protocol's secret fields wherever they appear, so a dump can
/// be pasted into a chat without leaking a pairing code or a session key.
enum Redaction {
    /// Nothing under these names is ever written down.
    static let sensitiveNames: Set<String> = [
        "accessToken", "pairingCode", "ciphertext", "identityKey", "privateKey", "secret", "token",
    ]

    static func scrub(_ value: Any, key: String? = nil) -> Any {
        if let key, Redaction.sensitiveNames.contains(key) { return "<redacted>" }
        if let dictionary = value as? [String: Any] {
            var scrubbed: [String: Any] = [:]
            for (name, item) in dictionary { scrubbed[name] = scrub(item, key: name) }
            return scrubbed
        }
        if let array = value as? [Any] { return array.map { scrub($0, key: key) } }
        return value
    }
}

/// Where the dumps live: Documents/diagnostics, one file per save.
enum DiagnosticsStore {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics", isDirectory: true)
    }

    static func write(_ text: String) throws -> URL {
        let folder = DiagnosticsStore.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = formatter.string(from: Date()) + ".json"
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// The newest dump, taken from the folder rather than from a stored name so a file
    /// deleted in Files.app stops being reported.
    static func latest() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let newest = names.filter({ $0.hasSuffix(".json") }).max() else { return nil }
        return folder.appendingPathComponent(newest)
    }
}

import Foundation

/// Wire constants shared with link/src/frames.ts. Changing any of these is a
/// protocol change, not a refactor.
public enum ProtocolLimits {
    public static let version = 1
    public static let linkPath = "/v1/link"
    public static let relayCapability = "transport.relay"
    public static let maxControlFrameBytes = 64 * 1024
    public static let maxRelayFrameBytes = 1024 * 1024
    public static let secureFragmentChunkBytes = 48 * 1024
    public static let maxSecureMessageBytes = 4 * 1024 * 1024
}

/// Every control frame the Relay speaks, spelled exactly as the TS side writes it.
public enum ControlFrameType: String, Codable, Sendable, CaseIterable {
    case hello
    case helloAck = "hello.ack"
    case connectRequest = "connect.request"
    case connectIncoming = "connect.incoming"
    case connectAccepted = "connect.accepted"
    case connectRejected = "connect.rejected"
    case secureHandshake = "secure.handshake"
    case relay
    case ping
    case pong
    case error
}

/// Remote messages ride inside the encrypted channel; the envelope shape is the same.
public enum MessageType: String, Codable, Sendable, CaseIterable {
    case rpcRequest = "rpc.request"
    case rpcResponse = "rpc.response"
    case rpcError = "rpc.error"
    case event
}

public struct TransportError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    public enum Code: String, Sendable {
        case invalidFrame
        case frameTooLarge
        case invalidBase64
        case notPaired
        case pairingRejected
        case timeout
        case notConnected
        case hostOffline
        case serverUnreachable
    }

    public let code: Code
    public let message: String
    /// The code the host or the Server actually sent, kept apart from the message so
    /// the screen can show words while the diagnostics keep the exact wire value.
    public let wireCode: String?

    public init(_ code: Code, _ message: String, wireCode: String? = nil) {
        self.code = code
        self.message = message
        self.wireCode = wireCode
    }

    /// The wire names both error paths send, mapped once: RelayTransport rejection
    /// frames and RpcClient error replies share it.
    public static func code(forWire wire: String?) -> Code {
        switch wire {
        case "NOT_PAIRED": return .notPaired
        case "PAIRING_REJECTED": return .pairingRejected
        case "HOST_OFFLINE": return .hostOffline
        case "SERVER_UNREACHABLE": return .serverUnreachable
        default: return .invalidFrame
        }
    }

    public var description: String { "\(code.rawValue): \(message)" }
    // The screen reads errorDescription, and it reads words; the raw code and message
    // stay in the diagnostics dump, which is the only place they are useful.
    public var errorDescription: String? { userText }
}

/// Payloads are JSON literals on the wire; unknown fields are kept so a newer host
/// can add one without breaking the phone.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw TransportError(.invalidFrame, "Unsupported JSON value in a control frame payload.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .number(let value) = self, value.rounded() == value { return Int(value) }
        return nil
    }

    public var stringArrayValue: [String]? {
        guard case .array(let items) = self else { return nil }
        let strings = items.compactMap { $0.stringValue }
        return strings.count == items.count ? strings : nil
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }
}

// MARK: - Ordered wire text

/// The wire order is the TS literal order, and Foundation's JSONEncoder does not
/// guarantee one. These frames are assembled by hand instead, key by key, so the
/// bytes match link-test-vectors/frames.json exactly.
public enum JSONText {
    public static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    public static func int(_ value: Int) -> String { String(value) }
    public static func bool(_ value: Bool) -> String { value ? "true" : "false" }

    public static func render(_ json: JSONValue) -> String {
        switch json {
        case .null: return "null"
        case .bool(let flag): return bool(flag)
        case .number(let number):
            if number.rounded() == number, number.magnitude < 9_007_199_254_740_992 {
                return String(Int(number))
            }
            return String(number)
        case .string(let text): return string(text)
        case .array(let items): return "[" + items.map { render($0) }.joined(separator: ",") + "]"
        case .object(let fields): return "{" + fields.map { string($0.key) + ":" + render($0.value) }.joined(separator: ",") + "}"
        }
    }
}

/// Builds one JSON object in the order the fields are added.
public struct OrderedObject {
    private var parts: [String] = []

    public init() {}

    public mutating func add(_ key: String, _ text: String) {
        parts.append(JSONText.string(key) + ":" + text)
    }

    public mutating func addIfPresent(_ key: String, _ value: String?) {
        guard let value else { return }
        add(key, JSONText.string(value))
    }

    public var text: String { "{" + parts.joined(separator: ",") + "}" }
}

/// A payload that knows its own field order. Every type the phone sends conforms.
public protocol WirePayload: Sendable {
    var wireJSON: String { get }
}

extension HelloPayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("role", JSONText.string(role))
        object.add("deviceId", JSONText.string(deviceId))
        object.add("identityKey", JSONText.string(identityKey))
        object.add("accessToken", JSONText.string(accessToken))
        object.add("protocols", "[" + protocols.map { String($0) }.joined(separator: ",") + "]")
        object.add("capabilities", "[" + capabilities.map(JSONText.string).joined(separator: ",") + "]")
        object.addIfPresent("clientVersion", clientVersion)
        return object.text
    }
}

extension ConnectRequestPayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("hostDeviceId", JSONText.string(hostDeviceId))
        return object.text
    }
}

extension ConnectAcceptedPayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("connectionId", JSONText.string(connectionId))
        return object.text
    }
}

extension RelayPayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("connectionId", JSONText.string(connectionId))
        object.add("targetDeviceId", JSONText.string(targetDeviceId))
        object.add("counter", JSONText.int(counter))
        object.add("ciphertext", JSONText.string(ciphertext))
        return object.text
    }
}

extension SecureHandshakePayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("connectionId", JSONText.string(connectionId))
        object.add("targetDeviceId", JSONText.string(targetDeviceId))
        object.add("step", JSONText.int(step))
        object.add("data", JSONText.string(data))
        return object.text
    }
}

extension ControlErrorPayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("code", JSONText.string(code))
        object.add("message", JSONText.string(message))
        if let retryable { object.add("retryable", JSONText.bool(retryable)) }
        object.addIfPresent("connectionId", connectionId)
        return object.text
    }
}

/// hello.ack is the Server's shape: `protocol` carries the version, and the rest of
/// the fields are optional on the wire (frames.ts writes them all, but a Server may
/// leave one out).
extension HelloAckPayload: WirePayload {
    public var wireJSON: String {
        var object = OrderedObject()
        object.add("protocol", JSONText.int(protocolVersion))
        object.addIfPresent("serverVersion", serverVersion)
        object.addIfPresent("connectionSessionId", connectionSessionId)
        if let heartbeatIntervalMs { object.add("heartbeatIntervalMs", JSONText.int(heartbeatIntervalMs)) }
        if let maxControlFrameBytes { object.add("maxControlFrameBytes", JSONText.int(maxControlFrameBytes)) }
        if let maxRelayFrameBytes { object.add("maxRelayFrameBytes", JSONText.int(maxRelayFrameBytes)) }
        if let capabilities {
            object.add("capabilities", "[" + capabilities.map(JSONText.string).joined(separator: ",") + "]")
        }
        return object.text
    }
}

/// A pong echoes whatever ping carried, so its field order is whatever arrived.
extension JSONValue: WirePayload {
    public var wireJSON: String { JSONText.render(self) }
}

/// The envelope every control frame and every remote message shares:
/// v, id, type, timestamp, payload — in that order, because that is the order the
/// JSON on the wire has (link-test-vectors/frames.json pins it).
public struct ControlFrame<Payload: Codable & Sendable>: Codable, Sendable {
    public var v: Int
    public var id: String
    public var type: ControlFrameType
    public var timestamp: Int
    public var payload: Payload

    public init(
        type: ControlFrameType,
        payload: Payload,
        id: String = UUID().uuidString,
        timestamp: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.v = ProtocolLimits.version
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }
}

public struct RawControlFrame: Sendable, Equatable {
    public let v: Int
    public let id: String
    public let type: ControlFrameType
    public let timestamp: Int
    public let payload: JSONValue
}

// MARK: - Payloads

public struct HelloPayload: Codable, Sendable, Equatable {
    public var role: String
    public var deviceId: String
    public var identityKey: String
    public var accessToken: String
    public var protocols: [Int]
    public var capabilities: [String]
    public var clientVersion: String?

    public init(
        role: String = "client",
        deviceId: String,
        identityKey: String,
        accessToken: String,
        protocols: [Int] = [ProtocolLimits.version],
        capabilities: [String] = [ProtocolLimits.relayCapability],
        clientVersion: String? = nil
    ) {
        self.role = role
        self.deviceId = deviceId
        self.identityKey = identityKey
        self.accessToken = accessToken
        self.protocols = protocols
        self.capabilities = capabilities
        self.clientVersion = clientVersion
    }
}

public struct HelloAckPayload: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var serverVersion: String?
    public var connectionSessionId: String?
    public var heartbeatIntervalMs: Int?
    public var maxControlFrameBytes: Int?
    public var maxRelayFrameBytes: Int?
    public var capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case serverVersion
        case connectionSessionId
        case heartbeatIntervalMs
        case maxControlFrameBytes
        case maxRelayFrameBytes
        case capabilities
    }

    public init(
        protocolVersion: Int,
        serverVersion: String? = nil,
        connectionSessionId: String? = nil,
        heartbeatIntervalMs: Int? = nil,
        maxControlFrameBytes: Int? = nil,
        maxRelayFrameBytes: Int? = nil,
        capabilities: [String]? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.serverVersion = serverVersion
        self.connectionSessionId = connectionSessionId
        self.heartbeatIntervalMs = heartbeatIntervalMs
        self.maxControlFrameBytes = maxControlFrameBytes
        self.maxRelayFrameBytes = maxRelayFrameBytes
        self.capabilities = capabilities
    }
}

public struct ConnectRequestPayload: Codable, Sendable, Equatable {
    public var hostDeviceId: String
    public init(hostDeviceId: String) { self.hostDeviceId = hostDeviceId }
}

public struct ConnectAcceptedPayload: Codable, Sendable, Equatable {
    public var connectionId: String
    public init(connectionId: String) { self.connectionId = connectionId }
}

public struct RelayPayload: Codable, Sendable, Equatable {
    public var connectionId: String
    public var targetDeviceId: String
    public var counter: Int
    public var ciphertext: String

    public init(connectionId: String, targetDeviceId: String, counter: Int, ciphertext: String) {
        self.connectionId = connectionId
        self.targetDeviceId = targetDeviceId
        self.counter = counter
        self.ciphertext = ciphertext
    }
}

public struct SecureHandshakePayload: Codable, Sendable, Equatable {
    public var connectionId: String
    public var targetDeviceId: String
    public var step: Int
    public var data: String

    public init(connectionId: String, targetDeviceId: String, step: Int, data: String) {
        self.connectionId = connectionId
        self.targetDeviceId = targetDeviceId
        self.step = step
        self.data = data
    }
}

public struct ControlErrorPayload: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var retryable: Bool?
    public var connectionId: String?

    public init(code: String, message: String, retryable: Bool? = nil, connectionId: String? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.connectionId = connectionId
    }
}

// MARK: - Codec

public struct ControlFrameLimits: Sendable, Equatable {
    public var maxControlFrameBytes: Int?
    public var maxRelayFrameBytes: Int?

    public init(maxControlFrameBytes: Int? = nil, maxRelayFrameBytes: Int? = nil) {
        self.maxControlFrameBytes = maxControlFrameBytes
        self.maxRelayFrameBytes = maxRelayFrameBytes
    }
}

/// JSON on the wire, byte-for-byte with what JSON.stringify produces: no spaces,
/// no escaped slashes, keys in declaration order.
public enum FrameCodec {
    public static func encode<Payload: WirePayload & Codable>(
        _ frame: ControlFrame<Payload>,
        limits: ControlFrameLimits = .init()
    ) throws -> String {
        var envelope = OrderedObject()
        envelope.add("v", JSONText.int(frame.v))
        envelope.add("id", JSONText.string(frame.id))
        envelope.add("type", JSONText.string(frame.type.rawValue))
        envelope.add("timestamp", JSONText.int(frame.timestamp))
        envelope.add("payload", frame.payload.wireJSON)
        let text = envelope.text
        try assertSize(text.utf8.count, type: frame.type, limits: limits)
        return text
    }

    public static func decode(_ text: String, limits: ControlFrameLimits = .init()) throws -> RawControlFrame {
        let data = Data(text.utf8)
        guard data.count <= ProtocolLimits.maxRelayFrameBytes else {
            throw TransportError(.frameTooLarge, "Control frame exceeds the relay frame limit.")
        }
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let fields = value as? [String: Any]
        else {
            throw TransportError(.invalidFrame, "Control frame is not a JSON object.")
        }
        guard let version = fields["v"] as? Int, version == ProtocolLimits.version else {
            throw TransportError(.invalidFrame, "Control frame version is not \(ProtocolLimits.version).")
        }
        guard let id = fields["id"] as? String, !id.isEmpty else {
            throw TransportError(.invalidFrame, "Control frame has no id.")
        }
        guard let typeName = fields["type"] as? String, let type = ControlFrameType(rawValue: typeName) else {
            throw TransportError(.invalidFrame, "Control frame type is unknown.")
        }
        guard let timestamp = fields["timestamp"] as? Int else {
            throw TransportError(.invalidFrame, "Control frame has no timestamp.")
        }
        guard let rawPayload = fields["payload"], !(rawPayload is NSNull) else {
            throw TransportError(.invalidFrame, "Control frame has no payload.")
        }
        let payloadData = try JSONSerialization.data(withJSONObject: rawPayload)
        let payload = try JSONDecoder().decode(JSONValue.self, from: payloadData)
        try assertSize(data.count, type: type, limits: limits)
        return RawControlFrame(v: version, id: id, type: type, timestamp: timestamp, payload: payload)
    }

    private static func assertSize(_ bytes: Int, type: ControlFrameType, limits: ControlFrameLimits) throws {
        let protocolMaximum = type == .relay ? ProtocolLimits.maxRelayFrameBytes : ProtocolLimits.maxControlFrameBytes
        let configured = type == .relay ? limits.maxRelayFrameBytes : limits.maxControlFrameBytes
        let maximum = configured.map { min(protocolMaximum, $0) } ?? protocolMaximum
        guard maximum > 0 else {
            throw TransportError(.frameTooLarge, "Control frame limit is invalid.")
        }
        guard bytes <= maximum else {
            throw TransportError(.frameTooLarge, "\(type == .relay ? "Relay" : "Control") frame exceeds its limit.")
        }
    }
}

/// base64url without padding, the way keys.ts writes keys and ciphertext.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) throws -> Data {
        var value = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 {
            value += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: value) else {
            throw TransportError(.invalidBase64, "Value is not base64url.")
        }
        return data
    }
}

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

public struct TransportError: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Code: String, Sendable {
        case invalidFrame
        case frameTooLarge
        case invalidBase64
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
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

    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }
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
    public static func encode<Payload: Codable & Sendable>(
        _ frame: ControlFrame<Payload>,
        limits: ControlFrameLimits = .init()
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(frame)
        try assertSize(data.count, type: frame.type, limits: limits)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TransportError(.invalidFrame, "A control frame did not encode as UTF-8.")
        }
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

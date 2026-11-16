import Foundation

/// Wire constants shared with link/src/frames.ts. Changing any of these is a
/// protocol change, not a refactor.
public enum ProtocolLimits {
    public static let version = 1
    public static let linkPath = "/v1/link"
    public static let maxControlFrameBytes = 64 * 1024
    public static let maxRelayFrameBytes = 1024 * 1024
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

/// The envelope every control frame and every remote message shares:
/// v, id, type, timestamp, payload — in that order, because that is the order the
/// JSON on the wire has.
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

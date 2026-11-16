import Foundation

/// The socket the Relay needs, kept behind a protocol so a test can script it.
public protocol RelaySocket: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close() async
}

/// URLSessionWebSocketTask as a RelaySocket: text frames both ways.
public final class URLSessionRelaySocket: RelaySocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    public init(url: URL) {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw TransportError(.invalidFrame, "The socket sent an unknown frame kind.")
        }
    }

    public func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

public struct RelayOptions: Sendable {
    public var deviceId: String
    public var identityKey: String
    public var accessToken: String
    public var targetDeviceId: String
    public var capabilities: [String]
    public var handshakeTimeoutMs: Int

    public init(
        deviceId: String,
        identityKey: String,
        accessToken: String,
        targetDeviceId: String,
        capabilities: [String] = [ProtocolLimits.relayCapability],
        handshakeTimeoutMs: Int = 10_000
    ) {
        self.deviceId = deviceId
        self.identityKey = identityKey
        self.accessToken = accessToken
        self.targetDeviceId = targetDeviceId
        self.capabilities = capabilities
        self.handshakeTimeoutMs = handshakeTimeoutMs
    }
}

/// Client side of the Server's Relay: the Server only forwards ciphertext.
/// Control frames carry identity and routing; the secure channel rides inside them.
public actor RelayTransport {
    public struct Stats: Sendable {
        public var bytesSent: Int
        public var bytesReceived: Int
    }

    private let options: RelayOptions
    private let socket: RelaySocket
    private var ready: CheckedContinuation<Void, Error>?
    private var connectionId: String?
    private var counter = 0
    private var bytesSent = 0
    private var bytesReceived = 0
    private var limits = ControlFrameLimits()
    private var closed = false
    private var onSecure: (@Sendable (Data) -> Void)?
    private var onHandshake: (@Sendable (Int, Data) -> Void)?

    public init(options: RelayOptions, socket: RelaySocket) {
        self.options = options
        self.socket = socket
    }

    public init(options: RelayOptions, url: URL) {
        self.options = options
        self.socket = URLSessionRelaySocket(url: url)
    }

    public var currentConnectionId: String? { connectionId }

    public var stats: Stats { Stats(bytesSent: bytesSent, bytesReceived: bytesReceived) }

    /// Runs the control handshake and returns once the Server authorized a connection.
    public func start() async throws {
        guard connectionId == nil, !closed else { return }
        Task { await receiveLoop() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ready = continuation
            Task { await sendHello() }
        }
    }

    public func setSecureHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        onSecure = handler
    }

    public func setHandshakeHandler(_ handler: @escaping @Sendable (Int, Data) -> Void) {
        onHandshake = handler
    }

    /// One ciphertext frame; the counter is this direction's message index.
    public func send(_ ciphertext: Data) async throws {
        guard let connectionId else {
            throw TransportError(.invalidFrame, "The relay connection has not been authorized.")
        }
        let payload = RelayPayload(
            connectionId: connectionId,
            targetDeviceId: options.targetDeviceId,
            counter: counter,
            ciphertext: Base64URL.encode(ciphertext)
        )
        try await sendControl(.relay, payload: payload)
        bytesSent += ciphertext.count
        counter += 1
    }

    public func sendHandshake(step: Int, data: Data) async throws {
        guard let connectionId else {
            throw TransportError(.invalidFrame, "The relay connection has not been authorized.")
        }
        let payload = SecureHandshakePayload(
            connectionId: connectionId,
            targetDeviceId: options.targetDeviceId,
            step: step,
            data: Base64URL.encode(data)
        )
        try await sendControl(.secureHandshake, payload: payload)
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        failReady(TransportError(.invalidFrame, "The relay transport closed."))
        await socket.close()
    }

    // MARK: - Control

    private func sendHello() async {
        do {
            try await sendControl(.hello, payload: HelloPayload(
                deviceId: options.deviceId,
                identityKey: options.identityKey,
                accessToken: options.accessToken,
                capabilities: options.capabilities
            ))
        } catch {
            failReady(error)
        }
    }

    private func sendControl<Payload: WirePayload & Codable>(_ type: ControlFrameType, payload: Payload) async throws {
        let frame = ControlFrame(type: type, payload: payload)
        let text = try FrameCodec.encode(frame, limits: limits)
        try await socket.send(text)
    }

    private func receiveLoop() async {
        while !closed {
            let text: String
            do {
                text = try await socket.receive()
            } catch {
                failReady(error)
                return
            }
            do {
                try await handle(text)
            } catch {
                failReady(error)
                await close()
                return
            }
        }
    }

    private func handle(_ text: String) async throws {
        let frame = try FrameCodec.decode(text, limits: limits)
        switch frame.type {
        case .helloAck:
            let protocolVersion = frame.payload["protocol"]?.intValue
            guard protocolVersion == ProtocolLimits.version else {
                throw TransportError(.invalidFrame, "The Server picked an unsupported protocol version.")
            }
            let negotiated = frame.payload["capabilities"]?.stringArrayValue ?? []
            guard negotiated.isEmpty || negotiated.contains(ProtocolLimits.relayCapability) else {
                throw TransportError(.invalidFrame, "The Server did not negotiate the Relay capability.")
            }
            limits = ControlFrameLimits(
                maxControlFrameBytes: frame.payload["maxControlFrameBytes"]?.intValue,
                maxRelayFrameBytes: frame.payload["maxRelayFrameBytes"]?.intValue
            )
            try await sendControl(.connectRequest, payload: ConnectRequestPayload(hostDeviceId: options.targetDeviceId))

        case .connectAccepted:
            guard let id = frame.payload["connectionId"]?.stringValue, !id.isEmpty else {
                throw TransportError(.invalidFrame, "connect.accepted carried no connectionId.")
            }
            connectionId = id
            succeedReady()

        case .connectRejected, .error:
            let message = frame.payload["message"]?.stringValue ?? "The Server rejected the relay connection."
            throw TransportError(.invalidFrame, message)

        case .relay:
            guard let payloadId = frame.payload["connectionId"]?.stringValue, payloadId == connectionId,
                  frame.payload["targetDeviceId"]?.stringValue == options.deviceId,
                  let text = frame.payload["ciphertext"]?.stringValue
            else {
                throw TransportError(.invalidFrame, "A relay frame arrived for an unknown connection.")
            }
            let data = try Base64URL.decode(text)
            bytesReceived += data.count
            onSecure?(data)

        case .secureHandshake:
            guard let payloadId = frame.payload["connectionId"]?.stringValue, payloadId == connectionId,
                  frame.payload["targetDeviceId"]?.stringValue == options.deviceId,
                  let step = frame.payload["step"]?.intValue,
                  let data = frame.payload["data"]?.stringValue
            else {
                throw TransportError(.invalidFrame, "A handshake frame arrived for an unknown connection.")
            }
            onHandshake?(step, try Base64URL.decode(data))

        case .ping:
            try await sendControl(.pong, payload: frame.payload)

        case .pong, .hello, .connectIncoming, .connectRequest:
            break
        }
    }

    private func succeedReady() {
        ready?.resume()
        ready = nil
    }

    private func failReady(_ error: Error) {
        ready?.resume(throwing: error)
        ready = nil
    }
}

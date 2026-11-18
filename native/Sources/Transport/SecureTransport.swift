import Foundation

/// The end-to-end channel from this phone to one paired computer, riding the Relay's
/// control frames: Noise IK first, then one ciphertext per relay frame.
public actor SecureTransport {
    public struct Identity: Sendable {
        public var deviceId: String
        public var publicKey: String
        public var privateKey: String

        public init(deviceId: String, publicKey: String, privateKey: String) {
            self.deviceId = deviceId
            self.publicKey = publicKey
            self.privateKey = privateKey
        }
    }

    public struct Host: Sendable {
        public var deviceId: String
        public var identityKey: String

        public init(deviceId: String, identityKey: String) {
            self.deviceId = deviceId
            self.identityKey = identityKey
        }
    }

    public struct Ready: Sendable {
        public var connectionId: String
        public var remoteHello: Data
    }

    private let relay: RelayTransport
    private let identity: Identity
    private let host: Host
    private let hello: Data
    private let handshakeTimeoutMs: Int

    private var noise: NoiseIKHandshake?
    private var sending: NoiseCipherState?
    private var receiving: NoiseCipherState?
    // One codec per direction: fragments are numbered and reassembled per sender.
    private var outgoingFragments = SecureMessageCodec()
    private var incomingFragments = SecureMessageCodec()
    private var waitingForStepTwo: CheckedContinuation<Data, Error>?
    private var handshakeTimer: Task<Void, Never>?
    private var onMessage: (@Sendable (Data) -> Void)?
    private var onClose: (@Sendable () -> Void)?
    private var connectionId: String?

    /// hello is the handshake hello the phone sends inside the Noise handshake.
    public init(
        relay: RelayTransport,
        identity: Identity,
        host: Host,
        hello: Data = Data(),
        handshakeTimeoutMs: Int = 10_000
    ) {
        self.relay = relay
        self.identity = identity
        self.host = host
        self.hello = hello
        self.handshakeTimeoutMs = handshakeTimeoutMs
    }

    public func setMessageHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        onMessage = handler
    }

    /// Called once when the channel is gone, whether it dropped or we closed it.
    public func setCloseHandler(_ handler: @escaping @Sendable () -> Void) {
        onClose = handler
    }

    /// Relay handshake, Noise message 1, Noise message 2 — in that order.
    public func connect() async throws -> Ready {
        if let connectionId, sending != nil {
            return Ready(connectionId: connectionId, remoteHello: Data())
        }
        try await relay.start()
        guard let connectionId = await relay.currentConnectionId else {
            throw TransportError(.invalidFrame, "The Relay authorized no connection.")
        }
        self.connectionId = connectionId

        let prologue = try createNoisePrologue(
            connectionId: connectionId,
            hostDeviceId: host.deviceId,
            clientDeviceId: identity.deviceId
        )
        let localPair = try NoiseKeyPair(privateKeyBase64URL: identity.privateKey, publicKeyBase64URL: identity.publicKey)
        let remoteStatic = try Base64URL.decode(host.identityKey)
        let noise = try NoiseIKHandshake(
            role: .initiator,
            staticKeyPair: localPair,
            remoteStaticKey: remoteStatic,
            prologue: prologue
        )
        self.noise = noise

        await relay.setHandshakeHandler { [weak self] step, data in
            Task { await self?.handleHandshake(step: step, data: data) }
        }
        await relay.setSecureHandler { [weak self] data in
            Task { await self?.handleSecure(data) }
        }
        await relay.setCloseHandler { [weak self] error in
            Task { await self?.relayClosed(error: error) }
        }

        let first = try noise.writeMessage(payload: hello)
        try await relay.sendHandshake(step: 1, data: first)

        let remoteHello = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            waitingForStepTwo = continuation
            let timeoutMs = handshakeTimeoutMs
            handshakeTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                await self?.expireHandshake()
            }
        }
        return Ready(connectionId: connectionId, remoteHello: remoteHello)
    }

    public func send(_ plaintext: Data) async throws {
        guard var sending else {
            throw TransportError(.invalidFrame, "The secure channel is not ready.")
        }
        // Split first, then encrypt each fragment on its own: one Noise message cannot
        // carry more than 65 535 bytes, and a large state reply is bigger than that.
        for fragment in try outgoingFragments.encode(plaintext) {
            let ciphertext = try sending.encrypt(fragment)
            self.sending = sending
            try await relay.send(ciphertext)
        }
    }

    public var isReady: Bool { sending != nil }

    public func close() async {
        handshakeTimer?.cancel()
        handshakeTimer = nil
        waitingForStepTwo?.resume(throwing: TransportError(.invalidFrame, "The secure channel closed."))
        waitingForStepTwo = nil
        sending = nil
        receiving = nil
        await relay.close()
        onClose?()
    }

    // MARK: - Frames

    private func handleHandshake(step: Int, data: Data) {
        guard step == 2, let noise, let continuation = waitingForStepTwo else { return }
        waitingForStepTwo = nil
        handshakeTimer?.cancel()
        handshakeTimer = nil
        do {
            let remoteHello = try noise.readMessage(data)
            let keys = try noise.split()
            sending = NoiseCipherState(key: keys.sending)
            receiving = NoiseCipherState(key: keys.receiving)
            outgoingFragments.reset()
            incomingFragments.reset()
            continuation.resume(returning: remoteHello)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    private func handleSecure(_ data: Data) {
        guard var receiving else { return }
        do {
            let fragment = try receiving.decrypt(data)
            self.receiving = receiving
            // nil while a message is still arriving in pieces.
            if let plaintext = try incomingFragments.decode(fragment) {
                onMessage?(plaintext)
            }
        } catch {
            // A ciphertext that does not open ends the session; the supervisor reconnects.
            self.receiving = nil
        }
    }

    private func relayClosed(error: Error?) {
        sending = nil
        receiving = nil
        waitingForStepTwo?.resume(throwing: error ?? TransportError(.invalidFrame, "The link dropped during the handshake."))
        waitingForStepTwo = nil
        handshakeTimer?.cancel()
        handshakeTimer = nil
        onClose?()
    }

    private func expireHandshake() {
        guard let continuation = waitingForStepTwo else { return }
        waitingForStepTwo = nil
        continuation.resume(throwing: TransportError(.invalidFrame, "The secure handshake timed out."))
    }
}

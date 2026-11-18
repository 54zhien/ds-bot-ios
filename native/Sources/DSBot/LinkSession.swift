import Foundation

/// 1 s, doubling, +-20 % spread, capped at 60 s, reset after a link stays up 10 s.
/// The React Native app ran exactly these numbers, so behaviour carries over.
public struct Backoff: Sendable {
    public struct Options: Sendable {
        public var minMs: Int = 1_000
        public var factor: Double = 2
        public var jitter: Double = 0.2
        public var maxMs: Int = 60_000
        public var stableMs: Int = 10_000

        public init(minMs: Int = 1_000, factor: Double = 2, jitter: Double = 0.2, maxMs: Int = 60_000, stableMs: Int = 10_000) {
            self.minMs = minMs
            self.factor = factor
            self.jitter = jitter
            self.maxMs = maxMs
            self.stableMs = stableMs
        }
    }

    private let options: Options
    private let random: @Sendable () -> Double
    private var currentMs: Int

    public init(options: Options = Options(), random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.options = options
        self.random = random
        self.currentMs = options.minMs
    }

    /// A link that stayed up long enough starts the ladder over.
    public mutating func reset() {
        currentMs = options.minMs
    }

    /// The next wait, spread by the jitter around the current rung.
    public mutating func nextDelayMs() -> Int {
        let rung = currentMs
        let spread = 1 + (random() * 2 - 1) * options.jitter
        currentMs = min(Int(Double(rung) * options.factor), options.maxMs)
        return max(1, Int((Double(rung) * spread).rounded()))
    }
}

/// One connection object for the app.
public actor LinkSession {
    public enum Status: Equatable, Sendable {
        case disconnected
        case connecting
        case online
        case offline
    }

    public struct Pairing: Sendable {
        public var serverURL: URL
        public var hostDeviceId: String
        public var hostPublicKey: String
        public var identity: SecureTransport.Identity
        public var accessToken: String
        public var pairingCode: String?

        public init(
            serverURL: URL,
            hostDeviceId: String,
            hostPublicKey: String,
            identity: SecureTransport.Identity,
            accessToken: String,
            pairingCode: String? = nil
        ) {
            self.serverURL = serverURL
            self.hostDeviceId = hostDeviceId
            self.hostPublicKey = hostPublicKey
            self.identity = identity
            self.accessToken = accessToken
            self.pairingCode = pairingCode
        }
    }

    public struct Options: Sendable {
        public var retry: Backoff.Options = Backoff.Options()
        /// After this much time spent failing, the session stops and says so.
        public var disconnectedAfterMs: Int = 60_000
        public var handshakeTimeoutMs: Int = 10_000
        public var callTimeoutMs: Int = 30_000

        public init() {}
    }

    /// What the supervisor needs from a connection, so a test can fake it.
    public protocol Channel: Sendable {
        func call(_ method: String, params: JSONValue) async throws -> JSONValue
        func send(_ data: Data) async throws
        func setEventHandler(_ handler: @escaping @Sendable (String, JSONValue) -> Void) async
        func close() async
    }

    public typealias ChannelFactory = @Sendable (Pairing, @escaping @Sendable () -> Void) async throws -> Channel

    private let options: Options
    private let makeChannel: ChannelFactory
    private let sleep: @Sendable (Int) async -> Void
    private var status: Status = .disconnected
    private var wanted = false
    private var loop: Task<Void, Never>?
    private var channel: Channel?
    private var dropWaiter: CheckedContinuation<Void, Never>?
    private var onStatus: (@Sendable (Status) -> Void)?
    private var onError: (@Sendable (String) -> Void)?
    private var onEvent: (@Sendable (String, JSONValue) -> Void)?

    public init(
        options: Options = Options(),
        makeChannel: @escaping ChannelFactory = LinkSession.liveChannel,
        sleep: @escaping @Sendable (Int) async -> Void = { milliseconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
        }
    ) {
        self.options = options
        self.makeChannel = makeChannel
        self.sleep = sleep
    }

    public var currentStatus: Status { status }

    public func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        onStatus = handler
        handler(status)
    }

    public func setErrorHandler(_ handler: @escaping @Sendable (String) -> Void) {
        onError = handler
    }

    public func setEventHandler(_ handler: @escaping @Sendable (String, JSONValue) -> Void) async {
        onEvent = handler
        await channel?.setEventHandler(handler)
    }

    public func connect(_ pairing: Pairing) {
        guard !wanted else { return }
        wanted = true
        setStatus(.connecting)
        loop = Task { await runLoop(pairing) }
    }

    public func disconnect() async {
        wanted = false
        dropWaiter?.resume()
        dropWaiter = nil
        let current = channel
        channel = nil
        await current?.close()
        setStatus(.disconnected)
    }

    public func call(_ method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        guard let channel else {
            throw TransportError(.invalidFrame, "The link is not connected.")
        }
        // Every call is timed and kept, because a chat that never fills is otherwise a
        // screen with nothing to read on it.
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let reply = try await channel.call(method, params: params)
            await Diagnostics.shared.recordCall(
                method: method, endpoint: params["endpoint"]?.stringValue,
                milliseconds: LinkSession.elapsed(since: started),
                errorCode: nil, errorMessage: nil, reply: reply
            )
            return reply
        } catch {
            let failure = LinkSession.failure(error)
            await Diagnostics.shared.recordCall(
                method: method, endpoint: params["endpoint"]?.stringValue,
                milliseconds: LinkSession.elapsed(since: started),
                errorCode: failure.code, errorMessage: failure.message, reply: nil
            )
            throw error
        }
    }

    /// Uptime, not the wall clock: a clock change must not turn a call into a huge number.
    private static func elapsed(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    /// The dump carries strings, not error objects, so an actor can hold them.
    private static func failure(_ error: Error) -> (code: String?, message: String) {
        if let transport = error as? TransportError { return (transport.code.rawValue, transport.message) }
        let nsError = error as NSError
        return ("\(nsError.domain)#\(nsError.code)", nsError.localizedDescription)
    }

    // MARK: - Supervisor

    private func runLoop(_ initialPairing: Pairing) async {
        var pairing = initialPairing
        var backoff = Backoff(options: options.retry)
        var failingMs = 0
        while wanted {
            setStatus(.connecting)
            do {
                let opened = try await makeChannel(pairing) { [weak self] in
                    Task { await self?.dropped() }
                }
                if let onEvent { await opened.setEventHandler(onEvent) }
                channel = opened
                setStatus(.online)
                // A pairing code is valid for the first handshake only. A later
                // reconnect authenticates with the phone's stored identity.
                pairing.pairingCode = nil
                backoff.reset()
                failingMs = 0
                await waitForDrop()
                channel = nil
                guard wanted else { break }
            } catch {
                channel = nil
                guard wanted else { break }
                onError?(String(describing: error))
                await Diagnostics.shared.recordLinkError(String(describing: error))
                // disconnect() may have run while the dump was being written; without this
                // the offline below would walk the status back from disconnected.
                guard wanted else { break }
                if let rejected = error as? TransportError,
                   rejected.code == .notPaired || rejected.code == .pairingRejected {
                    wanted = false
                    break
                }
            }
            setStatus(.offline)
            let delay = backoff.nextDelayMs()
            failingMs += delay
            if failingMs >= options.disconnectedAfterMs {
                setStatus(.disconnected)
                wanted = false
                break
            }
            await sleep(delay)
        }
        setStatus(.disconnected)
    }

    private func waitForDrop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dropWaiter = continuation
        }
    }

    private func dropped() {
        dropWaiter?.resume()
        dropWaiter = nil
    }

    private func setStatus(_ next: Status) {
        guard next != status else { return }
        status = next
        onStatus?(next)
    }

    // MARK: - The real channel

    /// Relay handshake, Noise handshake, and one RPC client on top.
    public static let liveChannel: ChannelFactory = { pairing, dropped in
        let relay = RelayTransport(
            options: RelayOptions(
                deviceId: pairing.identity.deviceId,
                identityKey: pairing.identity.publicKey,
                accessToken: pairing.accessToken,
                targetDeviceId: pairing.hostDeviceId
            ),
            url: pairing.serverURL
        )
        let hello = try LinkSession.handshakeHello(pairing)
        let secure = SecureTransport(
            relay: relay,
            identity: pairing.identity,
            host: SecureTransport.Host(deviceId: pairing.hostDeviceId, identityKey: pairing.hostPublicKey),
            hello: hello
        )
        await secure.setCloseHandler { dropped() }
        let ready = try await secure.connect()
        await Diagnostics.shared.recordHandshake(sent: hello, received: ready.remoteHello)
        let rpc = RpcClient(send: { data in try await secure.send(data) })
        // A message that could not be read used to vanish here without a trace.
        await rpc.setInvalidMessageHandler { text in
            Task { await Diagnostics.shared.recordInvalidMessage(text) }
        }
        await secure.setMessageHandler { data in
            Task { await rpc.receive(data) }
        }
        return LiveChannel(secure: secure, rpc: rpc)
    }

    /// HandshakeHello is name plus the pairing code, and the code only rides the
    /// first pairing (pairing.ts).
    static func handshakeHello(_ pairing: Pairing) -> Data {
        var object = OrderedObject()
        object.add("name", JSONText.string("DS Bot"))
        if let code = pairing.pairingCode {
            object.add("pairingCode", JSONText.string(code))
        }
        return Data(object.text.utf8)
    }
}

private struct LiveChannel: LinkSession.Channel {
    let secure: SecureTransport
    let rpc: RpcClient

    func call(_ method: String, params: JSONValue) async throws -> JSONValue {
        try await rpc.call(method, params: params)
    }

    func send(_ data: Data) async throws {
        try await secure.send(data)
    }

    func setEventHandler(_ handler: @escaping @Sendable (String, JSONValue) -> Void) async {
        await rpc.setEventHandler(handler)
    }

    func close() async {
        await rpc.close()
        await secure.close()
    }
}

public extension LinkSession.Channel {
    func setEventHandler(_ handler: @escaping @Sendable (String, JSONValue) -> Void) async {}
}

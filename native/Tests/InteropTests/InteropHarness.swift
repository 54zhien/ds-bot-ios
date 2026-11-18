import Foundation

/// The transport stack every interop case builds the same way: one relay socket, the
/// Noise handshake with the fixture host, and an RPC client on top.
///
/// Every case uses the same identity on purpose. A pairing code works once, so whichever
/// case connects first spends it; the host then knows the device, and pairing.ts admits
/// a paired device without a code. A fresh key per case would meet connect.rejected.
final class InteropHarness: Sendable {
    let relay: RelayTransport
    let secure: SecureTransport
    let rpc: RpcClient
    /// The size of every plaintext the channel delivered, so a case can prove the reply
    /// it got was long enough to have been split.
    let delivered = MessageSizes()

    private init(relay: RelayTransport, secure: SecureTransport, rpc: RpcClient) {
        self.relay = relay
        self.secure = secure
        self.rpc = rpc
    }

    static func connect() async throws -> InteropHarness {
        let privateKey = Data((0..<32).map { index in UInt8((index * 7 + 3) & 0xff) })
        let keys = try NoiseKeyPair(privateKey: privateKey)
        let deviceId = InteropIdentity.deviceId(for: keys.publicKey)
        let identity = SecureTransport.Identity(
            deviceId: deviceId,
            publicKey: Base64URL.encode(keys.publicKey),
            privateKey: Base64URL.encode(keys.privateKey)
        )
        let host = SecureTransport.Host(
            deviceId: InteropConfig.hostDeviceId,
            identityKey: InteropConfig.hostPublicKey
        )
        guard let url = URL(string: InteropConfig.serverURL) else {
            throw TransportError(.invalidFrame, "InteropConfig.serverURL is not a URL")
        }
        let relay = RelayTransport(
            options: RelayOptions(
                deviceId: deviceId,
                identityKey: identity.publicKey,
                // The Relay refuses a token shorter than 32 characters.
                accessToken: String(repeating: "k", count: 32),
                targetDeviceId: InteropConfig.hostDeviceId
            ),
            url: url
        )
        // The host authorizes a new phone only by the code inside this hello.
        let hello = Data("{\"name\":\"Swift interop\",\"pairingCode\":\"\(InteropConfig.pairingCode)\"}".utf8)
        let secure = SecureTransport(
            relay: relay, identity: identity, host: host, hello: hello, handshakeTimeoutMs: 20_000
        )
        let rpc = RpcClient(
            options: RpcClient.Options(timeoutMs: 20_000),
            send: { message in try await secure.send(message) }
        )
        let harness = InteropHarness(relay: relay, secure: secure, rpc: rpc)
        // The handler goes on before connect(): the host may push a message the moment
        // the handshake completes, and a late handler drops it.
        await secure.setMessageHandler { message in
            harness.delivered.record(message.count)
            Task { await rpc.receive(message) }
        }
        _ = try await secure.connect()
        return harness
    }

    func close() async {
        await rpc.close()
        await secure.close()
    }
}

/// Records message sizes from the channel's own thread, so the values are readable from
/// the test afterwards.
final class MessageSizes: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func record(_ size: Int) {
        lock.withLock { storage.append(size) }
    }

    var all: [Int] {
        lock.withLock { storage }
    }
}

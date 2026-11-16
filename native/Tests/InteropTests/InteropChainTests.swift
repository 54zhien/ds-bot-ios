import CryptoKit
import Foundation
import XCTest

/// End to end against the CI relay and host: the pairing code travels inside the
/// Noise handshake, one RPC goes over the secure channel, and the session closes
/// without leaving a socket behind.
///
/// This target compiles Sources/Transport into itself, so there is no module to
/// import; the types are used directly.
final class InteropChainTests: XCTestCase {
    func testConnectHandshakeAndOneRpc() async throws {
        let pairingCode = InteropConfig.pairingCode

        let privateKey = Data((0..<32).map { index in UInt8((index * 7 + 3) & 0xff) })
        let phoneKeys = try NoiseKeyPair(privateKey: privateKey)
        // gateway.ts derives the device id from the identity key and rejects a hello
        // whose id does not match, so the test has to derive it the same way.
        let deviceId = InteropChainTests.deviceId(for: phoneKeys.publicKey)
        let identity = SecureTransport.Identity(
            deviceId: deviceId,
            publicKey: Base64URL.encode(phoneKeys.publicKey),
            privateKey: Base64URL.encode(phoneKeys.privateKey)
        )
        let host = SecureTransport.Host(
            deviceId: InteropConfig.hostDeviceId,
            identityKey: InteropConfig.hostPublicKey
        )
        guard let url = URL(string: InteropConfig.serverURL) else {
            throw XCTSkip("InteropConfig.serverURL is not a URL")
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
        let hello = Data("{\"name\":\"Swift interop\",\"pairingCode\":\"\(pairingCode)\"}".utf8)
        let secure = SecureTransport(relay: relay, identity: identity, host: host, hello: hello, handshakeTimeoutMs: 20_000)
        let rpc = RpcClient(
            options: RpcClient.Options(timeoutMs: 20_000),
            send: { message in try await secure.send(message) }
        )
        await secure.setMessageHandler { message in
            Task { await rpc.receive(message) }
        }

        let ready = try await secure.connect()
        XCTAssertFalse(ready.connectionId.isEmpty, "the Server must authorize a connection id")
        // The host's hello says who it is by display name only (pairing.ts HandshakeHello
        // has just name and pairingCode); identity is bound by the Noise static key.
        let remoteHello = try JSONSerialization.jsonObject(with: ready.remoteHello) as? [String: Any]
        XCTAssertEqual(remoteHello?["name"] as? String, "CI Desk", "the host hello carries the name scripts/interop-host.mjs gives it")
        XCTAssertNil(remoteHello?["pairingCode"], "the host never echoes the pairing code")

        // The paired identity data has to be self-consistent: the Relay derives the id
        // from the key, and this is the same derivation.
        let hostKeyBytes = try Base64URL.decode(InteropConfig.hostPublicKey)
        XCTAssertEqual(InteropChainTests.deviceId(for: hostKeyBytes), InteropConfig.hostDeviceId, "hostDeviceId must be the derivation of hostPublicKey")

        let reply = try await rpc.call("bot.state", params: .object([:]))
        XCTAssertTrue(reply["ok"] == .bool(true), "the host answers ok: true")
        XCTAssertEqual(reply["method"]?.stringValue, "bot.state", "the host echoes the method")

        await rpc.close()
        await secure.close()
        let readyAfterClose = await secure.isReady
        XCTAssertFalse(readyAfterClose, "close() leaves no usable channel")
    }

    /// keys.ts: `d-` + base64url(sha256(raw X25519 public key)[0..<16]).
    private static func deviceId(for publicKey: Data) -> String {
        let digest = Data(SHA256.hash(data: publicKey))
        return "d-" + Base64URL.encode(digest.prefix(16))
    }
}

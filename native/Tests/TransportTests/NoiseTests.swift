import CryptoKit
import XCTest
@testable import DSBot

final class NoiseTests: XCTestCase {
    func testHandshakeReproducesThePinnedTranscript() throws {
        let vector = try KeysFixture.load()
        let phone = try NoiseKeyPair(privateKeyBase64URL: vector.keys.phone.privateKey, publicKeyBase64URL: vector.keys.phone.publicKey)
        let host = try NoiseKeyPair(privateKeyBase64URL: vector.keys.host.privateKey, publicKeyBase64URL: vector.keys.host.publicKey)

        let prologue = try createNoisePrologue(
            connectionId: vector.connection.connectionId,
            hostDeviceId: vector.connection.hostDeviceId,
            clientDeviceId: vector.connection.clientDeviceId
        )
        XCTAssertEqual(Hex.string(prologue), vector.prologue.hex, "prologue bytes")

        let initiator = try NoiseIKHandshake(
            role: .initiator,
            staticKeyPair: phone,
            remoteStaticKey: host.publicKey,
            prologue: prologue,
            random: PinnedRandom(tag: "phone").next
        )
        let responder = try NoiseIKHandshake(
            role: .responder,
            staticKeyPair: host,
            remoteStaticKey: phone.publicKey,
            prologue: prologue,
            random: PinnedRandom(tag: "host").next
        )

        let phoneHello = Data("{\"name\":\"Phone (vector)\"}".utf8)
        let deskHello = Data("{\"name\":\"Desk (vector)\"}".utf8)

        let message1 = try initiator.writeMessage(payload: phoneHello)
        XCTAssertEqual(message1.count, vector.handshake.message1.bytes, "message 1 length")
        XCTAssertEqual(Hex.string(message1), vector.handshake.message1.hex, "message 1 bytes")

        let readByHost = try responder.readMessage(message1)
        XCTAssertEqual(readByHost, phoneHello, "message 1 payload")

        let message2 = try responder.writeMessage(payload: deskHello)
        XCTAssertEqual(message2.count, vector.handshake.message2.bytes, "message 2 length")
        XCTAssertEqual(Hex.string(message2), vector.handshake.message2.hex, "message 2 bytes")

        let readByPhone = try initiator.readMessage(message2)
        XCTAssertEqual(readByPhone, deskHello, "message 2 payload")

        XCTAssertEqual(Hex.string(initiator.hash), vector.handshake.handshakeHash.hex, "initiator handshake hash")
        XCTAssertEqual(Hex.string(responder.hash), vector.handshake.handshakeHash.hex, "responder handshake hash")

        let phoneKeys = try initiator.split()
        let hostKeys = try responder.split()
        XCTAssertEqual(Hex.string(phoneKeys.sending), vector.session.initiatorToResponder.hex, "initiator to responder key")
        XCTAssertEqual(Hex.string(phoneKeys.receiving), vector.session.responderToInitiator.hex, "responder to initiator key")
        XCTAssertEqual(Hex.string(hostKeys.receiving), vector.session.initiatorToResponder.hex, "responder receives with the initiator key")
        XCTAssertEqual(Hex.string(hostKeys.sending), vector.session.responderToInitiator.hex, "responder sends with its own key")

        var phoneTransport = NoiseCipherState(key: phoneKeys.sending)
        let ciphertext = try phoneTransport.encrypt(Data(vector.transportProof.plaintextUtf8.utf8))
        XCTAssertEqual(ciphertext.count, vector.transportProof.ciphertextBytes, "transport proof length")
        XCTAssertEqual(Hex.string(ciphertext), vector.transportProof.ciphertextHex, "transport proof bytes")
        XCTAssertEqual(phoneTransport.nonce, 1, "the nonce advances after one message")

        var hostTransport = NoiseCipherState(key: hostKeys.receiving)
        let plaintext = try hostTransport.decrypt(ciphertext)
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), vector.transportProof.plaintextUtf8)
    }

    func testHandshakeRejectsAForeignStaticKey() throws {
        let vector = try KeysFixture.load()
        let phone = try NoiseKeyPair(privateKeyBase64URL: vector.keys.phone.privateKey, publicKeyBase64URL: vector.keys.phone.publicKey)
        let host = try NoiseKeyPair(privateKeyBase64URL: vector.keys.host.privateKey, publicKeyBase64URL: vector.keys.host.publicKey)
        let prologue = try createNoisePrologue(
            connectionId: vector.connection.connectionId,
            hostDeviceId: vector.connection.hostDeviceId,
            clientDeviceId: vector.connection.clientDeviceId
        )
        let initiator = try NoiseIKHandshake(
            role: .initiator,
            staticKeyPair: phone,
            remoteStaticKey: host.publicKey,
            prologue: prologue,
            random: PinnedRandom(tag: "phone").next
        )
        let impostor = try NoiseKeyPair(privateKey: Data(repeating: 0x11, count: 32))
        let message1 = try initiator.writeMessage(payload: Data())
        let responder = try NoiseIKHandshake(
            role: .responder,
            staticKeyPair: host,
            remoteStaticKey: impostor.publicKey,
            prologue: prologue,
            random: PinnedRandom(tag: "host").next
        )
        XCTAssertThrowsError(try responder.readMessage(message1)) { error in
            XCTAssertEqual(error as? NoiseError, .peerIdentityMismatch)
        }
    }
}

// MARK: - Pinned randomness: random(tag, n) = sha256(tag || uint24le(n)), as the vectors define it

private final class PinnedRandom {
    private let tag: String
    private var counter: UInt32 = 0

    init(tag: String) {
        self.tag = tag
    }

    func next(_ length: Int) -> Data {
        var input = Data(tag.utf8)
        let value = counter
        input.append(UInt8(value & 0xff))
        input.append(UInt8((value >> 8) & 0xff))
        input.append(UInt8((value >> 16) & 0xff))
        counter &+= 1
        let digest = Data(SHA256.hash(data: input))
        return digest.count >= length ? digest.prefix(length) : digest
    }
}

// MARK: - Fixtures

private enum Hex {
    static func string(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private struct KeysFixture: Decodable {
    struct KeyPair: Decodable {
        let privateKey: String
        let publicKey: String
    }

    struct Keys: Decodable {
        let phone: KeyPair
        let host: KeyPair
    }

    struct Connection: Decodable {
        let connectionId: String
        let hostDeviceId: String
        let clientDeviceId: String
    }

    struct Prologue: Decodable {
        let hex: String
    }

    struct Handshake: Decodable {
        struct Message: Decodable {
            let bytes: Int
            let hex: String
        }

        struct Hash: Decodable {
            let hex: String
        }

        let message1: Message
        let message2: Message
        let handshakeHash: Hash
    }

    struct Session: Decodable {
        struct Key: Decodable {
            let hex: String
        }

        let initiatorToResponder: Key
        let responderToInitiator: Key
    }

    struct TransportProof: Decodable {
        let plaintextUtf8: String
        let ciphertextHex: String
        let ciphertextBytes: Int
    }

    let keys: Keys
    let connection: Connection
    let prologue: Prologue
    let handshake: Handshake
    let session: Session
    let transportProof: TransportProof

    static func load() throws -> KeysFixture {
        guard let url = locate() else {
            throw XCTSkip("docs/link-test-vectors/keys.json is not reachable from \(#filePath)")
        }
        return try JSONDecoder().decode(KeysFixture.self, from: Data(contentsOf: url))
    }

    private static func locate() -> URL? {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            directory.deleteLastPathComponent()
            let candidate = directory.appendingPathComponent("docs/link-test-vectors/keys.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

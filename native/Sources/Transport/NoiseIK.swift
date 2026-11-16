import CryptoKit
import Foundation

/// Noise_IK_25519_ChaChaPoly_SHA256, the suite link/src/noise.ts pins.
/// IK, so the phone only learns the computer's static key through a pair it trusts:
///
///     <- s
///     ...
///     -> e, es, s, ss
///     <- e, ee, se
public enum NoiseSuite {
    public static let name = "Noise_IK_25519_ChaChaPoly_SHA256"
    public static let hashLength = 32
    public static let keyLength = 32
    public static let tagLength = 16
    /// The protocol name is exactly 32 bytes, so it is the initial hash as-is.
    public static let initialHash = Data("Noise_IK_25519_ChaChaPoly_SHA256".utf8)
}

public enum NoiseError: Error, Equatable, CustomStringConvertible {
    case invalidKey(String)
    case invalidMessage(String)
    case handshakeOrder(String)
    case handshakeFinished
    case peerIdentityMismatch
    case decryptionFailed

    public var description: String {
        switch self {
        case .invalidKey(let detail): return "invalidKey: " + detail
        case .invalidMessage(let detail): return "invalidMessage: " + detail
        case .handshakeOrder(let detail): return "handshakeOrder: " + detail
        case .handshakeFinished: return "handshakeFinished"
        case .peerIdentityMismatch: return "peerIdentityMismatch"
        case .decryptionFailed: return "decryptionFailed"
        }
    }
}

public enum NoiseRole: Sendable {
    case initiator
    case responder
}

public struct NoiseKeyPair: Sendable, Equatable {
    public let privateKey: Data
    public let publicKey: Data

    public init(privateKey: Data, publicKey: Data) {
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    public init(privateKey: Data) throws {
        guard privateKey.count == NoiseSuite.keyLength else {
            throw NoiseError.invalidKey("A private key must be 32 bytes.")
        }
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        self.privateKey = privateKey
        self.publicKey = key.publicKey.rawRepresentation
    }

    /// The base64url pair keys.json and the phone's store use.
    public init(privateKeyBase64URL: String, publicKeyBase64URL: String) throws {
        let privateKey = try Base64URL.decode(privateKeyBase64URL)
        let publicKey = try Base64URL.decode(publicKeyBase64URL)
        guard privateKey.count == NoiseSuite.keyLength, publicKey.count == NoiseSuite.keyLength else {
            throw NoiseError.invalidKey("A Noise key must be 32 bytes.")
        }
        self.init(privateKey: privateKey, publicKey: publicKey)
    }
}

/// One direction of an established session: a key and the next nonce to use.
public struct NoiseCipherState: Sendable {
    public private(set) var key: Data
    public private(set) var nonce: UInt64

    public init(key: Data, nonce: UInt64 = 0) {
        self.key = key
        self.nonce = nonce
    }

    public mutating func encrypt(_ plaintext: Data, authenticatingData: Data = Data()) throws -> Data {
        let box = try ChaChaPoly.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: try NoiseNonce.make(nonce),
            authenticating: authenticatingData
        )
        nonce &+= 1
        return box.ciphertext + box.tag
    }

    public mutating func decrypt(_ ciphertext: Data, authenticatingData: Data = Data()) throws -> Data {
        guard ciphertext.count >= NoiseSuite.tagLength else {
            throw NoiseError.invalidMessage("A transport message is shorter than its tag.")
        }
        let body = ciphertext.prefix(ciphertext.count - NoiseSuite.tagLength)
        let tag = ciphertext.suffix(NoiseSuite.tagLength)
        let box = try ChaChaPoly.SealedBox(
            nonce: try NoiseNonce.make(nonce),
            ciphertext: body,
            tag: tag
        )
        do {
            let plaintext = try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: authenticatingData)
            nonce &+= 1
            return plaintext
        } catch {
            throw NoiseError.decryptionFailed
        }
    }
}

/// The two directions after split(); the initiator sends with sending.
public struct NoiseTransportKeys: Sendable, Equatable {
    public var sending: Data
    public var receiving: Data

    public init(sending: Data, receiving: Data) {
        self.sending = sending
        self.receiving = receiving
    }
}

public func createNoisePrologue(connectionId: String, hostDeviceId: String, clientDeviceId: String) throws -> Data {
    let parts = [("connectionId", connectionId), ("hostDeviceId", hostDeviceId), ("clientDeviceId", clientDeviceId)]
    for (name, value) in parts {
        if value.isEmpty || value.contains("\0") {
            throw NoiseError.invalidMessage(name + " is not safe for a Noise prologue")
        }
    }
    let text = "DS-BOT-LINK\0v=1\0connection=" + connectionId + "\0host=" + hostDeviceId + "\0client=" + clientDeviceId
    return Data(text.utf8)
}

/// One IK handshake. Write, read, write, read in the order the pattern dictates;
/// split() hands back the two transport directions once message 2 is in.
public final class NoiseIKHandshake {
    private let role: NoiseRole
    private let localStatic: NoiseKeyPair
    private let remoteStatic: Data
    private let random: (Int) -> Data

    private var chainingKey: Data
    private var handshakeHash: Data
    private var cipherKey = Data()
    private var nonce: UInt64 = 0
    private var ephemeral: NoiseKeyPair?
    private var remoteEphemeral: Data?
    private var remoteStaticSeen: Data?
    /// 0 before message 1, 1 after it, 2 once message 2 is in.
    private var messageIndex = 0
    private var finished = false

    public init(
        role: NoiseRole,
        staticKeyPair: NoiseKeyPair,
        remoteStaticKey: Data,
        prologue: Data,
        random: ((Int) -> Data)? = nil
    ) throws {
        guard staticKeyPair.privateKey.count == NoiseSuite.keyLength,
              staticKeyPair.publicKey.count == NoiseSuite.keyLength,
              remoteStaticKey.count == NoiseSuite.keyLength
        else {
            throw NoiseError.invalidKey("Every Noise key must be 32 bytes.")
        }
        self.role = role
        self.localStatic = staticKeyPair
        self.remoteStatic = remoteStaticKey
        self.random = random ?? NoiseIKHandshake.systemRandom

        var hash = NoiseSuite.initialHash
        NoiseIKHandshake.mixHash(&hash, prologue)
        // The pre-message is the responder's static key; the responder knows its own.
        NoiseIKHandshake.mixHash(&hash, role == .initiator ? remoteStaticKey : staticKeyPair.publicKey)

        self.handshakeHash = hash
        self.chainingKey = NoiseSuite.initialHash
    }

    public var hash: Data { handshakeHash }
    public var isFinished: Bool { finished }

    public func writeMessage(payload: Data = Data()) throws -> Data {
        guard !finished else { throw NoiseError.handshakeFinished }
        switch (role, messageIndex) {
        case (.initiator, 0):
            var out = Data()
            let ephemeral = try NoiseIKHandshake.generateEphemeral(random: random)
            self.ephemeral = ephemeral
            out.append(ephemeral.publicKey)
            NoiseIKHandshake.mixHash(&handshakeHash, ephemeral.publicKey)
            mixKey(try dh(ephemeral.privateKey, remoteStatic))
            out.append(try encryptAndHash(localStatic.publicKey))
            mixKey(try dh(localStatic.privateKey, remoteStatic))
            out.append(try encryptAndHash(payload))
            messageIndex = 1
            return out

        case (.responder, 1):
            var out = Data()
            let ephemeral = try NoiseIKHandshake.generateEphemeral(random: random)
            self.ephemeral = ephemeral
            out.append(ephemeral.publicKey)
            NoiseIKHandshake.mixHash(&handshakeHash, ephemeral.publicKey)
            guard let initiatorEphemeral = remoteEphemeral else {
                throw NoiseError.handshakeOrder("Message 1 has not been read.")
            }
            mixKey(try dh(ephemeral.privateKey, initiatorEphemeral))
            mixKey(try dh(ephemeral.privateKey, try requiredRemoteStatic()))
            out.append(try encryptAndHash(payload))
            messageIndex = 2
            finished = true
            return out

        default:
            throw NoiseError.handshakeOrder("This side writes no more handshake messages.")
        }
    }

    public func readMessage(_ message: Data) throws -> Data {
        guard !finished else { throw NoiseError.handshakeFinished }
        switch (role, messageIndex) {
        case (.responder, 0):
            var cursor = DataReader(message)
            let ephemeralPublic = try cursor.read(NoiseSuite.keyLength)
            remoteEphemeral = ephemeralPublic
            NoiseIKHandshake.mixHash(&handshakeHash, ephemeralPublic)
            mixKey(try dh(localStatic.privateKey, ephemeralPublic))
            let staticPublic = try decryptAndHash(try cursor.read(NoiseSuite.keyLength + NoiseSuite.tagLength))
            guard NoiseIKHandshake.constantTimeEqual(staticPublic, remoteStatic) else {
                throw NoiseError.peerIdentityMismatch
            }
            remoteStaticSeen = staticPublic
            mixKey(try dh(localStatic.privateKey, staticPublic))
            let payload = try decryptAndHash(try cursor.readToEnd())
            messageIndex = 1
            return payload

        case (.initiator, 1):
            var cursor = DataReader(message)
            let ephemeralPublic = try cursor.read(NoiseSuite.keyLength)
            remoteEphemeral = ephemeralPublic
            NoiseIKHandshake.mixHash(&handshakeHash, ephemeralPublic)
            guard let ephemeral = ephemeral else {
                throw NoiseError.handshakeOrder("This side has written no ephemeral key.")
            }
            mixKey(try dh(ephemeral.privateKey, ephemeralPublic))
            mixKey(try dh(localStatic.privateKey, ephemeralPublic))
            let payload = try decryptAndHash(try cursor.readToEnd())
            messageIndex = 2
            finished = true
            return payload

        default:
            throw NoiseError.handshakeOrder("This side reads no more handshake messages.")
        }
    }

    /// The two transport directions; only after both messages have crossed.
    public func split() throws -> NoiseTransportKeys {
        guard finished else {
            throw NoiseError.handshakeOrder("The handshake is not complete.")
        }
        let (first, second) = NoiseIKHandshake.hkdf2(chainingKey, Data())
        switch role {
        case .initiator:
            return NoiseTransportKeys(sending: first, receiving: second)
        case .responder:
            return NoiseTransportKeys(sending: second, receiving: first)
        }
    }

    // MARK: - Symmetric state

    private func requiredRemoteStatic() throws -> Data {
        guard let remoteStaticSeen else {
            throw NoiseError.handshakeOrder("The peer's static key has not arrived yet.")
        }
        return remoteStaticSeen
    }

    private func mixKey(_ input: Data) {
        let (newChaining, key) = NoiseIKHandshake.hkdf2(chainingKey, input)
        chainingKey = newChaining
        cipherKey = key
        nonce = 0
    }

    private func encryptAndHash(_ plaintext: Data) throws -> Data {
        let ciphertext = try encrypt(plaintext)
        NoiseIKHandshake.mixHash(&handshakeHash, ciphertext)
        return ciphertext
    }

    private func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let plaintext = try decrypt(ciphertext)
        NoiseIKHandshake.mixHash(&handshakeHash, ciphertext)
        return plaintext
    }

    private func encrypt(_ plaintext: Data) throws -> Data {
        guard !cipherKey.isEmpty else {
            return plaintext
        }
        let box = try ChaChaPoly.seal(
            plaintext,
            using: SymmetricKey(data: cipherKey),
            nonce: try NoiseNonce.make(nonce),
            authenticating: handshakeHash
        )
        nonce &+= 1
        return box.ciphertext + box.tag
    }

    private func decrypt(_ ciphertext: Data) throws -> Data {
        guard !cipherKey.isEmpty else { return ciphertext }
        guard ciphertext.count >= NoiseSuite.tagLength else {
            throw NoiseError.invalidMessage("A handshake ciphertext is shorter than its tag.")
        }
        let body = ciphertext.prefix(ciphertext.count - NoiseSuite.tagLength)
        let tag = ciphertext.suffix(NoiseSuite.tagLength)
        do {
            let box = try ChaChaPoly.SealedBox(nonce: try NoiseNonce.make(nonce), ciphertext: body, tag: tag)
            let plaintext = try ChaChaPoly.open(box, using: SymmetricKey(data: cipherKey), authenticating: handshakeHash)
            nonce &+= 1
            return plaintext
        } catch {
            throw NoiseError.decryptionFailed
        }
    }

    // MARK: - Primitives

    private func dh(_ privateKey: Data, _ publicKey: Data) throws -> Data {
        let local = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let shared = try local.sharedSecretFromKeyAgreement(with: remote)
        return shared.withUnsafeBytes { Data($0) }
    }

    private static func generateEphemeral(random: (Int) -> Data) throws -> NoiseKeyPair {
        let privateKey = random(NoiseSuite.keyLength)
        guard privateKey.count == NoiseSuite.keyLength else {
            throw NoiseError.invalidKey("The random source returned an unexpected length.")
        }
        return try NoiseKeyPair(privateKey: privateKey)
    }

    private static func systemRandom(_ length: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8]()
        bytes.reserveCapacity(length)
        for _ in 0..<length {
            bytes.append(UInt8.random(in: 0...255, using: &generator))
        }
        return Data(bytes)
    }

    static func mixHash(_ hash: inout Data, _ data: Data) {
        var input = hash
        input.append(data)
        hash = Data(SHA256.hash(data: input))
    }

    /// Noise HKDF(ck, ikm) producing two outputs, on HMAC-SHA256.
    static func hkdf2(_ chainingKey: Data, _ inputKeyMaterial: Data) -> (Data, Data) {
        let temp = hmac(key: chainingKey, inputKeyMaterial)
        let first = hmac(key: temp, Data([0x01]))
        var secondInput = first
        secondInput.append(0x02)
        let second = hmac(key: temp, secondInput)
        return (first, second)
    }

    private static func hmac(key: Data, _ data: Data) -> Data {
        let code = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(code)
    }

    static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        var different: UInt8 = 0
        for index in left.indices {
            different |= left[index] ^ right[index]
        }
        return different == 0
    }
}

enum NoiseNonce {
    static func make(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = Data(repeating: 0, count: 4)
        var value = counter.littleEndian
        withUnsafeBytes(of: &value) { raw in
            bytes.append(contentsOf: raw)
        }
        return try ChaChaPoly.Nonce(data: bytes)
    }
}

/// A cursor over a handshake message: every read is explicit, so a short frame is
/// reported as such instead of silently truncating.
struct DataReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = 0
    }

    mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw NoiseError.invalidMessage("A handshake message ended early.")
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return data[start..<end]
    }

    mutating func readToEnd() throws -> Data {
        try read(data.count - offset)
    }
}

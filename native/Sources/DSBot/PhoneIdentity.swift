import CryptoKit
import Foundation
import Security

/// This phone as the computer knows it. The private key is the one secret in the app,
/// so it lives in the Keychain; everything else is derived or stored beside it.
public struct PhoneIdentity: Sendable, Equatable, Codable {
    public var deviceId: String
    public var publicKey: String
    public var privateKey: String
    public var accessToken: String

    public init(deviceId: String, publicKey: String, privateKey: String, accessToken: String) {
        self.deviceId = deviceId
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.accessToken = accessToken
    }
}

public enum PhoneIdentityStore {
    private static let service = "io.github.fei2411.dsbot"
    private static let account = "phone.identity"

    /// The stored identity, or a fresh one saved in its place.
    public static func loadOrCreate() -> PhoneIdentity {
        if let existing = load() { return existing }
        let identity = make()
        save(identity)
        return identity
    }

    private static func make() -> PhoneIdentity {
        // X25519, the key agreement the Noise suite uses; not the signing key type.
        let key = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = Base64URL.encode(key.publicKey.rawRepresentation)
        let privateKey = Base64URL.encode(key.rawRepresentation)
        let deviceId = (try? PairingLink.deviceId(forHostKey: publicKey)) ?? "d-unknown"
        return PhoneIdentity(
            deviceId: deviceId,
            publicKey: publicKey,
            privateKey: privateKey,
            accessToken: randomToken()
        )
    }

    /// The Relay refuses a token shorter than 32 characters.
    private static func randomToken() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<40).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    private static func load() -> PhoneIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let identity = try? JSONDecoder().decode(PhoneIdentity.self, from: data)
        else { return nil }
        return identity
    }

    private static func save(_ identity: PhoneIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
}

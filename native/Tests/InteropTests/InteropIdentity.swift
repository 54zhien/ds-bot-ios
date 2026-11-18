import CryptoKit
import Foundation

/// The device id the Relay recomputes from an identity key, so a phone that derives it
/// differently is refused with AUTH_INVALID before any handshake starts.
enum InteropIdentity {
    /// keys.ts: `d-` + base64url(sha256(raw X25519 public key)[0..<16]).
    static func deviceId(for publicKey: Data) -> String {
        let digest = Data(SHA256.hash(data: publicKey))
        return "d-" + Base64URL.encode(digest.prefix(16))
    }
}

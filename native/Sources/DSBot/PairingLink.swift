import CryptoKit
import Foundation

/// What the computer's QR code carries to the phone (link/src/pairing.ts PairingOffer).
public struct PairingOffer: Sendable, Equatable {
    public var serverURL: URL
    public var hostDeviceId: String
    public var hostKey: String
    public var code: String
    public var name: String

    public init(serverURL: URL, hostDeviceId: String, hostKey: String, code: String, name: String) {
        self.serverURL = serverURL
        self.hostDeviceId = hostDeviceId
        self.hostKey = hostKey
        self.code = code
        self.name = name
    }
}

public enum PairingLinkError: Error, Equatable, CustomStringConvertible {
    case notAPairingLink
    case unsupportedVersion(String)
    case missingField(String)
    case invalidServer
    case keyMismatch

    public var description: String {
        switch self {
        case .notAPairingLink:
            return "This is not a DS Bot pairing link."
        case .unsupportedVersion(let version):
            return "The pairing link speaks version \(version); this app speaks version 1."
        case .missingField(let name):
            return "The pairing link has no \(name)."
        case .invalidServer:
            return "The pairing link names a Server that is not ws:// or wss://."
        case .keyMismatch:
            return "The pairing link does not match the computer it names."
        }
    }

    /// What a person can act on, shown next to the field they pasted into. The raw
    /// description stays English for the diagnostics dump and the tests.
    public var explanation: String {
        switch self {
        case .notAPairingLink:
            return NativeLanguage.text("This is not a DS Bot pairing link.")
        case .unsupportedVersion(let version):
            return NativeLanguage.text("The pairing link speaks version {version}; this app speaks version 1.", ["version": version])
        case .missingField(let name):
            return NativeLanguage.text("The pairing link has no {name}.", ["name": name])
        case .invalidServer:
            return NativeLanguage.text("The pairing link names a Server that is not ws:// or wss://.")
        case .keyMismatch:
            return NativeLanguage.text("The pairing link does not match the computer it names.")
        }
    }
}

/// dsbot://pair?v=1&server=…&host=…&key=…&code=…&name=…
/// The field names are the ones pairing.ts writes; nothing here is invented.
public enum PairingLink {
    public static let scheme = "dsbot"
    public static let pairHost = "pair"

    public static func parse(_ text: String) throws -> PairingOffer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else {
            throw PairingLinkError.notAPairingLink
        }
        guard components.scheme?.lowercased() == scheme, components.host?.lowercased() == pairHost else {
            throw PairingLinkError.notAPairingLink
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        func required(_ name: String) throws -> String {
            guard let found = value(name), !found.isEmpty else {
                throw PairingLinkError.missingField(name)
            }
            return found
        }

        let version = try required("v")
        guard version == "1" else { throw PairingLinkError.unsupportedVersion(version) }

        let server = try required("server")
        guard let serverURL = URL(string: server),
              let serverScheme = serverURL.scheme?.lowercased(),
              serverScheme == "ws" || serverScheme == "wss"
        else {
            throw PairingLinkError.invalidServer
        }

        let hostDeviceId = try required("host")
        let key = try required("key")
        let code = try required("code")
        let name = String((value("name") ?? "").prefix(64))
        guard (try? deviceId(forHostKey: key)) == hostDeviceId else {
            throw PairingLinkError.keyMismatch
        }
        return PairingOffer(serverURL: serverURL, hostDeviceId: hostDeviceId, hostKey: key, code: code, name: name)
    }

    /// The string a computer shows in its QR code, useful for tests and diagnostics.
    public static func make(_ offer: PairingOffer) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = pairHost
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "server", value: offer.serverURL.absoluteString),
            URLQueryItem(name: "host", value: offer.hostDeviceId),
            URLQueryItem(name: "key", value: offer.hostKey),
            URLQueryItem(name: "code", value: offer.code),
            URLQueryItem(name: "name", value: offer.name),
        ]
        return components.string ?? ""
    }

    /// keys.ts: \`d-\` + base64url(sha256(raw X25519 public key)[0..<16]).
    public static func deviceId(forHostKey key: String) throws -> String {
        let raw = try Base64URL.decode(key)
        guard raw.count == 32 else {
            throw PairingLinkError.keyMismatch
        }
        let digest = Data(SHA256.hash(data: raw))
        return "d-" + Base64URL.encode(digest.prefix(16))
    }
}

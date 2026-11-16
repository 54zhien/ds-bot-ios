import Foundation

/// The last pairing, kept in UserDefaults: a server address, a device id, a public
/// key and a one-shot code. None of it is secret, so none of it goes to the Keychain.
public struct PairingStore {
    private struct Stored: Codable {
        var server: String
        var hostDeviceId: String
        var hostKey: String
        var code: String
        var name: String
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "dsbot.pairing.offer") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PairingOffer? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let url = URL(string: stored.server)
        else { return nil }
        return PairingOffer(serverURL: url, hostDeviceId: stored.hostDeviceId, hostKey: stored.hostKey, code: stored.code, name: stored.name)
    }

    public func save(_ offer: PairingOffer) {
        let stored = Stored(
            server: offer.serverURL.absoluteString,
            hostDeviceId: offer.hostDeviceId,
            hostKey: offer.hostKey,
            code: offer.code,
            name: offer.name
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

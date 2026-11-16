import Foundation

/// Paired computers. The one-shot code is discarded once pairing succeeds.
public struct PairingStore {
    private struct Stored: Codable {
        var server: String
        var hostDeviceId: String
        var hostKey: String
        var code: String
        var name: String

        init(_ offer: PairingOffer) {
            server = offer.serverURL.absoluteString
            hostDeviceId = offer.hostDeviceId
            hostKey = offer.hostKey
            code = ""
            name = offer.name
        }

        var offer: PairingOffer? {
            guard let url = URL(string: server) else { return nil }
            return PairingOffer(serverURL: url, hostDeviceId: hostDeviceId, hostKey: hostKey, code: "", name: name)
        }
    }

    private struct StoredList: Codable {
        var activeId: String?
        var computers: [Stored]
    }

    private let defaults: UserDefaults
    private let key: String
    private var listKey: String { key + "s" }

    public init(defaults: UserDefaults = .standard, key: String = "dsbot.pairing.offer") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PairingOffer? {
        let list = readList()
        return (list.computers.first { $0.hostDeviceId == list.activeId } ?? list.computers.first)?.offer
    }

    public func all() -> [PairingOffer] {
        readList().computers.compactMap(\.offer)
    }

    public func save(_ offer: PairingOffer) {
        var list = readList()
        let stored = Stored(offer)
        if let index = list.computers.firstIndex(where: { $0.hostDeviceId == offer.hostDeviceId }) {
            list.computers[index] = stored
        } else {
            list.computers.append(stored)
        }
        list.activeId = offer.hostDeviceId
        writeList(list)
    }

    public func activate(_ hostDeviceId: String) {
        var list = readList()
        guard list.computers.contains(where: { $0.hostDeviceId == hostDeviceId }) else { return }
        list.activeId = hostDeviceId
        writeList(list)
    }

    public func remove(_ hostDeviceId: String) {
        var list = readList()
        list.computers.removeAll { $0.hostDeviceId == hostDeviceId }
        if list.activeId == hostDeviceId { list.activeId = list.computers.first?.hostDeviceId }
        writeList(list)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: listKey)
    }

    private func readList() -> StoredList {
        if let data = defaults.data(forKey: listKey),
           let list = try? JSONDecoder().decode(StoredList.self, from: data) {
            return list
        }
        if let data = defaults.data(forKey: key),
           let old = try? JSONDecoder().decode(Stored.self, from: data) {
            return StoredList(activeId: old.hostDeviceId, computers: [old])
        }
        return StoredList(activeId: nil, computers: [])
    }

    private func writeList(_ list: StoredList) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: listKey)
        defaults.removeObject(forKey: key)
    }
}

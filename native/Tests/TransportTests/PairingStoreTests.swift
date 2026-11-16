import Foundation
import XCTest
@testable import DSBot

final class PairingStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "dsbot.tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testASavedOfferComesBackUnchanged() {
        let store = PairingStore(defaults: defaults)
        let offer = PairingOffer(
            serverURL: URL(string: "wss://relay.example.com:8787/v1/link")!,
            hostDeviceId: "d-host",
            hostKey: "key",
            code: "code-1",
            name: "Desk"
        )
        store.save(offer)
        XCTAssertEqual(store.load()?.hostDeviceId, offer.hostDeviceId)
        XCTAssertEqual(store.load()?.serverURL, offer.serverURL)
        XCTAssertEqual(store.load()?.code, "", "a used pairing code must not survive a restart")
    }

    func testTwoComputersCanBeSwitchedAndOneForgotten() {
        let store = PairingStore(defaults: defaults)
        let first = PairingOffer(
            serverURL: URL(string: "wss://first.example/v1/link")!,
            hostDeviceId: "d-first", hostKey: "first-key", code: "once", name: "First"
        )
        let second = PairingOffer(
            serverURL: URL(string: "wss://second.example/v1/link")!,
            hostDeviceId: "d-second", hostKey: "second-key", code: "once", name: "Second"
        )
        store.save(first)
        store.save(second)
        XCTAssertEqual(store.all().map(\.hostDeviceId), ["d-first", "d-second"])
        XCTAssertEqual(store.load()?.hostDeviceId, "d-second")
        store.activate("d-first")
        XCTAssertEqual(store.load()?.hostDeviceId, "d-first")
        store.remove("d-first")
        XCTAssertEqual(store.load()?.hostDeviceId, "d-second")
    }

    func testClearingLeavesNothingToReconnectTo() {
        let store = PairingStore(defaults: defaults)
        store.save(PairingOffer(
            serverURL: URL(string: "wss://relay.example.com:8787/v1/link")!,
            hostDeviceId: "d-host",
            hostKey: "key",
            code: "code-1",
            name: "Desk"
        ))
        store.clear()
        XCTAssertNil(store.load(), "a cleared store must not hand a pairing to the next launch")
    }
}

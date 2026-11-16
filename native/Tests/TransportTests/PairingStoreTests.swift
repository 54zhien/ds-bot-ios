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
        XCTAssertEqual(store.load(), offer)
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

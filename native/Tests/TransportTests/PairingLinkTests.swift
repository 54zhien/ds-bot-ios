import Foundation
import XCTest
@testable import DSBot

final class PairingLinkTests: XCTestCase {
    func testAValidLinkRoundTrips() throws {
        let hostKey = Base64URL.encode(Data((0..<32).map { UInt8($0) }))
        let hostDeviceId = try PairingLink.deviceId(forHostKey: hostKey)
        let offer = PairingOffer(
            serverURL: URL(string: "wss://relay.example.com:8787/v1/link")!,
            hostDeviceId: hostDeviceId,
            hostKey: hostKey,
            code: "pair-1",
            name: "Desk"
        )
        let parsed = try PairingLink.parse(PairingLink.make(offer))
        XCTAssertEqual(parsed, offer)
    }

    func testAMissingFieldNamesItself() {
        let text = "dsbot://pair?v=1&server=wss%3A%2F%2Frelay.example.com&host=d-x&code=abc"
        XCTAssertThrowsError(try PairingLink.parse(text)) { error in
            XCTAssertEqual(error as? PairingLinkError, .missingField("key"))
        }
    }

    func testAnotherSchemeIsNotAPairingLink() {
        XCTAssertThrowsError(try PairingLink.parse("https://pair?v=1&server=wss%3A%2F%2Frelay.example.com")) { error in
            XCTAssertEqual(error as? PairingLinkError, .notAPairingLink)
        }
    }

    func testSchemeAndHostAreCaseInsensitive() throws {
        let hostKey = Base64URL.encode(Data(repeating: 0x33, count: 32))
        let hostDeviceId = try PairingLink.deviceId(forHostKey: hostKey)
        let text = "DSBOT://PAIR?v=1&server=wss%3A%2F%2Frelay.example.com&host=\(hostDeviceId)&key=\(hostKey)&code=abc&name=Desk"
        let parsed = try PairingLink.parse(text)
        XCTAssertEqual(parsed.hostDeviceId, hostDeviceId)
        XCTAssertEqual(parsed.name, "Desk")
    }

    func testAKeyThatDoesNotMatchItsComputerIsRejected() {
        let hostKey = Base64URL.encode(Data(repeating: 0x44, count: 32))
        let text = "dsbot://pair?v=1&server=wss%3A%2F%2Frelay.example.com&host=d-someone-else&key=\(hostKey)&code=abc"
        XCTAssertThrowsError(try PairingLink.parse(text)) { error in
            XCTAssertEqual(error as? PairingLinkError, .keyMismatch)
        }
    }
}

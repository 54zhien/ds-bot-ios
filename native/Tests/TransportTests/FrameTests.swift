import XCTest
@testable import DSBot

final class FrameTests: XCTestCase {
    private struct Probe: Codable, Sendable, Equatable {
        var ok: Bool
    }

    func testEnvelopeCarriesVersionAndType() {
        let frame = ControlFrame(type: .hello, payload: Probe(ok: true), id: "fixed", timestamp: 1)
        XCTAssertEqual(frame.v, ProtocolLimits.version)
        XCTAssertEqual(frame.type, .hello)
        XCTAssertEqual(frame.id, "fixed")
        XCTAssertEqual(frame.timestamp, 1)
        XCTAssertEqual(frame.payload, Probe(ok: true))
    }

    func testFrameTypeRawValuesMatchTheWire() {
        XCTAssertEqual(ControlFrameType.helloAck.rawValue, "hello.ack")
        XCTAssertEqual(ControlFrameType.connectRequest.rawValue, "connect.request")
        XCTAssertEqual(ControlFrameType.secureHandshake.rawValue, "secure.handshake")
        XCTAssertEqual(ControlFrameType.relay.rawValue, "relay")
    }
}

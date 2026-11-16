import XCTest
@testable import DSBot

final class FramesTests: XCTestCase {
    // MARK: - Envelope

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
        XCTAssertEqual(MessageType.rpcRequest.rawValue, "rpc.request")
    }

    // MARK: - Vectors (docs/link-test-vectors/frames.json)

    func testFramesMatchTheVectorsByteForByte() throws {
        let fixture = try VectorFixture.load()
        XCTAssertFalse(fixture.frames.isEmpty, "frames.json listed no frames")
        for vector in fixture.frames {
            let payloadData = try JSONEncoder().encode(vector.payload)
            let encoded: String
            switch vector.decoded.type {
            case ControlFrameType.hello.rawValue:
                let payload = try JSONDecoder().decode(HelloPayload.self, from: payloadData)
                encoded = try FrameCodec.encode(ControlFrame(type: .hello, payload: payload, id: vector.decoded.id, timestamp: vector.decoded.timestamp))
            case ControlFrameType.relay.rawValue:
                let payload = try JSONDecoder().decode(RelayPayload.self, from: payloadData)
                encoded = try FrameCodec.encode(ControlFrame(type: .relay, payload: payload, id: vector.decoded.id, timestamp: vector.decoded.timestamp))
            case ControlFrameType.error.rawValue:
                let payload = try JSONDecoder().decode(ControlErrorPayload.self, from: payloadData)
                encoded = try FrameCodec.encode(ControlFrame(type: .error, payload: payload, id: vector.decoded.id, timestamp: vector.decoded.timestamp))
            default:
                XCTFail("frames.json has a frame type this suite does not cover: \(vector.decoded.type)")
                continue
            }
            XCTAssertEqual(encoded, vector.encoded, "encoded bytes differ for \(vector.name)")
            XCTAssertEqual(encoded.utf8.count, vector.encodedBytes, "encoded size differs for \(vector.name)")
        }
    }

    func testDecodedVectorsCarryTheSameFields() throws {
        let fixture = try VectorFixture.load()
        for vector in fixture.frames {
            let frame = try FrameCodec.decode(vector.encoded)
            XCTAssertEqual(frame.v, vector.decoded.v, "v differs for \(vector.name)")
            XCTAssertEqual(frame.id, vector.decoded.id, "id differs for \(vector.name)")
            XCTAssertEqual(frame.type.rawValue, vector.decoded.type, "type differs for \(vector.name)")
            XCTAssertEqual(frame.timestamp, vector.decoded.timestamp, "timestamp differs for \(vector.name)")
        }
    }

    func testRelayCiphertextIsBase64URLOfTheKnownBytes() throws {
        let fixture = try VectorFixture.load()
        guard let vector = fixture.frames.first(where: { $0.type == ControlFrameType.relay.rawValue }),
              let expectedHex = vector.ciphertextSourceHex,
              let ciphertext = vector.payload["ciphertext"]?.stringValue
        else {
            throw XCTSkip("frames.json has no relay frame with ciphertextSourceHex")
        }
        let bytes = try Base64URL.decode(ciphertext)
        XCTAssertEqual(Hex.string(bytes), expectedHex)
        XCTAssertEqual(Base64URL.encode(bytes), ciphertext)
    }

    // MARK: - Limits

    func testFrameLargerThanTheNegotiatedLimitIsRejected() {
        let frame = ControlFrame(type: .hello, payload: HelloPayload(deviceId: "d", identityKey: "k", accessToken: "t"), id: "x", timestamp: 1)
        XCTAssertNoThrow(try FrameCodec.encode(frame))
        XCTAssertThrowsError(try FrameCodec.encode(frame, limits: ControlFrameLimits(maxControlFrameBytes: 16))) { error in
            XCTAssertEqual((error as? TransportError)?.code, .frameTooLarge)
        }
    }

    func testDecodeRejectsForeignVersionAndUnknownType() {
        XCTAssertThrowsError(try FrameCodec.decode("{\"v\":2,\"id\":\"a\",\"type\":\"hello\",\"timestamp\":1,\"payload\":{}}"))
        XCTAssertThrowsError(try FrameCodec.decode("{\"v\":1,\"id\":\"a\",\"type\":\"nope\",\"timestamp\":1,\"payload\":{}}"))
        XCTAssertThrowsError(try FrameCodec.decode("{\"v\":1,\"id\":\"\",\"type\":\"hello\",\"timestamp\":1,\"payload\":{}}"))
    }
}

// MARK: - Fixtures

private enum Hex {
    static func string(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private struct VectorFixture: Decodable {
    struct Frame: Decodable {
        struct Decoded: Decodable {
            let v: Int
            let id: String
            let type: String
            let timestamp: Int
        }

        let name: String
        let encoded: String
        let encodedBytes: Int
        let decoded: Decoded
        let payload: JSONValue
        let ciphertextSourceHex: String?

        var type: String { decoded.type }
    }

    let timestamp: Int
    let frames: [Frame]

    /// The vectors live at the repo root, not in the test bundle: walk up from this
    /// file until docs/link-test-vectors/frames.json is found.
    static func load() throws -> VectorFixture {
        guard let url = locate() else {
            throw XCTSkip("docs/link-test-vectors/frames.json is not reachable from \(#filePath)")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VectorFixture.self, from: data)
    }

    private static func locate() -> URL? {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            directory.deleteLastPathComponent()
            let candidate = directory.appendingPathComponent("docs/link-test-vectors/frames.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

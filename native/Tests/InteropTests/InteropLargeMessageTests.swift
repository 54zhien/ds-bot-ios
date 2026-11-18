import CryptoKit
import Foundation
import XCTest

/// A phone that only ever sees short replies still reports itself online while the chat
/// stays empty: a state reply is many fragments long, and one that cannot be stitched
/// back together looks exactly like a host with no Bots. These cases drive the fragment
/// path in both directions against the CI host.
final class InteropLargeMessageTests: XCTestCase {
    private static let bots = 40

    /// Host to phone: the reply only comes back whole if the fragments were joined in
    /// order, so every Bot is checked against its own index.
    func testTheStateReplyArrivesWhole() async throws {
        try await withConnection { harness in
            let reply = try await harness.rpc.call("bot", params: .object([
                "endpoint": .string("state"),
                "payload": .object(["since": .number(-1), "avatars": .string("ref"), "live": .null]),
            ]))
            XCTAssertEqual(reply["ok"], JSONValue.bool(true), "the host answers ok: true")

            // The size comes first: a fixture that quietly shrinks back under one fragment
            // leaves every assertion below passing while nothing is being tested.
            let largest = try XCTUnwrap(harness.delivered.all.max(), "the channel delivered the reply")
            XCTAssertGreaterThan(
                largest, ProtocolLimits.secureFragmentChunkBytes,
                "the state reply has to cross the fragment size"
            )

            let value = try XCTUnwrap(reply["value"], "the fixture state rides under value")
            guard case .array(let bots)? = value["bots"] else {
                return XCTFail("state carries a bots array, got \(String(describing: value["bots"]))")
            }
            XCTAssertEqual(bots.count, InteropLargeMessageTests.bots, "the fixture sends forty Bots")
            XCTAssertEqual(
                bots.compactMap { $0["id"]?.stringValue },
                (0..<InteropLargeMessageTests.bots).map { "bot-" + String(format: "%02d", $0) },
                "every Bot arrived at its own index"
            )
            XCTAssertEqual(bots.first?["name"]?.stringValue, "Fixture Bot 0")
            XCTAssertEqual(bots.last?["name"]?.stringValue, "Fixture Bot 39")
            XCTAssertEqual(value["revision"]?.intValue, 7, "the whole state came through, not just the bots")
        }
    }

    /// Phone to host: one Noise message holds at most 65 535 bytes, so a long request can
    /// only leave the phone in fragments. The host answers with what it read, which is the
    /// only proof that the pieces arrived whole.
    func testALargeRequestReachesTheHostWhole() async throws {
        try await withConnection { harness in
            var text = ""
            let line = "the phone has to fragment this request "
            while text.utf8.count < 120_000 { text += line }
            XCTAssertGreaterThan(
                text.utf8.count, ProtocolLimits.secureFragmentChunkBytes,
                "the request has to cross the fragment size"
            )

            let reply = try await harness.rpc.call("interop.echo", params: .object(["text": .string(text)]))
            XCTAssertEqual(reply["ok"], JSONValue.bool(true), "the host answers ok: true")
            XCTAssertEqual(reply["bytes"]?.intValue, text.utf8.count, "the host counted every byte it was sent")
            let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(reply["sha256"]?.stringValue, digest, "the host read the same bytes")
            XCTAssertEqual(reply["head"]?.stringValue, String(text.prefix(16)))
            XCTAssertEqual(reply["tail"]?.stringValue, String(text.suffix(16)))
        }
    }

    /// Builds one connection, runs the case, and closes the socket even when the case throws.
    private func withConnection(_ body: (InteropHarness) async throws -> Void) async throws {
        let harness = try await InteropHarness.connect()
        do {
            try await body(harness)
        } catch {
            await harness.close()
            throw error
        }
        await harness.close()
    }
}

import XCTest
@testable import DSBot

/// The dump leaves the phone as text, so it is the one thing that must not carry the
/// pairing code or a session key with it.
final class DiagnosticsTests: XCTestCase {
    func testAHelloIsWrittenDownWithoutItsPairingCode() async {
        let sent = Data("{\"name\":\"DS Bot\",\"pairingCode\":\"code-123\"}".utf8)
        let received = Data("{\"name\":\"CI Desk\"}".utf8)
        await Diagnostics.shared.recordHandshake(sent: sent, received: received)

        let text = await Diagnostics.shared.text()
        XCTAssertFalse(text.contains("code-123"), "a pairing code must never be written down")
        XCTAssertTrue(text.contains("<redacted>"))
        XCTAssertTrue(text.contains("CI Desk"), "the host name is what identifies the computer")
    }

    func testAHelloThatIsNotJSONIsNotWrittenOutAtAll() async {
        // A broken hello could carry a code in clear text, and there would be no key to
        // redact it by.
        await Diagnostics.shared.recordHandshake(sent: Data("code-123 is not json".utf8), received: Data())
        let text = await Diagnostics.shared.text()
        XCTAssertFalse(text.contains("code-123"))
        XCTAssertTrue(text.contains("not JSON"))
    }

    func testTheStateSummaryNamesEveryKeyItSaw() async throws {
        await Diagnostics.shared.recordCall(
            method: "bot", endpoint: "state", milliseconds: 12, errorCode: nil, errorMessage: nil,
            reply: .object([
                "ok": .bool(true),
                "value": .object([
                    "bots": .array([.null, .null]),
                    "revision": .number(7),
                    "liveKey": .string("k"),
                ]),
            ])
        )

        let text = await Diagnostics.shared.text()
        let document = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let keys = (document?["state"] as? [String: Any])?["keys"] as? [String: Any]
        XCTAssertEqual((keys?["bots"] as? [String: Any])?["type"] as? String, "array")
        XCTAssertEqual((keys?["bots"] as? [String: Any])?["count"] as? Int, 2)
        XCTAssertEqual((keys?["revision"] as? [String: Any])?["type"] as? String, "number")
        XCTAssertEqual((keys?["liveKey"] as? [String: Any])?["length"] as? Int, 1)
        XCTAssertNil(keys?["value"], "the reply is described one level down, not by its envelope")
    }

    func testADumpLandsWhereTheUpdatesPageLooksForIt() throws {
        let url = try DiagnosticsStore.write("{\"ok\":true}")

        XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"))
        XCTAssertEqual(url.lastPathComponent.count, "20260101-000000.json".count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let latest = DiagnosticsStore.latest()?.lastPathComponent ?? ""
        XCTAssertGreaterThanOrEqual(latest, url.lastPathComponent, "the newest dump is the one the page shows")
        try? FileManager.default.removeItem(at: url)
    }
}

import XCTest
@testable import DSBot

/// The screen reads userText; the raw code and message belong to the diagnostics
/// dump. link.ts errorText pins the React Native mapping, this pins the native one.
final class ErrorTextTests: XCTestCase {
    func testTheWireCodesMapToTheirOwnCases() {
        XCTAssertEqual(TransportError.code(forWire: "NOT_PAIRED"), .notPaired)
        XCTAssertEqual(TransportError.code(forWire: "PAIRING_REJECTED"), .pairingRejected)
        XCTAssertEqual(TransportError.code(forWire: "HOST_OFFLINE"), .hostOffline)
        XCTAssertEqual(TransportError.code(forWire: "SERVER_UNREACHABLE"), .serverUnreachable)
        XCTAssertEqual(TransportError.code(forWire: "bot/not-found"), .invalidFrame)
        XCTAssertEqual(TransportError.code(forWire: nil), .invalidFrame)
    }

    func testKnownCodesReadAsSentences() {
        XCTAssertEqual(
            TransportError(.notPaired, "NOT_PAIRED").userText,
            NativeLanguage.text("This phone is not paired with the computer yet."))
        XCTAssertEqual(
            TransportError(.pairingRejected, "refused").userText,
            NativeLanguage.text("The computer did not accept this phone. Show a new QR code on the computer and scan it again."))
        XCTAssertEqual(TransportError(.hostOffline, "").userText, NativeLanguage.text("Could not reach your computer."))
        XCTAssertEqual(TransportError(.serverUnreachable, "").userText, NativeLanguage.text("Could not reach your computer."))
        XCTAssertEqual(
            TransportError(.timeout, "The call timed out.").userText,
            NativeLanguage.text("The computer did not answer."))
        XCTAssertEqual(
            TransportError(.notConnected, "The link is not connected.").userText,
            NativeLanguage.text("Not connected to the computer yet."))
    }

    func testPairingIsTheOnlyWayOutOfARefusedIdentity() {
        XCTAssertTrue(TransportError(.notPaired, "").needsPairing)
        XCTAssertTrue(TransportError(.pairingRejected, "").needsPairing)
        XCTAssertFalse(TransportError(.timeout, "").needsPairing)
        XCTAssertFalse((NSError(domain: "DSBot", code: 1) as Error).needsPairing)
    }

    func testTheScreensWordsNeverCarryTheTransportEnumName() {
        let unknown = TransportError(.invalidFrame, "The host refused.", wireCode: "bot/not-found")
        XCTAssertEqual(
            unknown.userText,
            NativeLanguage.text("Something went wrong ({code}).", ["code": "bot/not-found"]))
        let bare = TransportError(.invalidFrame, "The relay connection has not been authorized.").userText
        XCTAssertEqual(bare, NativeLanguage.text("Something went wrong."))
        XCTAssertFalse(bare.contains("invalidFrame"))
    }

    /// Every screen reads localizedDescription, so the words must travel that way too.
    func testLocalizedDescriptionFollowsTheWords() {
        let error = TransportError(.timeout, "The call timed out.") as Error
        XCTAssertEqual(error.localizedDescription, error.userText)
    }

    func testOtherErrorsPassTheirOwnWordsThrough() {
        let plain = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Own words."]) as Error
        XCTAssertEqual(plain.userText, "Own words.")
    }
}

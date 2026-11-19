import XCTest
@testable import DSBot

final class ChatTimelineTests: XCTestCase {
    func testAnsweredQuestionShowsTheSavedSelection() {
        let row = ChatRow(.object([
            "kind": .string("answer"),
            "title": .string("Choose a route"),
            "answers": .array([.object([
                "selected": .array([.string("Train")]),
                "custom": .string("Window seat"),
            ])]),
        ]))
        XCTAssertEqual(row.text, "Train, Window seat")
    }

    func testClosedQuestionShowsItsOutcome() {
        let row = ChatRow(.object([
            "kind": .string("closed"),
            "question": .object(["question": .string("Continue?")]),
            "closed": .string("replied"),
        ]))
        XCTAssertEqual(row.text, "Continue?\nAnswered by message")
    }

    func testEventShowsFailureReasonAndRelayPause() {
        let event = ChatRow(.object([
            "kind": .string("event"), "name": .string("Aster"), "event": .string("failed"),
            "text": .string("No key"),
        ]))
        XCTAssertEqual(event.text, NativeLanguage.text("{name} could not answer: {reason}",
                                                       ["name": "Aster", "reason": "No key"]))
        let relay = ChatRow(.object([
            "kind": .string("relay"),
            "reply": .object(["kind": .string("paused"), "name": .string("Aster"),
                              "idle": .bool(true), "count": .number(3),
                              "names": .array([.string("Nova")])]),
        ]))
        XCTAssertTrue(relay.text.contains("3"))
        XCTAssertTrue(relay.text.contains("Nova"))
    }

    func testUnrecognizedRelayIsOmittedFromTimeline() {
        let page = ChatPage(.object(["items": .array([
            .object(["kind": .string("relay"), "reply": .object(["event": .string("unknown")])]),
            .object(["kind": .string("user"), "text": .string("Hello")]),
        ])]))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.text, "Hello")
    }

    func testHistoricalViewKeepsRootForReadOnlyOpening() {
        let root: JSONValue = .object(["type": .string("text"), "text": .string("Result")])
        let row = ChatRow(.object([
            "kind": .string("view"), "title": .string("Report"), "view": root,
        ]))
        XCTAssertEqual(row.text, "Report")
        XCTAssertEqual(row.viewRecord?["view"], root)
        XCTAssertEqual(row.viewRecord?["title"], .string("Report"))
    }

    func testLocalPhotoRowRetainsPreviewWithoutAddingCountToText() {
        let image = Data([1, 2, 3])
        let row = ChatRow(localID: UUID(), text: "", localImageData: [image], failureReason: nil)
        XCTAssertEqual(row.imageCount, 1)
        XCTAssertEqual(row.localImageData, [image])
        XCTAssertEqual(row.text, "")
    }

    func testSavedPhotoOnlyMessageUsesImageWithoutCountText() {
        let row = ChatRow(.object([
            "kind": .string("user"),
            "imageRefs": .array([.object(["attachmentId": .string("photo-1")])]),
        ]))
        XCTAssertEqual(row.imageCount, 1)
        XCTAssertEqual(row.text, "")
    }

    func testUserRowReadsItsViaPlatform() {
        let row = ChatRow(.object([
            "kind": .string("user"), "text": .string("Hi"), "via": .string("weixin"),
        ]))
        XCTAssertEqual(row.via, "weixin")
        XCTAssertNil(ChatRow(.object(["kind": .string("user"), "text": .string("Hi")])).via)
        XCTAssertNil(ChatRow(localID: UUID(), text: "Hi", localImageData: [], failureReason: nil).via)
    }

    func testViaTagNamesThePlatformAndFallsBackToItsId() {
        XCTAssertEqual(ChatRow.viaTagText("weixin"), "via WeChat")
        XCTAssertEqual(ChatRow.viaTagText("matrix"), "via matrix")
    }

    func testPhotosOnlyRowsShowBare() {
        let bare = ChatRow(.object([
            "kind": .string("user"),
            "imageRefs": .array([.object(["attachmentId": .string("photo-1")])]),
        ]))
        XCTAssertTrue(bare.photosOnly)
        XCTAssertTrue(ChatRow(localID: UUID(), text: "", localImageData: [Data([1])], failureReason: nil).photosOnly)
        XCTAssertFalse(ChatRow(.object([
            "kind": .string("user"), "text": .string("Look"),
            "imageRefs": .array([.object(["attachmentId": .string("photo-1")])]),
        ])).photosOnly)
        XCTAssertFalse(ChatRow(.object([
            "kind": .string("user"), "text": .string(""),
            "files": .array([.object(["name": .string("notes.txt")])]),
            "imageRefs": .array([.object(["attachmentId": .string("photo-1")])]),
        ])).photosOnly)
        XCTAssertFalse(ChatRow(.object([
            "kind": .string("bot"),
            "imageRefs": .array([.object(["attachmentId": .string("photo-1")])]),
        ])).photosOnly)
    }
}

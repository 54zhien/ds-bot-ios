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
}

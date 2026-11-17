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
}

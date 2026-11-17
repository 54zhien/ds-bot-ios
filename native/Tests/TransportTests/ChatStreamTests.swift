import XCTest
@testable import DSBot

final class ChatStreamTests: XCTestCase {
    private func event(_ session: String, _ attempt: String, phase: String? = nil,
                       text: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = [
            "sessionId": .string(session), "attemptId": .string(attempt),
        ]
        if let phase { value["phase"] = .string(phase) }
        if let text { value["text"] = .string(text) }
        return .object(value)
    }

    func testSeparateAttemptsStayVisibleUntilEachEnds() {
        var stream = ChatStream()
        XCTAssertTrue(stream.receive(event("chat", "a", phase: "start"), for: "chat"))
        XCTAssertTrue(stream.receive(event("chat", "a", text: "First"), for: "chat"))
        XCTAssertTrue(stream.receive(event("chat", "b", phase: "start"), for: "chat"))
        XCTAssertTrue(stream.receive(event("chat", "b", text: "Second"), for: "chat"))
        XCTAssertEqual(stream.text, "First\n\nSecond")
        XCTAssertTrue(stream.receive(event("chat", "a", phase: "end"), for: "chat"))
        XCTAssertEqual(stream.text, "Second")
        XCTAssertTrue(stream.receive(event("chat", "b", phase: "end"), for: "chat"))
        XCTAssertEqual(stream.text, "")
    }

    func testAnotherChatCannotChangeTheVisibleReply() {
        var stream = ChatStream()
        XCTAssertTrue(stream.receive(event("chat", "a", text: "Hello"), for: "chat"))
        XCTAssertFalse(stream.receive(event("other", "b", text: "Hidden"), for: "chat"))
        XCTAssertEqual(stream.text, "Hello")
        stream.clear()
        XCTAssertEqual(stream.text, "")
        XCTAssertNil(stream.sessionID)
    }
}

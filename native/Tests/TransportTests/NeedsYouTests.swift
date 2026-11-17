import XCTest
@testable import DSBot

final class NeedsYouTests: XCTestCase {
    func testTeamPendingCountMatchesVisibleActionKinds() {
        let state = JSONValue.object([
            "questions": .object(["one": .object([:]), "two": .object([:])]),
            "work": .object(["approvals": .array([
                .object(["answerable": .bool(true)]),
                .object(["answerable": .bool(false)]),
            ])]),
            "secretRequests": .object(["bot": .array([
                .object(["status": .string("pending")]),
                .object(["status": .string("resolved")]),
            ])]),
            "browserHolds": .object(["bot": .object(["callId": .string("call")])]),
            "views": .object(["session": .object([:])]),
        ])
        XCTAssertEqual(NeedsYouViewController.count(in: state), 6)
    }
}

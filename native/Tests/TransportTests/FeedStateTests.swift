import XCTest
@testable import DSBot

/// The host restarts its notices and keeps only a ring of them, so the read
/// position must answer resets honestly: one full read, from the start, once.
/// The wiring itself waits for the chat screen's window.
final class FeedStateTests: XCTestCase {
    private func reply(seq: Int?, reset: Bool, boot: String = "b1") -> JSONValue {
        var object: [String: JSONValue] = ["boot": .string(boot)]
        if let seq { object["seq"] = .number(Double(seq)) }
        if reset { object["reset"] = .bool(true) }
        return .object(object)
    }

    func testAResetClearsThePositionAndAsksForOneRead() {
        var state = FeedState(boot: "b1")
        _ = state.receive(reply(seq: 5, reset: false))
        XCTAssertTrue(state.receive(reply(seq: 1, reset: true, boot: "b2")))
        // The position is gone, so the next call reads from the start.
        XCTAssertEqual(state.parameters()["since"]?.intValue, 0)
        XCTAssertEqual(state.parameters()["boot"]?.stringValue, "b2")
    }

    func testThePositionFollowsTheHostSequence() {
        var state = FeedState(boot: "b1")
        _ = state.receive(reply(seq: 5, reset: false))
        XCTAssertEqual(state.parameters()["since"]?.intValue, 5)
        // Nothing moves between reads: no reset, no spurious catch-up.
        _ = state.receive(reply(seq: 5, reset: false))
        XCTAssertEqual(state.parameters()["since"]?.intValue, 5)
        _ = state.receive(reply(seq: 9, reset: false))
        XCTAssertEqual(state.parameters()["since"]?.intValue, 9)
    }

    func testConsecutiveResetsReadOnce() {
        var state = FeedState(boot: "b1")
        XCTAssertTrue(state.receive(reply(seq: 1, reset: true, boot: "b2")))
        XCTAssertFalse(state.receive(reply(seq: 1, reset: true)),
                       "a second reset while a read is due queues no second read")
    }

    func testAnOrdinaryReplyRearmsTheNextReset() {
        var state = FeedState(boot: "b1")
        XCTAssertTrue(state.receive(reply(seq: 1, reset: true, boot: "b2")))
        // The catch-up read lands and the host answers normally again.
        XCTAssertFalse(state.receive(reply(seq: 3, reset: false)))
        XCTAssertEqual(state.parameters()["since"]?.intValue, 3)
        XCTAssertTrue(state.receive(reply(seq: 1, reset: true, boot: "b3")),
                      "a later restart is a new catch-up")
    }

    func testAReplyWithoutASequenceLeavesThePosition() {
        var state = FeedState(boot: "b1")
        _ = state.receive(reply(seq: nil, reset: false))
        XCTAssertEqual(state.parameters()["since"]?.intValue, 0)
        _ = state.receive(reply(seq: nil, reset: false))
        XCTAssertEqual(state.parameters()["since"]?.intValue, 0)
    }

    func testTheCallCarriesTheBootTheHostNamed() {
        var state = FeedState(boot: "")
        _ = state.receive(reply(seq: 2, reset: false, boot: "host-1"))
        XCTAssertEqual(state.parameters()["boot"]?.stringValue, "host-1")
        XCTAssertEqual(state.parameters()["since"]?.intValue, 2)
    }
}

import XCTest
@testable import DSBot

/// The settled card's parsing follows items.tsx's own branches; these hold the
/// helpers to the RN semantics — the handoff hiding inside the text, a pick's
/// letter from its option's index, the view answer as one short line. The
/// on-screen card is a device check.
final class SettledCardTests: XCTestCase {

    func testAClosedAskCarriesItsPromptAndState() {
        let card = SettledCard(item: .object([
            "kind": .string("closed"),
            "closed": .string("replied"),
            "question": .object(["question": .string("Pick a tone")]),
        ]))
        guard case .closed(let prompt, let answered)? = card else { return XCTFail("expected a closed card") }
        XCTAssertEqual(prompt, "Pick a tone")
        XCTAssertTrue(answered)
    }

    func testAHandoffWithNoOutcomeDrawsNoBadge() {
        let card = SettledCard(item: .object([
            "kind": .string("answer"),
            "handoff": .object(["reason": .string("sign-in")]),
        ]))
        guard case .handoff(let title, let badge)? = card else { return XCTFail("expected a handoff card") }
        XCTAssertEqual(title, NativeLanguage.text("Sign-in needed"))
        XCTAssertNil(badge)
    }

    func testTheHandoffCanRideInsideTheAnswerText() {
        // items.tsx:156-163: no questions, no views, and the text parses.
        let card = SettledCard(item: .object([
            "kind": .string("answer"),
            "text": .string(#"{"kind":"answer_to_pending_handoff","reason":"verification","outcome":"skipped"}"#),
        ]))
        guard case .handoff(let title, let badge)? = card else { return XCTFail("expected a handoff card") }
        XCTAssertEqual(title, NativeLanguage.text("Verification needed"))
        XCTAssertEqual(badge, NativeLanguage.text("Skipped"))
    }

    func testAHandoffRidingTheTextNeedsQuestionsAndViewsEmpty() {
        XCTAssertNil(SettledCard(item: .object([
            "kind": .string("answer"),
            "questions": .array([.object(["question": .string("Still open?")])]),
            "text": .string(#"{"kind":"answer_to_pending_handoff","reason":"sign-in"}"#),
        ])))
    }

    func testPicksTakeTheirLettersFromTheOptions() {
        let question: JSONValue = .object([
            "question": .string("Ship today?"),
            "options": .array([
                .string("Yes"),
                .object(["label": .string("No")]),
                .string("Later"),
            ]),
        ])
        let answer: JSONValue = .object([
            "selected": .array([.string("No"), .string("Later")]),
            "custom": .string(" tomorrow"),
        ])
        let picks = SettledCard.picks(question: question, answer: answer)
        XCTAssertEqual(picks.map(\.letter), ["B", "C", "D"], "the object option counts, custom lands past them")
        XCTAssertEqual(picks.map(\.label), ["No", "Later", "tomorrow"])
    }

    func testAnUnknownSelectionFallsBackToItsPosition() {
        let question: JSONValue = .object([
            "options": .array([.string("One"), .string("Two")]),
        ])
        let answer: JSONValue = .object(["selected": .array([.string("Three")])])
        let picks = SettledCard.picks(question: question, answer: answer)
        XCTAssertEqual(picks.map(\.letter), ["A"])
    }

    func testAViewAnswerResolvesTheLabelsTheUserSaw() {
        let view: JSONValue = .object([
            "children": .array([
                .object(["options": .array([
                    .object(["label": .string("Ship it"), "value": .string("ship")]),
                    .object(["label": .string("Hold"), "value": .string("hold")]),
                ])]),
                .object([
                    "id": .string("confirm"),
                    "confirmLabel": .string("Do it"),
                    "cancelLabel": .string("Stop"),
                    "fields": .array([.object(["id": .string("port"), "label": .string("Port")])]),
                ]),
            ]),
        ])
        let picked = SettledCard.viewAnswerText(view: view, answer: .object([
            "action": .string("confirm"),
            "values": .object(["selected": .array([.string("ship")])]),
        ]))
        XCTAssertEqual(picked, "Ship it", "the value resolves to the label")
        let confirmed = SettledCard.viewAnswerText(view: view, answer: .object([
            "action": .string("confirm"),
            "values": .object(["confirmed": .bool(true)]),
        ]))
        XCTAssertEqual(confirmed, "Do it")
        let filled = SettledCard.viewAnswerText(view: view, answer: .object([
            "action": .string("confirm"),
            "values": .object([
                "fields": .object(["port": .string("22")]),
                "inputs": .object(["confirm": .string("yes")]),
            ]),
        ]))
        XCTAssertEqual(filled, "Port: 22; confirm=yes")
    }

    func testAViewAnswerCapsAtTwoHundredCharacters() {
        let long = String(repeating: "x", count: 80)
        let view: JSONValue = .object(["options": .array([.object(["label": .string(long)])])])
        let text = SettledCard.viewAnswerText(view: view, answer: .object([
            "values": .object(["selected": .array([.string(long), .string(long), .string(long)])]),
        ]))
        XCTAssertEqual(text.count, 201, "two hundred characters, then the ellipsis")
        XCTAssertTrue(text.hasSuffix("…"))
    }

    func testAViewWithItsDataIsTheLiveCardNotThisOne() {
        XCTAssertNil(SettledCard(item: .object([
            "kind": .string("view"),
            "title": .string("Build"),
            "view": .object(["type": .string("text")]),
        ])))
        guard case .viewTitle(let title)? = SettledCard(item: .object([
            "kind": .string("view"),
            "title": .string("Build"),
        ])) else { return XCTFail("expected a title card") }
        XCTAssertEqual(title, "Build")
    }

    func testAPlainAnswerIsNoCard() {
        XCTAssertNil(SettledCard(item: .object([
            "kind": .string("answer"),
            "text": .string("plain"),
        ])))
    }

    func testTheRowKeepsTheCardForTheCellToDraw() {
        let row = ChatRow(.object([
            "kind": .string("closed"),
            "closed": .string("dismissed"),
            "title": .string("Pick"),
        ]))
        guard case .closed(let prompt, let answered)? = row.settled else {
            return XCTFail("expected the row to carry the card")
        }
        XCTAssertEqual(prompt, "Pick")
        XCTAssertFalse(answered)
    }
}

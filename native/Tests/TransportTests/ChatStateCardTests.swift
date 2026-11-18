import XCTest
@testable import DSBot

final class ChatStateCardTests: XCTestCase {
    func testBlockedBotShowsProviderRepairForMissingCredential() {
        let bot = JSONValue.object([
            "id": .string("bot-1"), "name": .string("Aster"),
            "blocked": .object(["code": .string("MISSING_CREDENTIAL")]),
        ])
        let card = BotBlockedPresentation(bot: bot, models: [])
        XCTAssertEqual(card.message, NativeLanguage.text("{name}'s model has no API key yet.", ["name": "Aster"]))
        XCTAssertEqual(card.actions, [.providers, .model])
    }

    func testBlockedBotShowsTopUpOnlyForRelevantQuota() {
        let bot = JSONValue.object([
            "id": .string("bot-1"), "name": .string("Aster"),
            "blocked": .object([
                "code": .string("QUOTA"), "provider": .string("deepseek-official"),
                "status": .number(402),
            ]),
        ])
        let card = BotBlockedPresentation(bot: bot, models: [])
        XCTAssertEqual(card.actions, [.topUp, .model])
        XCTAssertTrue(card.message.contains("402"))
    }

    func testComputerUseFiltersRequestsAndShowsActiveControlForSelectedBot() {
        let bot = JSONValue.object(["id": .string("bot-1"), "name": .string("Aster")])
        let live = JSONValue.object([
            "asks": .object([
                "ask-1": .object(["id": .string("ask-1"), "botId": .string("bot-1"), "appName": .string("Safari")]),
                "ask-2": .object(["id": .string("ask-2"), "botId": .string("bot-2"), "appName": .string("Terminal")]),
            ]),
            "bots": .object(["bot-1": .object(["state": .string("running"), "app": .string("Safari")])]),
        ])
        let card = ComputerUsePresentation(bot: bot, live: live)
        XCTAssertEqual(card.asks, [.init(id: "ask-1", appName: "Safari")])
        XCTAssertTrue(card.isActive)
        XCTAssertEqual(card.activeApp, "Safari")
        XCTAssertEqual(card.botID, "bot-1")
    }

    func testComputerUseAnswerPayloadKeepsAskIDAndExactAnswer() {
        for answer in ["deny", "once", "always"] {
            XCTAssertEqual(ComputerUsePresentation.answerPayload(id: "ask-1", answer: answer),
                           .object(["id": .string("ask-1"), "answer": .string(answer)]))
        }
    }

    func testRoomGoalStatusAndStageProjection() {
        let stages: JSONValue = .array([
            .object(["title": .string("Plan"), "status": .string("passed")]),
            .object(["title": .string("Build"), "status": .string("active"),
                     "tasks": .array([.object(["status": .string("done")])])]),
        ])
        func goal(_ status: String, idle: Bool = false) -> RoomGoalPresentation {
            RoomGoalPresentation(goal: .object([
                "title": .string("Ship"), "status": .string(status), "idle": .bool(idle),
                "current": .number(1), "stages": stages,
            ]))
        }
        XCTAssertEqual(goal("drafting").number, nil)
        XCTAssertEqual(goal("active").number, "2/2")
        XCTAssertEqual(goal("active").label, NativeLanguage.text("Checking · {title}", ["title": "Build"]))
        XCTAssertEqual(goal("paused").label, NativeLanguage.text("Paused · {title}", ["title": "Build"]))
        XCTAssertEqual(goal("active", idle: true).label,
                       NativeLanguage.text("Waiting for you · {title}", ["title": "Build"]))
        XCTAssertEqual(goal("stopped").number, "1/2")
        XCTAssertEqual(goal("complete").label, NativeLanguage.text("Goal reached"))
        XCTAssertEqual(goal("active").stages[0], .init(title: "Plan", status: "passed"))
    }

    func testRoomGoalWithoutStagesShowsFinalCheck() {
        let card = RoomGoalPresentation(goal: .object(["title": .string("Ship"), "status": .string("active")]))
        XCTAssertEqual(card.title, "Ship")
        XCTAssertEqual(card.number, "0/0")
        XCTAssertEqual(card.label, NativeLanguage.text("Final check"))
    }

    func testWorkStatusUsesSelectedBotAndRoomWorker() {
        let bot = ChatTarget(kind: .bot, id: "bot-1", name: "Aster")
        let room = ChatTarget(kind: .room, id: "room-1", name: "Team")
        let state: JSONValue = .object([
            "bots": .array([.object(["id": .string("bot-1"), "name": .string("Aster")])]),
            "work": .object([
                "bots": .object(["bot-1": .object(["tool": .string("web_search")])]),
                "rooms": .object(["room-1": .array([.object(["botId": .string("bot-1"), "said": .string("Reading")])])]),
            ]),
        ])
        XCTAssertEqual(WorkStatusPresentation(target: bot, state: state)?.text,
                       NativeLanguage.text("Searching online") + "…")
        XCTAssertEqual(WorkStatusPresentation(target: room, state: state)?.text, "Aster · Reading…")
    }
}

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
}

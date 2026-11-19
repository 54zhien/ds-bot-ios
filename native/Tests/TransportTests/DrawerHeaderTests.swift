import XCTest
@testable import DSBot

/// The drawer's head is a `tableHeaderView`. It is built once and `reloadData` never
/// touches it, so these hold the two ways it went wrong: its colours stayed on the
/// palette it was built with, and its role chip was squeezed below its own line.
@MainActor
final class DrawerHeaderTests: XCTestCase {
    private func state() -> JSONValue {
        JSONValue.object([
            "mainBotIds": .array([.string("bot-1")]),
            "bots": .array([.object([
                "id": .string("bot-1"),
                "name": .string("Warden"),
                "role": .string("管理员"),
                "color": .string("violet"),
                "avatar": .object(["shape": .string("moon")]),
                "lastAt": .number(1_700_000_000_000),
            ])]),
        ])
    }

    /// A drawer in a window, so it has a real trait collection to read the palette from.
    private func presenter(style: UIUserInterfaceStyle) -> (TeamListViewController, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = style
        let controller = TeamListViewController(state: state())
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private func find(_ identifier: String, in root: UIView?) -> UIView? {
        guard let root else { return nil }
        if root.accessibilityIdentifier == identifier { return root }
        for child in root.subviews {
            if let found = find(identifier, in: child) { return found }
        }
        return nil
    }

    private func table(in controller: TeamListViewController) -> UITableView? {
        var found: UITableView?
        func walk(_ view: UIView) {
            if let table = view as? UITableView { found = table; return }
            view.subviews.forEach(walk)
        }
        walk(controller.view)
        return found
    }

    // MARK: - The squeezed chip

    /// The height is derived from the content now, so it has to cover every part of it.
    /// These numbers are written out rather than taken from the class: a test that reads
    /// the same constants it checks cannot catch a wrong constant.
    func testTheTileIsTallEnoughForWhatItHolds() {
        let (controller, _) = presenter(style: .light)
        guard let tile = find("drawer.tile", in: controller.view) else {
            return XCTFail("no tile in the drawer header")
        }
        let needed: CGFloat = 10 + 52 + 6 + 16 + 3 + 18 + 8
        XCTAssertGreaterThanOrEqual(tile.bounds.height, needed,
                                    "the tile cannot be shorter than its content")
        XCTAssertEqual(tile.bounds.height, TeamListViewController.tileHeight, accuracy: 0.5)
    }

    func testTheRoleChipKeepsItsLineHeight() {
        let (controller, _) = presenter(style: .light)
        guard let chip = find("drawer.tile.chip", in: controller.view),
              let role = find("drawer.tile.role", in: controller.view) else {
            return XCTFail("no role chip in the drawer header")
        }
        XCTAssertEqual(chip.bounds.height, 18, accuracy: 0.5)
        // 11pt SF sets 13.09; the label is the chip minus its 2pt top and bottom.
        XCTAssertGreaterThanOrEqual(role.bounds.height, 13.0,
                                    "the glyphs are cut when the label is under its line")
    }

    func testTheNameIsNotSqueezed() {
        let (controller, _) = presenter(style: .light)
        guard let name = find("drawer.tile.name", in: controller.view) else {
            return XCTFail("no name in the drawer header")
        }
        XCTAssertGreaterThanOrEqual(name.bounds.height, 15.5)
    }

    // MARK: - The stale palette

    /// Light, then dark: the head has to end up on the dark palette, which it cannot do
    /// by repainting — the tiles are new views.
    func testTheHeaderFollowsTheAppearance() {
        let (controller, window) = presenter(style: .light)
        let lightName = find("drawer.tile.name", in: controller.view) as? UILabel
        XCTAssertEqual(lightName?.textColor, ThemeStore.palette(dark: false).ink)

        controller.view.overrideUserInterfaceStyle = .dark
        controller.refreshAppearance()
        controller.view.layoutIfNeeded()

        let dark = ThemeStore.palette(dark: true)
        let darkName = find("drawer.tile.name", in: controller.view) as? UILabel
        let darkRole = find("drawer.tile.role", in: controller.view) as? UILabel
        let darkChip = find("drawer.tile.chip", in: controller.view)
        XCTAssertEqual(darkName?.textColor, dark.ink, "the name kept the old palette")
        XCTAssertEqual(darkRole?.textColor, dark.ink2)
        XCTAssertEqual(darkChip?.backgroundColor, dark.active)
        // The chip is a tint over the drawer, so what the eye sees is the composite.
        let seen = composite(dark.active, over: dark.sidebar)
        XCTAssertEqual(seen.0, 0.21, accuracy: 0.03)
        XCTAssertEqual(seen.1, 0.21, accuracy: 0.03)
        XCTAssertEqual(seen.2, 0.21, accuracy: 0.03)
    }

    /// The theme notification is the other way in, and it has to rebuild rather than
    /// repaint: the tile instance is what tells the two apart.
    func testAThemeChangeRebuildsTheHeader() {
        let (controller, _) = presenter(style: .light)
        let before = find("drawer.tile", in: controller.view)
        NotificationCenter.default.post(name: ThemeStore.changed, object: nil)
        controller.view.layoutIfNeeded()
        let after = find("drawer.tile", in: controller.view)
        XCTAssertNotNil(after)
        XCTAssertFalse(before === after, "the head was repainted instead of rebuilt")
    }

    /// A rebuild can move the content, and the list must not jump under the reader.
    func testRebuildingKeepsTheScrollPosition() {
        let (controller, _) = presenter(style: .light)
        guard let list = table(in: controller) else { return XCTFail("no table") }
        list.setContentOffset(CGPoint(x: 0, y: 12), animated: false)
        let before = list.contentOffset
        controller.refreshAppearance()
        XCTAssertEqual(list.contentOffset, before)
    }

    private func composite(_ top: UIColor, over bottom: UIColor) -> (CGFloat, CGFloat, CGFloat) {
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        bottom.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return (tr * ta + br * (1 - ta), tg * ta + bg * (1 - ta), tb * ta + bb * (1 - ta))
    }
}

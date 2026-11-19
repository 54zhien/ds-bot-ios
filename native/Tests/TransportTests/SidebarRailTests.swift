import XCTest
@testable import DSBot

/// SidebarRailView.swift:29-77 ported: the rail's measurements, where Settings rides
/// when the display corner is wide enough, and the opacity curve it slides on. The
/// numbers are zen's; the test names say which line each one comes from.
@MainActor
final class SidebarRailTests: XCTestCase {
    private func layout(leading: CGFloat = 0, top: CGFloat = 59, bottom: CGFloat = 34,
                        corner: CGFloat = 55) -> SidebarRailLayout {
        SidebarRailLayout(windowInsets: NSDirectionalEdgeInsets(top: top, leading: leading,
                                                               bottom: bottom, trailing: leading),
                          cornerRadius: corner)
    }

    /// :46-49 with a 55pt display corner: the column leads by the 16pt minimum, starts
    /// below the corner (55 - 28) or the safe area plus 12, whichever is lower down,
    /// and clears the home indicator plus 16.
    func testTheColumnMeasuresItselfFromTheWindow() {
        let rail = layout()
        XCTAssertEqual(rail.leading, 16)
        XCTAssertEqual(rail.top, 71, "59 + 12 beats 55 - 28")
        XCTAssertEqual(rail.bottom, 50, "34 + 16")
        XCTAssertEqual(rail.width, 96, "64 + leading on both sides")

        // A wider side safe area expands both sides, and a tall corner pushes the top.
        let wide = layout(leading: 24, top: 20, bottom: 0, corner: 62)
        XCTAssertEqual(wide.leading, 24)
        XCTAssertEqual(wide.top, 34, "62 - 28 beats 20 + 12")
        XCTAssertEqual(wide.bottom, 16)
        XCTAssertEqual(wide.width, 112)
    }

    /// :54-61: a corner of 36 or more centres Settings on the display corner; below
    /// that the control keeps the column slot and no shift.
    func testSettingsRidesTheDisplayCornerWhenThereIsRoom() {
        let rail = layout()
        let placement = rail.settingsPlacement(windowCornerRadius: 55)
        XCTAssertEqual(placement.bottom, 27, "55 - 28")
        XCTAssertEqual(placement.leadingShift, 7, "(55 - 28) - (16 + 4)")
        XCTAssertEqual(rail.settingsPlacement(windowCornerRadius: 55, isRightToLeft: true).leadingShift, -7)

        let tight = rail.settingsPlacement(windowCornerRadius: 30)
        XCTAssertEqual(tight.bottom, rail.bottom, "too small a corner keeps the column slot")
        XCTAssertEqual(tight.leadingShift, 0)
    }

    /// :73-76: the rail never disappears while it slides; it fades between a quarter
    /// and full.
    func testTheRailFadesBetweenAQuarterAndFull() {
        XCTAssertEqual(SidebarProgressPresentation.opacity(forProgress: 0), 0.25, accuracy: 0.0001)
        XCTAssertEqual(SidebarProgressPresentation.opacity(forProgress: 0.5), 0.625, accuracy: 0.0001)
        XCTAssertEqual(SidebarProgressPresentation.opacity(forProgress: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(SidebarProgressPresentation.opacity(forProgress: .nan), 0.25, accuracy: 0.0001)
        XCTAssertEqual(SidebarProgressPresentation.opacity(forProgress: -3), 0.25, accuracy: 0.0001)
        XCTAssertEqual(SidebarProgressPresentation.opacity(forProgress: 7), 1, accuracy: 0.0001)
        XCTAssertEqual(SidebarProgressPresentation.edgeOpacity, 0.16)
    }

    /// :116-124: new / search / recent in the capsule, files in a circle, settings at
    /// the bottom. Five controls, each with the identifier zen gives it.
    func testTheRailCarriesTheFiveControlsZenDraws() {
        let rail = SidebarRailView(layout: layout(), size: CGSize(width: 96, height: 844))
        XCTAssertEqual(rail.controls.count, 5)
        XCTAssertEqual(rail.controls.map(\.accessibilityIdentifier),
                       ["new-conversation-new", "sidebar-search", "new-conversation-recent",
                        "sidebar-files", "sidebar-settings"])
        XCTAssertEqual(rail.controls.map(\.accessibilityLabel),
                       ["New conversation", "Search", "Recent conversations", "Files", "Settings"])
        XCTAssertEqual(rail.accessibilityIdentifier, "sidebar-rail")
    }

    /// :85/136/155: a control the surface does not offer stays visible, dims to 0.35
    /// and stops answering; a moving rail leaves every control disabled and undimmed.
    func testAnUnavailableControlDimsAndAMovingRailGoesInert() {
        let rail = SidebarRailView(layout: layout(), size: CGSize(width: 96, height: 844))
        rail.availableRoutes = ["files"]
        let search = rail.controls[1]
        XCTAssertFalse(search.isEnabled)
        XCTAssertEqual(search.alpha, 0.35, accuracy: 0.0001)
        let files = rail.controls[3]
        XCTAssertTrue(files.isEnabled)
        XCTAssertEqual(files.alpha, 1, accuracy: 0.0001)

        rail.availableRoutes = ["search", "files", "settings"]
        rail.isInteractive = false
        XCTAssertTrue(rail.controls.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(rail.controls.allSatisfy { $0.alpha == 1 }, "inertness is not dimming")

        rail.isInteractive = true
        XCTAssertTrue(rail.controls[1].isEnabled)
    }
}

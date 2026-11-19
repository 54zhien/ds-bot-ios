import XCTest
@testable import DSBot

/// The drawer's two fixed blocks. Neither has an upstream to copy — zen's rail has no
/// device row, and the mobile drawer opens with the product name (ShellB.tsx:63-72) —
/// so these hold the two things that can still be wrong: the words, and the hairline.
@MainActor
final class SidebarContentBlocksTests: XCTestCase {
    func testTheDeviceHeadSaysWhoAndWhetherItIsUp() {
        let head = SidebarDeviceHeaderView()
        head.configure(name: "Studio iMac", connected: true)
        XCTAssertEqual(head.deviceName, "Studio iMac")
        XCTAssertEqual(head.statusText, NativeLanguage.text("Connected"))
        XCTAssertEqual(head.statusColor, ThemeStore.palette(trait: head.traitCollection).green)
        XCTAssertEqual(head.accessibilityLabel, "Studio iMac, " + NativeLanguage.text("Connected"))

        head.configure(name: "Studio iMac", connected: false)
        XCTAssertEqual(head.statusText, NativeLanguage.text("Offline"))
        XCTAssertEqual(head.statusColor, ThemeStore.palette(trait: head.traitCollection).ink3)

        head.configure(name: nil, connected: false)
        XCTAssertNil(head.deviceName, "a phone that has not read its pairing says nothing")
    }

    func testTheSectionTitleIsGreyAndItsLineIsOnePixel() {
        let header = SidebarSectionHeaderView()
        header.configure(title: NativeLanguage.text("Main Bots"))
        XCTAssertEqual(header.title, NativeLanguage.text("Main Bots"))
        XCTAssertEqual(header.titleColor, ThemeStore.palette(trait: header.traitCollection).ink3)
        XCTAssertEqual(header.hairlineHeight, 1 / header.traitCollection.displayScale, accuracy: 0.0001,
                       "StyleSheet.hairlineWidth, not a 1pt rule")
    }
}

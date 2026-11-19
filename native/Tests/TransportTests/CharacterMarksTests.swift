import XCTest
@testable import DSBot

/// characters.js is data before it is a picture: these hold the twenty shapes to
/// the strings the desktop ships (by fingerprint, so a transcription slip fails
/// here instead of drawing wrong), and hold the ink rules to the values the JS
/// returned for the same inputs.
final class CharacterMarksTests: XCTestCase {
    func testTheShapeTableCameOverWhole() {
        XCTAssertEqual(CharacterMarks.shapes.count, 20)
        XCTAssertEqual(CharacterMarks.inks.count, 19)
        XCTAssertEqual(CharacterMarks.fallbackShape, "gumdrop")
        XCTAssertEqual(CharacterMarks.maskId, "%MASK%")
        XCTAssertEqual(CharacterMarks.defaultShapes, ["star", "moon", "gumdrop", "peanut", "bunny", "kitty", "acorn"])
    }

    /// The generator fingerprinted path + layers straight out of characters.js.
    func testEveryShapesPathAndLayersMatchTheDesktopFile() {
        for (id, shape) in CharacterMarks.shapes {
            let expected = CharacterMarks.shapeHashes[id]
            XCTAssertNotNil(expected, "\(id) has no fingerprint")
            let actual = CharacterMarks.hash((shape.path ?? "") + "|" + shape.layers)
            XCTAssertEqual(actual, expected, "\(id) does not match characters.js")
        }
        XCTAssertEqual(CharacterMarks.shapeHashes.count, 20)
    }

    func testEveryShapeIsAHundredUnitBoxWithTwoEyes() {
        for (id, shape) in CharacterMarks.shapes {
            XCTAssertEqual(shape.size, 100, "\(id) box")
            XCTAssertEqual(shape.eyes.count, 2, "\(id) eyes")
            XCTAssertFalse(shape.label.isEmpty, "\(id) label")
        }
    }

    func testAnUnknownShapeFallsBackToGumdrop() {
        XCTAssertEqual(CharacterMarks.shapeId("nonesuch"), "gumdrop")
        XCTAssertEqual(CharacterMarks.shapeOf("nonesuch").label, "Gumdrop")
        XCTAssertEqual(CharacterMarks.shapeOf("").label, "Gumdrop")
        XCTAssertFalse(CharacterMarks.hasShape(""))
    }

    func testAColourAsPaint() {
        XCTAssertEqual(CharacterMarks.inkFill(""), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkText(""), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkName(""), "gray")
        XCTAssertEqual(CharacterMarks.paintCss(""), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkFill("hàn"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkText("hàn"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkName("hàn"), "gray")
        XCTAssertEqual(CharacterMarks.paintCss("hàn"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkFill("😀"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkText("😀"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkName("😀"), "gray")
        XCTAssertEqual(CharacterMarks.paintCss("😀"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkFill("chartreuse"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkText("chartreuse"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkName("chartreuse"), "gray")
        XCTAssertEqual(CharacterMarks.paintCss("chartreuse"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkFill("black"), "var(--bt-ink-black)")
        XCTAssertEqual(CharacterMarks.inkText("black"), "var(--bt-ink-gray)")
        XCTAssertEqual(CharacterMarks.inkName("black"), "black")
        XCTAssertEqual(CharacterMarks.paintCss("black"), "var(--bt-ink-black)")
        XCTAssertEqual(CharacterMarks.inkFill("#ff0000"), "#ff0000")
        XCTAssertEqual(CharacterMarks.inkText("#ff0000"), "#ff0000")
        XCTAssertEqual(CharacterMarks.inkName("#ff0000"), "gray")
        XCTAssertEqual(CharacterMarks.paintCss("#ff0000"), "#ff0000")
        XCTAssertEqual(CharacterMarks.inkFill("aurora"), "var(--bt-ink-aurora)")
        XCTAssertEqual(CharacterMarks.inkText("aurora"), "var(--bt-ink-aurora)")
        XCTAssertEqual(CharacterMarks.inkName("aurora"), "aurora")
        XCTAssertEqual(CharacterMarks.paintCss("aurora"), "linear-gradient(135deg,#A4FFB0 0%,#00F0E4 42%,#2E9EF7 100%)")
        XCTAssertEqual(CharacterMarks.inkFill("kimi"), "var(--bt-ink-charcoal)")
        XCTAssertEqual(CharacterMarks.inkText("kimi"), "var(--bt-ink-charcoal)")
        XCTAssertEqual(CharacterMarks.inkName("kimi"), "charcoal")
        XCTAssertEqual(CharacterMarks.paintCss("kimi"), "var(--bt-ink-charcoal)")
    }

    func testRenamedInksResolveThroughTheLegacyMap() {
        XCTAssertEqual(CharacterMarks.inkName("kimi"), "charcoal")
        XCTAssertEqual(CharacterMarks.inkFill("qwen"), "var(--bt-ink-cobalt)")
    }

    func testHexIsPaintAsItStands() {
        XCTAssertTrue(CharacterMarks.isHex("#ff0000"))
        XCTAssertTrue(CharacterMarks.isHex("#AbCdEf"))
        XCTAssertFalse(CharacterMarks.isHex("#fff"))
        XCTAssertFalse(CharacterMarks.isHex("ff0000"))
        XCTAssertFalse(CharacterMarks.isHex(""))
        XCTAssertFalse(CharacterMarks.isHex("汉#123456"))
    }

    func testTheMarkupCarriesItsOwnMaskId() {
        let markup = CharacterMarks.characterMarkup("star", "blue", maskId: "pm7")
        XCTAssertTrue(markup.contains("mask=\"url(#pm7)\""), "the body is masked by its own id")
        XCTAssertTrue(markup.contains("<mask id=\"pm7\""), "the mask carries it")
        XCTAssertFalse(markup.contains(CharacterMarks.maskId), "no placeholder survives")
        XCTAssertTrue(markup.contains("<g class=\"bt-b\">"))
        XCTAssertTrue(markup.contains("fill-rule=\"evenodd\""))
    }

    func testANamedColourPaintsThroughTheCssVariable() {
        XCTAssertTrue(CharacterMarks.characterMarkup("star", "blue").contains("fill=\"var(--bt-ink-blue)\""))
        XCTAssertTrue(CharacterMarks.characterMarkup("star", "").contains("fill=\"var(--bt-ink-gray)\""), "an empty colour is gray")
        XCTAssertTrue(CharacterMarks.characterMarkup("star", "😀").contains("fill=\"var(--bt-ink-gray)\""), "an emoji colour is gray")
        XCTAssertTrue(CharacterMarks.characterMarkup("star", "#00ff00").contains("fill=\"#00ff00\""), "hex paints directly")
    }

    func testOnlyAGradientColourCarriesAStopList() {
        let aurora = CharacterMarks.characterMarkup("star", "aurora", maskId: "pm1")
        XCTAssertTrue(aurora.contains("<linearGradient id=\"pm1g\""))
        XCTAssertTrue(aurora.contains("stop-color=\"#A4FFB0\""))
        XCTAssertTrue(aurora.contains("fill=\"url(#pm1g)\""))
        XCTAssertFalse(CharacterMarks.characterMarkup("star", "blue").contains("linearGradient"))
    }

    func testTheEyesAreCutOutOfTheBodyNotDrawnInIt() {
        let markup = CharacterMarks.characterMarkup("whale", "black", maskId: "pm2")
        guard let maskStart = markup.range(of: "<mask" ), let bodyStart = markup.range(of: "<g class=\"bt-b\">") else {
            return XCTFail("no mask or body")
        }
        let mask = markup[maskStart.lowerBound..<bodyStart.lowerBound]
        XCTAssertTrue(mask.contains("class=\"bt-eye\""), "the eyes live in the mask")
        XCTAssertFalse(markup[bodyStart.lowerBound...].contains("class=\"bt-eye\""), "the body is cut, not drawn")
    }
}

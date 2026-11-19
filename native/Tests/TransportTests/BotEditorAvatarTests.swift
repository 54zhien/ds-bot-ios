import XCTest
@testable import DSBot

// The photo rows write immediately while the form's Save is deferred, so the
// avatar a Save sends must grow from what the photo rows already wrote —
// otherwise a shape change after an upload resurrects the pre-photo avatar.
final class BotEditorAvatarTests: XCTestCase {
    func testShapePatchBuildsOnAPendingUploadNotTheSnapshot() {
        let saved = JSONValue.object(["shape": .string("star"), "imageRef": .string("lib-7")])
        var avatar = BotEditorViewController.avatarBase(
            pending: ["shape": .string("star"), "image": .string("data:image/jpeg;base64,AA==")],
            saved: saved)
        avatar["shape"] = .string("moon")
        XCTAssertEqual(avatar["shape"]?.stringValue, "moon")
        XCTAssertEqual(avatar["image"]?.stringValue, "data:image/jpeg;base64,AA==")
        XCTAssertNil(avatar["imageRef"])
    }

    func testShapePatchWithoutAPhotoStartsFromTheSnapshot() {
        let saved = JSONValue.object(["shape": .string("star"), "imageRef": .string("lib-7")])
        var avatar = BotEditorViewController.avatarBase(pending: nil, saved: saved)
        avatar["shape"] = .string("moon")
        XCTAssertEqual(avatar["shape"]?.stringValue, "moon")
        XCTAssertEqual(avatar["imageRef"]?.stringValue, "lib-7")
    }

    func testUploadAfterADeferredShapePickKeepsBoth() {
        // Shape picked first (still only local), photo uploaded second: the
        // upload starts from the snapshot, the later Save merges its shape
        // on top of the pending photo — neither write loses the other's keys.
        let saved = JSONValue.object(["shape": .string("star")])
        var uploaded = BotEditorViewController.avatarBase(pending: nil, saved: saved)
        uploaded["image"] = .string("data:image/jpeg;base64,AA==")
        var patched = BotEditorViewController.avatarBase(pending: uploaded, saved: saved)
        patched["shape"] = .string("moon")
        XCTAssertEqual(patched["shape"]?.stringValue, "moon")
        XCTAssertEqual(patched["image"]?.stringValue, "data:image/jpeg;base64,AA==")
    }

    func testPendingRemoveHidesTheSnapshotImage() {
        // The bot already had a photo and the row removed it here: a later
        // Save must not bring the snapshot's image back through its patch.
        let saved = JSONValue.object(["shape": .string("star"), "image": .string("data:image/jpeg;base64,old")])
        var avatar = BotEditorViewController.avatarBase(pending: ["shape": .string("star")], saved: saved)
        avatar["shape"] = .string("moon")
        XCTAssertNil(avatar["image"])
        XCTAssertEqual(avatar["shape"]?.stringValue, "moon")
    }
}

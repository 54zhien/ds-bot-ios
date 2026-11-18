import XCTest
@testable import DSBot

/// A phone set to Chinese shows English wherever a key has no entry, so the keys the
/// sources pass to NativeLanguage are checked against the tables here instead of on a
/// device. The sources are read from the checkout the test was built in.
final class LanguageTests: XCTestCase {
    func testEveryKeyInTheSourcesHasAChineseEntry() throws {
        let files = try LanguageTests.sourceFiles()
        var used = Set<String>()
        var missing: [String] = []
        for url in files {
            let source = try String(contentsOf: url, encoding: .utf8)
            for key in LanguageTests.keys(in: source) {
                used.insert(key)
                if !NativeLanguage.hasEntry(key) { missing.append(key) }
            }
        }
        XCTAssertFalse(used.isEmpty, "the scan found no keys, so it is reading the wrong folder")
        XCTAssertEqual(missing.sorted(), [], "every key needs a Chinese entry in NativeLanguage")
    }

    /// The other direction only reports: an entry nothing uses is clutter, not a failure.
    func testEntriesNothingUsesAreListed() throws {
        let files = try LanguageTests.sourceFiles()
        var used = Set<String>()
        for url in files {
            let source = try String(contentsOf: url, encoding: .utf8)
            used.formUnion(LanguageTests.keys(in: source))
        }
        let unused = NativeLanguage.nativeKeys.subtracting(used).sorted()
        if !unused.isEmpty { print("language entries with no call site: \(unused)") }
    }

    // MARK: - Sources

    private static func sourceFiles() throws -> [URL] {
        // This file lives in native/Tests/TransportTests, so three levels up is native/.
        let native = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let folder = native.appendingPathComponent("Sources/DSBot")
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw XCTSkip("the sources are not beside this test, so there is nothing to scan")
        }
        return try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every key handed to tr(...) or NativeLanguage.text(...). An interpolated key cannot
    /// be a dictionary key, so those are skipped.
    private static func keys(in source: String) -> [String] {
        let pattern = #"(?:NativeLanguage\.text|tr)\(\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }.filter { !$0.contains("\\(") }
    }
}

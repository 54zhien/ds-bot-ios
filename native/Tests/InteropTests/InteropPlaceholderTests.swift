import XCTest

/// The interop target compiles the transport sources into itself, so there is no
/// module to import. The real cases arrive with InteropConfig.generated.swift.
final class InteropPlaceholderTests: XCTestCase {
    func testTheTransportSourcesCompileIntoThisTarget() {
        XCTAssertEqual(ProtocolLimits.version, 1)
        XCTAssertEqual(ProtocolLimits.linkPath, "/v1/link")
    }
}

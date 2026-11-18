import Foundation
import XCTest
@testable import DSBot

final class SecureMessageCodecTests: XCTestCase {
    func testASmallMessageIsOneUntouchedFrame() throws {
        var codec = SecureMessageCodec()
        let message = Data(repeating: 0x41, count: 1_024)
        let frames = try codec.encode(message)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], message, "a short message carries no header at all")

        var inbox = SecureMessageCodec()
        XCTAssertEqual(try inbox.decode(frames[0]), message)
    }

    func testOneHundredThirtyKiBArrivesInThreeNumberedFragments() throws {
        var codec = SecureMessageCodec()
        let chunk = ProtocolLimits.secureFragmentChunkBytes
        let message = Data((0..<(130 * 1_024)).map { UInt8($0 & 0xff) })
        let frames = try codec.encode(message)
        XCTAssertEqual(frames.count, 3, "130 KiB needs ( (130 * 1024 + chunk - 1) / chunk ) chunks")

        for (index, frame) in frames.enumerated() {
            let bytes = [UInt8](frame)
            XCTAssertEqual([UInt8](frame.prefix(4)), [0x44, 0x53, 0x42, 0x46], "DSBF")
            XCTAssertEqual(bytes[4], 1, "fragment version")
            XCTAssertEqual(Int(bytes[9]) << 8 | Int(bytes[10]), index, "fragment index")
            XCTAssertEqual(Int(bytes[11]) << 8 | Int(bytes[12]), 3, "fragment total")
            let totalBytes = (Int(bytes[13]) << 24) | (Int(bytes[14]) << 16) | (Int(bytes[15]) << 8) | Int(bytes[16])
            XCTAssertEqual(totalBytes, message.count)
        }

        var inbox = SecureMessageCodec()
        var rebuilt: Data?
        for frame in frames {
            if let message = try inbox.decode(frame) { rebuilt = message }
        }
        XCTAssertEqual(rebuilt, message, "the pieces have to reassemble byte for byte")
    }

    func testAFragmentOutOfOrderIsRejected() throws {
        var codec = SecureMessageCodec()
        let frames = try codec.encode(Data(repeating: 0x42, count: 130 * 1_024))
        var inbox = SecureMessageCodec()
        XCTAssertThrowsError(try inbox.decode(frames[1]))
    }

    func testADuplicateFragmentIsRejected() throws {
        var codec = SecureMessageCodec()
        let frames = try codec.encode(Data(repeating: 0x43, count: 130 * 1_024))
        var inbox = SecureMessageCodec()
        _ = try inbox.decode(frames[0])
        XCTAssertThrowsError(try inbox.decode(frames[0]), "the same index twice cannot be a sequence")
    }

    func testTwoMessagesInterleavedStayApart() throws {
        var codec = SecureMessageCodec()
        let first = Data(repeating: 0x11, count: 130 * 1_024)
        let second = Data(repeating: 0x22, count: 100 * 1_024)
        let a = try codec.encode(first)
        let b = try codec.encode(second)
        XCTAssertEqual(a.count, 3)
        XCTAssertEqual(b.count, 3)

        var inbox = SecureMessageCodec()
        XCTAssertNil(try inbox.decode(a[0]))
        XCTAssertNil(try inbox.decode(b[0]))
        XCTAssertNil(try inbox.decode(a[1]))
        XCTAssertNil(try inbox.decode(b[1]))
        XCTAssertEqual(try inbox.decode(a[2]), first)
        XCTAssertEqual(try inbox.decode(b[2]), second)
    }

    func testAMessageLargerThanTheReassemblyLimitIsRefused() {
        var codec = SecureMessageCodec()
        let tooLarge = Data(repeating: 0x55, count: ProtocolLimits.maxSecureMessageBytes + 1)
        XCTAssertThrowsError(try codec.encode(tooLarge))
    }
}

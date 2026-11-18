import Foundation

/// Splits plaintext before Noise encryption and joins it after decryption, the way
/// link/src/frames.ts does: a 17-byte header, 48 KiB chunks, at most 4 MiB a message.
/// One Noise message holds at most 65 535 bytes, so a large state reply can only
/// arrive in pieces; a phone that skips this never sees one.
public struct SecureMessageCodec: Sendable {
    public static let headerBytes = 17
    public static let magic = Data([0x44, 0x53, 0x42, 0x46]) // DSBF
    public static let fragmentVersion: UInt8 = 1
    public static let maxInFlight = 8

    private struct Assembly {
        var total: Int
        var totalBytes: Int
        var receivedBytes: Int
        var chunks: [Data]
    }

    private var nextMessageId: UInt32 = 1
    private var assemblies: [UInt32: Assembly] = [:]

    public init() {}

    public mutating func reset() {
        nextMessageId = 1
        assemblies.removeAll()
    }

    /// One message in, one or more frames out; each frame is encrypted separately.
    public mutating func encode(_ message: Data) throws -> [Data] {
        guard message.count <= ProtocolLimits.maxSecureMessageBytes else {
            throw TransportError(.frameTooLarge, "The message is larger than the reassembly limit.")
        }
        let chunkBytes = ProtocolLimits.secureFragmentChunkBytes
        if message.count <= chunkBytes { return [message] }

        let messageId = nextMessageId
        nextMessageId = messageId == UInt32.max ? 1 : messageId + 1
        let total = (message.count + chunkBytes - 1) / chunkBytes
        let bytes = [UInt8](message)
        var frames: [Data] = []
        frames.reserveCapacity(total)
        for index in 0..<total {
            let start = index * chunkBytes
            let end = min(bytes.count, start + chunkBytes)
            var frame = Data(capacity: SecureMessageCodec.headerBytes + (end - start))
            frame.append(SecureMessageCodec.magic)
            frame.append(SecureMessageCodec.fragmentVersion)
            frame.append(SecureMessageCodec.bigEndian32(messageId))
            frame.append(SecureMessageCodec.bigEndian16(UInt16(index)))
            frame.append(SecureMessageCodec.bigEndian16(UInt16(total)))
            frame.append(SecureMessageCodec.bigEndian32(UInt32(bytes.count)))
            frame.append(contentsOf: bytes[start..<end])
            frames.append(frame)
        }
        return frames
    }

    /// A frame back into plaintext, or nil while a message is still arriving.
    /// A frame without the magic is a whole message and comes back untouched.
    public mutating func decode(_ frame: Data) throws -> Data? {
        guard SecureMessageCodec.isFragment(frame) else { return frame }
        let bytes = [UInt8](frame)
        guard bytes.count >= SecureMessageCodec.headerBytes, bytes[4] == SecureMessageCodec.fragmentVersion else {
            throw TransportError(.invalidFrame, "A secure fragment header is invalid.")
        }
        let messageId = SecureMessageCodec.read32(bytes, 5)
        let index = Int(SecureMessageCodec.read16(bytes, 9))
        let total = Int(SecureMessageCodec.read16(bytes, 11))
        let totalBytes = Int(SecureMessageCodec.read32(bytes, 13))
        let chunkBytes = ProtocolLimits.secureFragmentChunkBytes
        let expectedTotal = (totalBytes + chunkBytes - 1) / chunkBytes
        guard messageId != 0,
              total >= 2,
              index < total,
              totalBytes > chunkBytes,
              totalBytes <= ProtocolLimits.maxSecureMessageBytes,
              total == expectedTotal
        else {
            throw TransportError(.invalidFrame, "Secure fragment metadata is invalid.")
        }

        let expectedChunk = min(chunkBytes, totalBytes - index * chunkBytes)
        let chunk = Data(bytes[SecureMessageCodec.headerBytes..<bytes.count])
        guard chunk.count == expectedChunk else {
            throw TransportError(.invalidFrame, "Secure fragment length is invalid.")
        }

        if var assembly = assemblies[messageId] {
            guard assembly.total == total, assembly.totalBytes == totalBytes,
                  index == assembly.chunks.count
            else {
                assemblies.removeValue(forKey: messageId)
                throw TransportError(.invalidFrame, "Secure fragment sequence is invalid.")
            }
            assembly.chunks.append(chunk)
            assembly.receivedBytes += chunk.count
            if assembly.chunks.count < total {
                assemblies[messageId] = assembly
                return nil
            }
            assemblies.removeValue(forKey: messageId)
            guard assembly.receivedBytes == totalBytes else {
                throw TransportError(.invalidFrame, "Secure message length is invalid.")
            }
            var message = Data(capacity: totalBytes)
            for part in assembly.chunks { message.append(part) }
            return message
        }

        guard index == 0, assemblies.count < SecureMessageCodec.maxInFlight else {
            throw TransportError(.invalidFrame, "Secure fragment sequence is invalid.")
        }
        let assembly = Assembly(total: total, totalBytes: totalBytes, receivedBytes: chunk.count, chunks: [chunk])
        if assembly.chunks.count < total {
            assemblies[messageId] = assembly
            return nil
        }
        return chunk
    }

    private static func isFragment(_ frame: Data) -> Bool {
        guard frame.count >= magic.count else { return false }
        return [UInt8](frame.prefix(magic.count)) == [UInt8](magic)
    }

    private static func bigEndian16(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
    }

    private static func bigEndian32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ])
    }

    private static func read16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

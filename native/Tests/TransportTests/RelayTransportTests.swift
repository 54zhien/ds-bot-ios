import Foundation
import XCTest
@testable import DSBot

final class RelayTransportTests: XCTestCase {
    func testHandshakeSendsHelloThenConnectRequest() async throws {
        let socket = FakeRelaySocket()
        let transport = RelayTransport(options: options, socket: socket)

        let started = Task { try await transport.start() }
        try await waitForSent(socket, count: 1)

        let hello = try await socket.sentFrames()[0]
        XCTAssertEqual(hello.type, .hello)
        XCTAssertEqual(hello.payload["role"]?.stringValue, "client")
        XCTAssertEqual(hello.payload["deviceId"]?.stringValue, "d-phone")
        XCTAssertEqual(hello.payload["targetDeviceId"], nil, "hello carries no target")

        await socket.push(helloAck())
        try await waitForSent(socket, count: 2)
        let request = try await socket.sentFrames()[1]
        XCTAssertEqual(request.type, .connectRequest)
        XCTAssertEqual(request.payload["hostDeviceId"]?.stringValue, "d-host")

        await socket.push(accepted(connectionId: "conn-1"))
        try await started.value
        let connectionId = await transport.currentConnectionId
        XCTAssertEqual(connectionId, "conn-1")
    }

    func testRelayCounterStartsAtZeroAndAdvances() async throws {
        let socket = FakeRelaySocket()
        let transport = RelayTransport(options: options, socket: socket)
        let started = Task { try await transport.start() }
        try await waitForSent(socket, count: 1)
        await socket.push(helloAck())
        try await waitForSent(socket, count: 2)
        await socket.push(accepted(connectionId: "conn-1"))
        try await started.value

        try await transport.send(Data([0x01, 0x02, 0x03]))
        try await transport.send(Data([0x04]))

        let frames = try await socket.sentFrames()
        let relayFrames = frames.filter { $0.type == .relay }
        XCTAssertEqual(relayFrames.count, 2)
        XCTAssertEqual(relayFrames[0].payload["counter"]?.intValue, 0)
        XCTAssertEqual(relayFrames[1].payload["counter"]?.intValue, 1)
        XCTAssertEqual(relayFrames[0].payload["connectionId"]?.stringValue, "conn-1")
        XCTAssertEqual(relayFrames[0].payload["targetDeviceId"]?.stringValue, "d-host")

        let ciphertext = try Base64URL.decode(relayFrames[0].payload["ciphertext"]?.stringValue ?? "")
        XCTAssertEqual([UInt8](ciphertext), [0x01, 0x02, 0x03])
    }

    func testIncomingRelayFrameReachesTheSecureHandler() async throws {
        let socket = FakeRelaySocket()
        let transport = RelayTransport(options: options, socket: socket)
        await transport.setSecureHandler { data in
            SecureSink.shared.append(data)
        }
        SecureSink.shared.reset()

        let started = Task { try await transport.start() }
        try await waitForSent(socket, count: 1)
        await socket.push(helloAck())
        try await waitForSent(socket, count: 2)
        await socket.push(accepted(connectionId: "conn-1"))
        try await started.value

        await socket.push(relayFrame(connectionId: "conn-1", ciphertext: Data([0xaa, 0xbb])))
        try await waitUntil { SecureSink.shared.values.count == 1 }
        XCTAssertEqual([UInt8](SecureSink.shared.values[0]), [0xaa, 0xbb])
    }

    func testClosingDuringTheHandshakeRejectsTheStart() async throws {
        let socket = FakeRelaySocket()
        let transport = RelayTransport(options: options, socket: socket)
        let started = Task { try await transport.start() }
        try await waitForSent(socket, count: 1)
        await transport.close()
        do {
            try await started.value
            XCTFail("start() should have failed after close()")
        } catch {
            XCTAssertTrue(error is TransportError)
        }
    }

    // MARK: - Scripts

    private var options: RelayOptions {
        RelayOptions(deviceId: "d-phone", identityKey: "key", accessToken: "token", targetDeviceId: "d-host")
    }

    private func helloAck() -> String {
        let frame = ControlFrame(
            type: .helloAck,
            payload: HelloAckPayload(
                protocolVersion: ProtocolLimits.version,
                serverVersion: "test",
                connectionSessionId: "s-1",
                heartbeatIntervalMs: 15_000,
                maxControlFrameBytes: ProtocolLimits.maxControlFrameBytes,
                maxRelayFrameBytes: ProtocolLimits.maxRelayFrameBytes,
                capabilities: [ProtocolLimits.relayCapability]
            ),
            id: "ack-1",
            timestamp: 1
        )
        return (try? FrameCodec.encode(frame)) ?? ""
    }

    private func accepted(connectionId: String) -> String {
        let frame = ControlFrame(
            type: .connectAccepted,
            payload: ConnectAcceptedPayload(connectionId: connectionId),
            id: "acc-1",
            timestamp: 1
        )
        return (try? FrameCodec.encode(frame)) ?? ""
    }

    private func relayFrame(connectionId: String, ciphertext: Data) -> String {
        let frame = ControlFrame(
            type: .relay,
            payload: RelayPayload(
                connectionId: connectionId,
                targetDeviceId: "d-phone",
                counter: 0,
                ciphertext: Base64URL.encode(ciphertext)
            ),
            id: "relay-1",
            timestamp: 1
        )
        return (try? FrameCodec.encode(frame)) ?? ""
    }

    private func waitForSent(_ socket: FakeRelaySocket, count: Int) async throws {
        try await waitUntil { await socket.sentCount >= count }
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for the socket")
    }
}

private final class SecureSink: @unchecked Sendable {
    static let shared = SecureSink()
    private let lock = NSLock()
    private var storage: [Data] = []

    var values: [Data] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        storage = []
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(data)
    }
}

/// A scripted RelaySocket: the test pushes frames in, and reads what went out.
actor FakeRelaySocket: RelaySocket {
    private var incoming: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var sentTexts: [String] = []
    private var closed = false

    var sentCount: Int { sentTexts.count }

    func send(_ text: String) async throws {
        if closed { throw TransportError(.invalidFrame, "The fake socket is closed.") }
        sentTexts.append(text)
    }

    func receive() async throws -> String {
        if !incoming.isEmpty { return incoming.removeFirst() }
        if closed { throw TransportError(.invalidFrame, "The fake socket is closed.") }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
        }
    }

    func close() async {
        closed = true
        waiter?.resume(throwing: TransportError(.invalidFrame, "The fake socket is closed."))
        waiter = nil
    }

    func push(_ text: String) {
        if let pending = waiter {
            waiter = nil
            pending.resume(returning: text)
        } else {
            incoming.append(text)
        }
    }

    func sentFrames() throws -> [RawControlFrame] {
        try sentTexts.map { try FrameCodec.decode($0) }
    }
}

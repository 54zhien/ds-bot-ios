import Foundation
import XCTest
@testable import DSBot

final class SecureTransportTests: XCTestCase {
    func testHandshakeCarriesThePrologueAndCompletes() async throws {
        let socket = ScriptedSocket()
        let relay = RelayTransport(options: relayOptions, socket: socket)
        let secure = SecureTransport(relay: relay, identity: phoneIdentity, host: host, hello: phoneHello, handshakeTimeoutMs: 2_000)
        let connecting = Task { try await secure.connect() }

        try await driveToStepOne(socket)
        let frames = try await socket.sentFrames()
        let stepOne = frames[2]
        XCTAssertEqual(stepOne.type, .secureHandshake)
        XCTAssertEqual(stepOne.payload["step"]?.intValue, 1)

        let message1 = try Base64URL.decode(stepOne.payload["data"]?.stringValue ?? "")
        let responder = try responderSession()
        let helloSeen = try responder.readMessage(message1)
        XCTAssertEqual(helloSeen, phoneHello, "the phone hello rides inside message 1")

        let message2 = try responder.writeMessage(payload: hostHello)
        await socket.push(handshakeFrame(step: 2, data: message2))
        let ready = try await connecting.value
        XCTAssertEqual(ready.remoteHello, hostHello)
        XCTAssertEqual(ready.connectionId, "conn-1")
    }

    func testSendingEncryptsIntoARelayFrame() async throws {
        let socket = ScriptedSocket()
        let relay = RelayTransport(options: relayOptions, socket: socket)
        let secure = SecureTransport(relay: relay, identity: phoneIdentity, host: host, hello: phoneHello, handshakeTimeoutMs: 2_000)
        let connecting = Task { try await secure.connect() }
        let responder = try await driveToStepOne(socket, responder: nil)
        let frames = try await socket.sentFrames()
        let message1 = try Base64URL.decode(frames[2].payload["data"]?.stringValue ?? "")
        _ = try responder.readMessage(message1)
        await socket.push(handshakeFrame(step: 2, data: try responder.writeMessage(payload: hostHello)))
        _ = try await connecting.value

        try await secure.send(Data("ping".utf8))
        let sent = try await socket.sentFrames()
        let relayFrame = sent.last
        XCTAssertEqual(relayFrame?.type, .relay)
        XCTAssertEqual(relayFrame?.payload["counter"]?.intValue, 0)
        let ciphertext = try Base64URL.decode(relayFrame?.payload["ciphertext"]?.stringValue ?? "")
        // The phone sends with the initiator key, which is the responder's receiving side.
        var hostTransport = NoiseCipherState(key: try responder.split().receiving)
        XCTAssertEqual(try hostTransport.decrypt(ciphertext), Data("ping".utf8))
    }

    func testInboundCiphertextReachesTheHandler() async throws {
        let socket = ScriptedSocket()
        let relay = RelayTransport(options: relayOptions, socket: socket)
        let secure = SecureTransport(relay: relay, identity: phoneIdentity, host: host, hello: phoneHello, handshakeTimeoutMs: 2_000)
        let sink = DataSink()
        await secure.setMessageHandler { data in sink.append(data) }
        let connecting = Task { try await secure.connect() }
        let responder = try await driveToStepOne(socket, responder: nil)
        let frames = try await socket.sentFrames()
        let message1 = try Base64URL.decode(frames[2].payload["data"]?.stringValue ?? "")
        _ = try responder.readMessage(message1)
        await socket.push(handshakeFrame(step: 2, data: try responder.writeMessage(payload: hostHello)))
        _ = try await connecting.value

        var hostSending = NoiseCipherState(key: try responder.split().sending)
        let ciphertext = try hostSending.encrypt(Data("yo".utf8))
        await socket.push(relayFrame(ciphertext: ciphertext))
        try await waitUntil { sink.values.count == 1 }
        XCTAssertEqual(sink.values.first, Data("yo".utf8))
    }

    func testCloseFailsAHandshakeStillWaitingForStepTwo() async throws {
        let socket = ScriptedSocket()
        let relay = RelayTransport(options: relayOptions, socket: socket)
        let secure = SecureTransport(relay: relay, identity: phoneIdentity, host: host, hello: phoneHello, handshakeTimeoutMs: 5_000)
        let connecting = Task { try await secure.connect() }
        try await driveToStepOne(socket)
        await secure.close()
        do {
            _ = try await connecting.value
            XCTFail("connect() should have failed after close()")
        } catch {
            XCTAssertTrue(error is TransportError)
        }
    }

    // MARK: - Fixtures

    private var relayOptions: RelayOptions {
        RelayOptions(deviceId: "d-phone", identityKey: Base64URL.encode(phonePair.publicKey), accessToken: "t", targetDeviceId: "d-host")
    }

    private var phoneIdentity: SecureTransport.Identity {
        SecureTransport.Identity(
            deviceId: "d-phone",
            publicKey: Base64URL.encode(phonePair.publicKey),
            privateKey: Base64URL.encode(phonePair.privateKey)
        )
    }

    private var host: SecureTransport.Host {
        SecureTransport.Host(deviceId: "d-host", identityKey: Base64URL.encode(hostPair.publicKey))
    }

    private var phonePair: NoiseKeyPair {
        try! NoiseKeyPair(privateKey: Data((0..<32).map { UInt8($0) }))
    }

    private var hostPair: NoiseKeyPair {
        try! NoiseKeyPair(privateKey: Data((0..<32).map { UInt8(0xA0 + $0) }))
    }

    private var phoneHello: Data { Data("{\"name\":\"Phone\"}".utf8) }
    private var hostHello: Data { Data("{\"name\":\"Desk\"}".utf8) }

    private func responderSession() throws -> NoiseIKHandshake {
        let prologue = try createNoisePrologue(connectionId: "conn-1", hostDeviceId: "d-host", clientDeviceId: "d-phone")
        return try NoiseIKHandshake(role: .responder, staticKeyPair: hostPair, remoteStaticKey: phonePair.publicKey, prologue: prologue)
    }

    /// Drives the relay handshake until SecureTransport has sent its step-1 frame.
    @discardableResult
    private func driveToStepOne(_ socket: ScriptedSocket, responder: NoiseIKHandshake? = nil) async throws -> NoiseIKHandshake {
        try await waitForSent(socket, count: 1)
        await socket.push(helloAck())
        try await waitForSent(socket, count: 2)
        await socket.push(accepted())
        try await waitForSent(socket, count: 3)
        return try responder ?? responderSession()
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

    private func accepted() -> String {
        let frame = ControlFrame(type: .connectAccepted, payload: ConnectAcceptedPayload(connectionId: "conn-1"), id: "acc-1", timestamp: 1)
        return (try? FrameCodec.encode(frame)) ?? ""
    }

    private func handshakeFrame(step: Int, data: Data) -> String {
        let frame = ControlFrame(
            type: .secureHandshake,
            payload: SecureHandshakePayload(connectionId: "conn-1", targetDeviceId: "d-phone", step: step, data: Base64URL.encode(data)),
            id: "hs-\\(step)",
            timestamp: 1
        )
        return (try? FrameCodec.encode(frame)) ?? ""
    }

    private func relayFrame(ciphertext: Data) -> String {
        let frame = ControlFrame(
            type: .relay,
            payload: RelayPayload(connectionId: "conn-1", targetDeviceId: "d-phone", counter: 0, ciphertext: Base64URL.encode(ciphertext)),
            id: "relay-1",
            timestamp: 1
        )
        return (try? FrameCodec.encode(frame)) ?? ""
    }

    private func waitForSent(_ socket: ScriptedSocket, count: Int) async throws {
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

private final class DataSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Data] = []

    var values: [Data] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(data)
    }
}

actor ScriptedSocket: RelaySocket {
    private var incoming: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var sentTexts: [String] = []
    private var closed = false

    var sentCount: Int { sentTexts.count }

    func send(_ text: String) async throws {
        if closed { throw TransportError(.invalidFrame, "The scripted socket is closed.") }
        sentTexts.append(text)
    }

    func receive() async throws -> String {
        if !incoming.isEmpty { return incoming.removeFirst() }
        if closed { throw TransportError(.invalidFrame, "The scripted socket is closed.") }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
        }
    }

    func close() async {
        closed = true
        waiter?.resume(throwing: TransportError(.invalidFrame, "The scripted socket is closed."))
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

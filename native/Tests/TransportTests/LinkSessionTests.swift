import Foundation
import XCTest
@testable import DSBot

final class LinkSessionTests: XCTestCase {
    func testTheLadderRunsOneToSixtyThenStays() {
        var backoff = Backoff(options: Backoff.Options(), random: { 0.5 })
        let ladder = (0..<8).map { _ in backoff.nextDelayMs() }
        XCTAssertEqual(ladder, [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000, 60_000])
    }

    func testTheSpreadStaysInsideTwentyPercent() {
        var low = Backoff(options: Backoff.Options(), random: { 0 })
        XCTAssertEqual(low.nextDelayMs(), 800)
        var high = Backoff(options: Backoff.Options(), random: { 1 })
        XCTAssertEqual(high.nextDelayMs(), 1_200)
    }

    func testAStableLinkResetsTheLadder() {
        var backoff = Backoff(options: Backoff.Options(), random: { 0.5 })
        _ = backoff.nextDelayMs()
        _ = backoff.nextDelayMs()
        backoff.reset()
        XCTAssertEqual(backoff.nextDelayMs(), 1_000)
    }

    func testItRetriesUntilTheLinkComesUp() async throws {
        let factory = ChannelBox(failuresBeforeSuccess: 2)
        let session = LinkSession(
            options: LinkSession.Options(),
            makeChannel: factory.makeChannel,
            sleep: { _ in }
        )
        let log = StatusLog()
        await session.setStatusHandler { status in log.append(status) }
        await session.connect(factory.pairing)

        try await waitUntil { await session.currentStatus == .online }
        XCTAssertEqual(log.values.prefix(4), [.connecting, .offline, .connecting, .online])
        let attempts = await factory.attempts
        XCTAssertEqual(attempts, 3)
    }

    func testItGivesUpAfterTheThreshold() async throws {
        let factory = ChannelBox(failuresBeforeSuccess: .max)
        var options = LinkSession.Options()
        options.disconnectedAfterMs = 1
        let session = LinkSession(options: options, makeChannel: factory.makeChannel, sleep: { _ in })
        let log = StatusLog()
        await session.setStatusHandler { status in log.append(status) }
        await session.connect(factory.pairing)

        try await waitUntil { await session.currentStatus == .disconnected && log.values.contains(.disconnected) }
        XCTAssertEqual(log.values.last, .disconnected)
        let attempts = await factory.attempts
        XCTAssertEqual(attempts, 1, "the first wait already reaches the threshold")
    }

    func testDisconnectStopsTheLoop() async throws {
        let factory = ChannelBox(failuresBeforeSuccess: .max)
        let session = LinkSession(
            options: LinkSession.Options(),
            makeChannel: factory.makeChannel,
            sleep: { _ in }
        )
        await session.connect(factory.pairing)
        try await waitUntil { await factory.attempts >= 1 }
        await session.disconnect()
        let afterStop = await factory.attempts
        try await Task.sleep(nanoseconds: 60_000_000)
        let later = await factory.attempts
        XCTAssertEqual(later, afterStop, "no attempt may start after disconnect()")
        let status = await session.currentStatus
        XCTAssertEqual(status, .disconnected)
    }

    func testADropSendsTheLoopBackToConnecting() async throws {
        let factory = ChannelBox(failuresBeforeSuccess: 0)
        let session = LinkSession(options: LinkSession.Options(), makeChannel: factory.makeChannel, sleep: { _ in })
        let log = StatusLog()
        await session.setStatusHandler { status in log.append(status) }
        await session.connect(factory.pairing)
        try await waitUntil { await session.currentStatus == .online }
        factory.drop()
        try await waitUntil { log.values.contains(.offline) }
        XCTAssertEqual(log.values.suffix(3), [.offline, .connecting, .online])
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for the session")
    }
}

private final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LinkSession.Status] = []

    var values: [LinkSession.Status] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ status: LinkSession.Status) {
        lock.lock(); defer { lock.unlock() }
        storage.append(status)
    }
}

/// Fails the first N attempts, then hands out a channel the test can drop.
private final class ChannelBox: @unchecked Sendable {
    private let lock = NSLock()
    private let failuresBeforeSuccess: Int
    private var attemptsStorage = 0
    private var dropHandler: (@Sendable () -> Void)?

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    var attempts: Int {
        lock.lock(); defer { lock.unlock() }
        return attemptsStorage
    }

    func drop() {
        lock.lock()
        let handler = dropHandler
        lock.unlock()
        handler?()
    }

    var pairing: LinkSession.Pairing {
        let privateKey = Data(repeating: 0x2a, count: 32)
        let keys = try! NoiseKeyPair(privateKey: privateKey)
        return LinkSession.Pairing(
            serverURL: URL(string: "ws://127.0.0.1:8787/v1/link")!,
            hostDeviceId: "d-host",
            hostPublicKey: Base64URL.encode(Data(repeating: 0x11, count: 32)),
            identity: SecureTransport.Identity(
                deviceId: "d-phone",
                publicKey: Base64URL.encode(keys.publicKey),
                privateKey: Base64URL.encode(keys.privateKey)
            ),
            accessToken: String(repeating: "k", count: 32)
        )
    }

    func makeChannel(
        _ pairing: LinkSession.Pairing,
        _ dropped: @escaping @Sendable () -> Void
    ) async throws -> LinkSession.Channel {
        lock.lock()
        attemptsStorage += 1
        let attempt = attemptsStorage
        let failing = attempt <= failuresBeforeSuccess
        if !failing { dropHandler = dropped }
        lock.unlock()
        if failing {
            throw TransportError(.invalidFrame, "attempt failed")
        }
        return StubChannel()
    }
}

private struct StubChannel: LinkSession.Channel {
    func call(_ method: String, params: JSONValue) async throws -> JSONValue {
        .null
    }

    func send(_ data: Data) async throws {}

    func close() async {}
}

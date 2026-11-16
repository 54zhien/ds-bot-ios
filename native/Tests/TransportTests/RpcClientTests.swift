import Foundation
import XCTest
@testable import DSBot

final class RpcClientTests: XCTestCase {
    func testCallPairsTheReplyByRequestId() async throws {
        let channel = FakeChannel()
        let client = RpcClient(send: { try await channel.send($0) })

        let call = Task { try await client.call("state", params: .object(["since": .number(0)])) }
        try await waitForSent(channel, count: 1)

        let request = try await channel.lastRequest()
        XCTAssertEqual(request.method, "state")
        XCTAssertEqual(request.type, "rpc.request")

        await client.receive(RpcClientTests.reply(requestId: request.requestId, result: "{\"revision\":7}"))
        let result = try await call.value
        XCTAssertEqual(result["revision"]?.intValue, 7)
    }

    func testCallFailsOnItsDeadline() async throws {
        let channel = FakeChannel()
        let client = RpcClient(options: RpcClient.Options(timeoutMs: 60), send: { try await channel.send($0) })
        do {
            _ = try await client.call("state")
            XCTFail("the call should have timed out")
        } catch {
            XCTAssertTrue(error is TransportError)
        }
        try await waitForSent(channel, count: 1)
    }

    func testCloseFailsCallsStillInFlight() async throws {
        let channel = FakeChannel()
        let client = RpcClient(options: RpcClient.Options(timeoutMs: 5_000), send: { try await channel.send($0) })
        let call = Task { try await client.call("state") }
        try await waitForSent(channel, count: 1)
        await client.close()
        do {
            _ = try await call.value
            XCTFail("the call should have failed with the channel")
        } catch {
            XCTAssertTrue(error is TransportError)
        }
    }

    func testAnErrorReplyFailsTheCall() async throws {
        let channel = FakeChannel()
        let client = RpcClient(send: { try await channel.send($0) })
        let call = Task { try await client.call("state") }
        try await waitForSent(channel, count: 1)
        let request = try await channel.lastRequest()
        await client.receive(RpcClientTests.error(requestId: request.requestId, code: "HOST_OFFLINE", message: "The computer is offline."))
        do {
            _ = try await call.value
            XCTFail("an rpc.error reply must fail the call")
        } catch {
            XCTAssertTrue((error as? TransportError)?.message.contains("HOST_OFFLINE") == true)
        }
    }

    // MARK: - Helpers

    private func waitForSent(_ channel: FakeChannel, count: Int) async throws {
        for _ in 0..<200 {
            if await channel.sentCount >= count { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for the channel")
    }

    private static func reply(requestId: String, result: String) -> Data {
        let text = "{\"v\":1,\"id\":\"m-1\",\"type\":\"rpc.response\",\"timestamp\":1,\"payload\":{\"requestId\":\"\(requestId)\",\"result\":\(result)}}"
        return Data(text.utf8)
    }

    private static func error(requestId: String, code: String, message: String) -> Data {
        let text = "{\"v\":1,\"id\":\"m-2\",\"type\":\"rpc.error\",\"timestamp\":1,\"payload\":{\"requestId\":\"\(requestId)\",\"code\":\"\(code)\",\"message\":\"\(message)\"}}"
        return Data(text.utf8)
    }
}

private struct SentRequest {
    let requestId: String
    let method: String
    let type: String
}

private actor FakeChannel {
    private var sent: [Data] = []

    var sentCount: Int { sent.count }

    func send(_ data: Data) async throws {
        sent.append(data)
    }

    func lastRequest() throws -> SentRequest {
        guard let data = sent.last,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = value["id"] as? String,
              let type = value["type"] as? String,
              let payload = value["payload"] as? [String: Any],
              let method = payload["method"] as? String
        else {
            throw TransportError(.invalidFrame, "The test could not read the request it sent.")
        }
        return SentRequest(requestId: id, method: method, type: type)
    }
}

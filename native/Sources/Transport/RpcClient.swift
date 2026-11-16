import Foundation

/// The smallest RPC that can sit on the secure channel: one request, one reply,
/// a deadline, and every in-flight call failed when the channel goes away.
/// Messages are RemoteMessage envelopes (rpc.request / rpc.response / rpc.error).
public actor RpcClient {
    public struct Options: Sendable {
        public var timeoutMs: Int
        public init(timeoutMs: Int = 30_000) {
            self.timeoutMs = timeoutMs
        }
    }

    private let options: Options
    private let sendData: @Sendable (Data) async throws -> Void
    private var waiting: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var closed = false
    private var onEvent: (@Sendable (String, JSONValue) -> Void)?

    public init(options: Options = Options(), send: @escaping @Sendable (Data) async throws -> Void) {
        self.options = options
        self.sendData = send
    }

    public func setEventHandler(_ handler: @escaping @Sendable (String, JSONValue) -> Void) {
        onEvent = handler
    }

    /// Sends one request and waits for its reply or its deadline.
    public func call(_ method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        guard !closed else {
            throw TransportError(.invalidFrame, "The RPC channel is closed.")
        }
        let id = UUID().uuidString
        let text = RpcClient.requestText(id: id, method: method, params: params)
        // The continuation is stored before anything goes on the wire: a fast reply
        // must find it.
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            let timeoutMs = options.timeoutMs
            deadlines[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                await self?.expire(id)
            }
            Task { [weak self] in
                do {
                    try await self?.sendData(Data(text.utf8))
                } catch {
                    await self?.fail(id, error)
                }
            }
        }
    }

    /// Feeds one decrypted message in; replies resume the caller waiting for that id.
    public func receive(_ message: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: message),
              let fields = value as? [String: Any],
              let type = fields["type"] as? String,
              let payload = fields["payload"] as? [String: Any]
        else { return }
        if type == MessageType.event.rawValue {
            guard let event = payload["event"] as? String else { return }
            onEvent?(event, RpcClient.jsonValue(payload["data"]))
            return
        }
        guard let requestId = payload["requestId"] as? String else { return }
        switch type {
        case MessageType.rpcResponse.rawValue:
            let result = payload["result"]
            finish(requestId, with: RpcClient.jsonValue(result))
        case MessageType.rpcError.rawValue:
            let message = payload["message"] as? String ?? "The call failed."
            let code = payload["code"] as? String
            finish(requestId, with: nil, error: TransportError(.invalidFrame, code.map { "\($0): \(message)" } ?? message))
        default:
            break
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        let pending = waiting
        waiting.removeAll()
        for (id, continuation) in pending {
            deadlines.removeValue(forKey: id)?.cancel()
            continuation.resume(throwing: TransportError(.invalidFrame, "The RPC channel closed."))
        }
    }

    // MARK: - Internals

    private func expire(_ id: String) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: TransportError(.invalidFrame, "The call timed out."))
    }

    private func fail(_ id: String, _ error: Error) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: error)
    }

    private func finish(_ id: String, with result: JSONValue?, error: Error? = nil) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: result ?? .null)
        }
    }

    private static func requestText(id: String, method: String, params: JSONValue) -> String {
        var payload = OrderedObject()
        payload.add("method", JSONText.string(method))
        payload.add("params", JSONText.render(params))
        var message = OrderedObject()
        message.add("v", JSONText.int(ProtocolLimits.version))
        message.add("id", JSONText.string(id))
        message.add("type", JSONText.string(MessageType.rpcRequest.rawValue))
        message.add("timestamp", JSONText.int(Int(Date().timeIntervalSince1970 * 1000)))
        message.add("payload", payload.text)
        return message.text
    }

    private static func jsonValue(_ any: Any?) -> JSONValue {
        guard let any, !(any is NSNull) else { return .null }
        guard let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .null }
        return value
    }
}

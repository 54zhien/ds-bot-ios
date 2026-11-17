import Foundation
import JavaScriptCore

/// Runs the same restricted deep-view 0.1.0 formula parser as the RN card.
/// Formula input is parsed by deep-view; it is never passed to JavaScript eval.
final class DeepViewFormula {
    private let context: JSContext
    private let definitions: [String: JSONValue]

    init?(root: JSONValue) {
        guard let url = Bundle.main.url(forResource: "deep-view-formula", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(source)
        guard context.exception == nil,
              context.objectForKeyedSubscript("dsbotFormula")?.isUndefined == false else { return nil }
        self.context = context
        var definitions: [String: JSONValue] = [:]
        Self.collectLets(root, into: &definitions)
        self.definitions = definitions
    }

    static func isFormula(_ value: JSONValue?) -> Bool {
        value?["="]?.stringValue != nil
    }

    func resolve(_ value: JSONValue?, inputs: [String: JSONValue]) -> JSONValue? {
        guard let value else { return nil }
        guard let source = value["="]?.stringValue else { return value }
        context.exception = nil
        let result = context.objectForKeyedSubscript("dsbotFormula")?.call(withArguments: [
            source, Self.foundation(.object(inputs)), Self.foundation(.object(definitions)),
        ])
        guard context.exception == nil, let result,
              result.forProperty("error")?.isUndefined != false,
              let object = result.forProperty("value")?.toObject(),
              let data = try? JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func collectInputs(_ node: JSONValue, into inputs: inout [String: JSONValue]) {
        guard case .object = node else { return }
        if let id = node["id"]?.stringValue,
           let type = node["type"]?.stringValue,
           ["slider", "number", "choice", "toggle"].contains(type) {
            inputs[id] = node["value"] ?? .null
        }
        for key in ["children", "options"] {
            if case .array(let values)? = node[key] {
                for value in values { collectInputs(value, into: &inputs) }
            }
        }
    }

    private static func collectLets(_ node: JSONValue, into definitions: inout [String: JSONValue]) {
        guard case .object = node else { return }
        if case .object(let values)? = node["let"] {
            for (name, value) in values { definitions[name] = value }
        }
        for key in ["children", "options"] {
            if case .array(let values)? = node[key] {
                for value in values { collectLets(value, into: &definitions) }
            }
        }
    }

    private static func foundation(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .number(let number): return number
        case .string(let text): return text
        case .array(let values): return values.map(foundation)
        case .object(let values): return values.mapValues(foundation)
        }
    }
}

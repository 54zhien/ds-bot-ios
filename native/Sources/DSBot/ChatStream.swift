import Foundation

/// The reply currently arriving over the feed. Saved messages still come from chat pages.
struct ChatStream {
    private(set) var sessionID: String?
    private var attempts: [(id: String, text: String)] = []

    var text: String {
        attempts.map { $0.text }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    mutating func clear() {
        sessionID = nil
        attempts = []
    }

    @discardableResult
    mutating func receive(_ value: JSONValue, for currentSessionID: String?) -> Bool {
        guard let currentSessionID, value["sessionId"]?.stringValue == currentSessionID,
              let attemptID = value["attemptId"]?.stringValue else { return false }
        if sessionID != currentSessionID {
            clear()
            sessionID = currentSessionID
        }
        if value["phase"]?.stringValue == "start" {
            attempts.removeAll { $0.id == attemptID }
            attempts.append((id: attemptID, text: ""))
        } else if let chunk = value["text"]?.stringValue {
            if let index = attempts.firstIndex(where: { $0.id == attemptID }) {
                attempts[index].text += chunk
            } else {
                attempts.append((id: attemptID, text: chunk))
            }
        } else if value["phase"]?.stringValue == "end" {
            attempts.removeAll { $0.id == attemptID }
        }
        return true
    }
}

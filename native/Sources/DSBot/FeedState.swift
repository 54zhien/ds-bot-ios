import Foundation

/// The read position of the notices feed, kept away from any screen. The host
/// numbers its notices and keeps only the last ring of them (host/mobile.js
/// notices()): a client whose position names a boot that went away, or fell out
/// of the ring, is told so and reads the team again instead of trusting deltas.
///
/// A reset clears the position — the next call reads from the start — and asks
/// for exactly one catch-up read, however many resets stack up while one is due.
/// The next ordinary reply confirms the read and re-arms the next reset.
struct FeedState {
    /// The boot the host named last; the call sends it back so a restart is told apart.
    private(set) var boot: String
    /// The last sequence the host confirmed, or nil while reading from the start.
    private(set) var lastSeq: Int?
    private var catchUpPending = false

    init(boot: String = "") {
        self.boot = boot
    }

    /// The parameters a notices call carries: this boot and the position it left off.
    func parameters() -> JSONValue {
        .object([
            "boot": .string(boot),
            "since": .number(Double(lastSeq ?? 0)),
        ])
    }

    /// One notices reply. An ordinary one just advances the position; a reset
    /// clears it and answers whether the team should be read now — true the
    /// first time, false while a catch-up is already due.
    @discardableResult
    mutating func receive(_ reply: JSONValue) -> Bool {
        if let next = reply["boot"]?.stringValue { boot = next }
        guard reply["reset"] == .bool(true) else {
            if let seq = reply["seq"]?.intValue { lastSeq = seq }
            catchUpPending = false
            return false
        }
        lastSeq = nil
        if catchUpPending { return false }
        catchUpPending = true
        return true
    }
}

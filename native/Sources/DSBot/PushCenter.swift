import Foundation
import UIKit
import UserNotifications

/// The phone side of real push. The payload carries routing keys only
/// (roomId / botId / kind); the body never travels through Apple, because the
/// app pulls the message itself over the encrypted link once it is open.
@MainActor
final class PushCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushCenter()

    typealias Router = (ChatTarget.Kind, String) -> Void

    /// The chat screen installs this at viewDidLoad: a cold-start tap routes
    /// after launch, and the push center holds no UI of its own.
    var openChat: Router?

    private(set) var enabled: Bool
    private var token: String?
    private weak var session: LinkSession?
    private var hostAcceptsToken = false
    private var reporting = false

    private let intentKey = "dsbot.push"
    private let tokenKey = "dsbot.push.token"

    private override init() {
        enabled = UserDefaults.standard.string(forKey: "dsbot.push") == "on"
        token = UserDefaults.standard.string(forKey: "dsbot.push.token")
        super.init()
    }

    /// Seated from didFinishLaunching, before the run loop spins: a tap that
    /// cold-launched the app is delivered to the delegate right after launch,
    /// so a late delegate would drop it. Tokens rotate per launch, so an
    /// enabled phone re-registers here every time.
    func bootstrap() {
        UNUserNotificationCenter.current().delegate = self
        if enabled {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// The Settings toggle is the only ask, so permission is never requested
    /// on launch or out of context. A refusal leaves push off silently.
    func setEnabled(_ on: Bool) async -> Bool {
        if on {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            guard granted else {
                disable()
                return false
            }
            UserDefaults.standard.set("on", forKey: intentKey)
            enabled = true
            UIApplication.shared.registerForRemoteNotifications()
            reportToken(token)
            return true
        }
        disable()
        return false
    }

    private func disable() {
        UserDefaults.standard.set("off", forKey: intentKey)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        enabled = false
        token = nil
        // Off means off: the phone unregisters and tells the host to stop
        // sending to a token nobody will display.
        UIApplication.shared.unregisterForRemoteNotifications()
        reportToken(nil)
    }

    func deviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        guard hex != token else { return }
        token = hex
        UserDefaults.standard.set(hex, forKey: tokenKey)
        reportToken(hex)
    }

    func registrationFailed(_ error: Error) {
        // A simulator or a profile without push lands here: no token, no error
        // on screen, everything else keeps working.
    }

    /// The hello reply names what the host takes. "push-token" in
    /// hello.capabilities is the gate: an older computer never hears about a
    /// token, and the protocol version does not move.
    func hostOnline(hello: JSONValue, session: LinkSession) {
        hostAcceptsToken = hello["capabilities"]?.stringArrayValue?.contains("push-token") ?? false
        self.session = session
        reportToken(token)
    }

    /// A reconnect builds a new session; reporting waits for its hello again.
    func hostOffline() {
        session = nil
        hostAcceptsToken = false
    }

    private func reportToken(_ value: String?) {
        guard let session, hostAcceptsToken, !reporting else { return }
        reporting = true
        Task {
            defer { reporting = false }
            // A null token means "stop sending"; the bundle id is the APNs
            // topic, which the host cannot guess from a token.
            let payload: [String: JSONValue] = [
                "token": value.map(JSONValue.string) ?? .null,
                "bundleId": .string(Bundle.main.bundleIdentifier ?? ""),
            ]
            // The report is best-effort: a rejection here degrades to "no
            // push", which is never worth an error on screen.
            _ = try? await BotAPI.call("push-token", payload: .object(payload), on: session)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Foreground: no system banner. The link is live, so the message and its
    /// in-app notice banner are already on their way over the encrypted path.
    // The delegate requirements enter from a nonisolated context and their
    // parameters are not Sendable, so the entry points stay nonisolated and the
    // work hops onto the main actor with plain strings.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    /// The tap path, foreground, background and cold start alike.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Routing keys only; the chat screen resolves the display name from team
        // state, because the payload never carries one. Read them out of the
        // notification before crossing to the main actor: the dictionary is not
        // Sendable, the two strings are.
        let userInfo = response.notification.request.content.userInfo
        let room = userInfo["roomId"] as? String
        let bot = userInfo["botId"] as? String
        await MainActor.run {
            if let room, !room.isEmpty {
                openChat?(.room, room)
            } else if let bot, !bot.isEmpty {
                openChat?(.bot, bot)
            }
        }
    }
}

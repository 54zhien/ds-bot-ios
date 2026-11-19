import UIKit
import UserNotifications

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let chat = ChatViewController()
        let navigation = UINavigationController(rootViewController: chat)
        navigation.navigationBar.prefersLargeTitles = false

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = NativeSettingsViewController.style(
            for: UserDefaults.standard.string(forKey: "dsbot.theme") ?? "System"
        )
        window.rootViewController = navigation
        // The ink of the team's theme, not the system blue, is what anything
        // unstyled falls back to.
        window.tintColor = ThemeStore.palette(trait: window.traitCollection).ink
        window.makeKeyAndVisible()
        self.window = window
        // A pairing link that launched the app arrives with the connection,
        // not through openURLContexts; one tick lets the first frame land.
        DispatchQueue.main.async { [weak self] in
            self?.handlePairingURLs(connectionOptions.urlContexts.map(\.url))
        }
        // A theme picked on the computer moves the fallback too.
        NotificationCenter.default.addObserver(
            forName: ThemeStore.changed, object: nil, queue: .main
        ) { [weak window] _ in
            let view = window
            Task { @MainActor in
                view?.tintColor = ThemeStore.palette(trait: view?.traitCollection ?? .current).ink
            }
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // The host owns the badge count and recomputes it on the next push;
        // the phone only clears what it has already shown.
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    /// A pairing link tapped in Safari or a QR app while the app runs
    /// (App.tsx:108 in RN); a cold-start link came through connectionOptions.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handlePairingURLs(URLContexts.map(\.url))
    }

    private func handlePairingURLs(_ urls: [URL]) {
        // The scheme is registered in project.yml; the parse errors for
        // anything else inside the link are explained by the pairing sheet.
        for url in urls
        where url.scheme?.lowercased() == PairingLink.scheme && url.host?.lowercased() == PairingLink.pairHost {
            chatViewController()?.openPairingURL(url)
        }
    }

    private func chatViewController() -> ChatViewController? {
        guard let nav = window?.rootViewController as? UINavigationController else { return nil }
        return nav.viewControllers.compactMap { $0 as? ChatViewController }.first
    }
}

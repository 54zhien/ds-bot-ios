import UIKit

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
}

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
        window.makeKeyAndVisible()
        self.window = window
    }
}

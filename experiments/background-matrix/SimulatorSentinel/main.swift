import UIKit

final class SentinelApplication: UIApplication {
    override func sendEvent(_ event: UIEvent) {
        if event.allTouches?.contains(where: { $0.phase == .began }) == true ||
            (event as? UIPressesEvent)?.allPresses.contains(where: { $0.phase == .began }) == true {
            SentinelScene.counter += 1
            SentinelScene.label?.text = String(SentinelScene.counter)
        }
        super.sendEvent(event)
    }
}

final class SentinelDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SentinelScene.self
        return config
    }
}

final class SentinelScene: UIResponder, UIWindowSceneDelegate {
    static var counter = 0
    static weak var label: UILabel?
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        let label = UILabel()
        label.text = "0"
        label.accessibilityIdentifier = "matrix.sentinel.events"
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
        ])
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        Self.label = label
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, NSStringFromClass(SentinelApplication.self), NSStringFromClass(SentinelDelegate.self))

import UIKit

/// UIKit rather than SwiftUI: the IMA SDK hands ads to a `UIView` and needs a
/// `UIViewController` to present from, so this stays closer to how it is
/// actually integrated.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = AdPlayerViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

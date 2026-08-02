import SwiftUI
import UIKit

// Hosts both counter implementations side by side in a tab bar: one tab backed
// by TCA, one by a plain @Observable model. Both render through the same
// FineUIKit body (see CounterView.swift).
struct CounterTabs: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabs = UITabBarController()
        let settings = DemoSettings()

        let tca = UINavigationController(rootViewController: TCACounterViewController())
        tca.tabBarItem = UITabBarItem(
            title: "TCA",
            image: UIImage(systemName: "square.stack.3d.up"),
            tag: 0
        )

        let plain = UINavigationController(rootViewController: PlainCounterViewController())
        plain.tabBarItem = UITabBarItem(
            title: "Plain",
            image: UIImage(systemName: "circle"),
            tag: 1
        )

        let settingsController = SettingsViewController(
            settings: settings,
            onAppearanceChange: { [weak tabs] isDarkModeEnabled in
                tabs?.overrideUserInterfaceStyle = isDarkModeEnabled ? .dark : .light
            },
            onLanguageChange: { [weak tabs] language in
                tabs?.viewControllers?.last?.tabBarItem.title = language.settingsTitle
            }
        )
        let settingsNavigation = UINavigationController(rootViewController: settingsController)
        settingsNavigation.tabBarItem = UITabBarItem(
            title: settings.language.settingsTitle,
            image: UIImage(systemName: "gearshape"),
            tag: 2
        )

        tabs.viewControllers = [tca, plain, settingsNavigation]
        tabs.overrideUserInterfaceStyle = settings.isDarkModeEnabled ? .dark : .light
        return tabs
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
    }
}

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            CounterTabs()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    CounterTabs()
        .ignoresSafeArea()
}

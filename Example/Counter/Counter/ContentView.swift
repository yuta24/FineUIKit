import FineUIKit
import SwiftUI
import UIKit

// Hosts both counter implementations side by side in a tab bar: one tab backed
// by TCA, one by a plain @Observable model. Both render through the same
// FineUIKit body (see CounterView.swift).
struct CounterTabs: UIViewControllerRepresentable {
    // Owns the screen's delegate. A screen reports what happened; deciding what
    // that means for the rest of the app belongs out here, to something whose
    // lifetime SwiftUI already manages.
    @MainActor
    final class Coordinator: SettingsScreenDelegate {
        weak var tabs: UITabBarController?

        func settingsScreen(_ screen: SettingsScreen, didChangeDarkMode isEnabled: Bool) {
            tabs?.overrideUserInterfaceStyle = isEnabled ? .dark : .light
        }

        func settingsScreen(_ screen: SettingsScreen, didChangeLanguage language: DemoLanguage) {
            tabs?.viewControllers?.last?.tabBarItem.title = language.settingsTitle
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabs = UITabBarController()
        let settings = DemoSettings()
        context.coordinator.tabs = tabs

        let tca = UINavigationController(rootViewController: FineScreenController(TCACounterScreen()))
        tca.tabBarItem = UITabBarItem(
            title: "TCA",
            image: UIImage(systemName: "square.stack.3d.up"),
            tag: 0
        )

        let plain = UINavigationController(rootViewController: FineScreenController(PlainCounterScreen()))
        plain.tabBarItem = UITabBarItem(
            title: "Plain",
            image: UIImage(systemName: "circle"),
            tag: 1
        )

        let settingsScreen = SettingsScreen(settings: settings)
        settingsScreen.delegate = context.coordinator
        let settingsNavigation = UINavigationController(
            rootViewController: FineScreenController(settingsScreen)
        )
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

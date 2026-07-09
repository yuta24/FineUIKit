import SwiftUI
import UIKit

// Hosts both counter implementations side by side in a tab bar: one tab backed
// by TCA, one by a plain @Observable model. Both render through the same
// FineUIKit body (see CounterView.swift).
struct CounterTabs: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
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

        let tabs = UITabBarController()
        tabs.viewControllers = [tca, plain]
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

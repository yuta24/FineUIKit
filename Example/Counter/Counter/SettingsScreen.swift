import FineUIKit
import Foundation
import Observation
import UIKit

enum DemoLanguage: String, CaseIterable {
    case japanese
    case english

    var displayName: String {
        switch self {
        case .japanese:
            "日本語"
        case .english:
            "English"
        }
    }

    var settingsTitle: String {
        switch self {
        case .japanese:
            "設定"
        case .english:
            "Settings"
        }
    }

    var appearanceTitle: String {
        switch self {
        case .japanese:
            "外観"
        case .english:
            "Appearance"
        }
    }

    var darkModeTitle: String {
        switch self {
        case .japanese:
            "ダークモード"
        case .english:
            "Dark Mode"
        }
    }

    var languageTitle: String {
        switch self {
        case .japanese:
            "言語"
        case .english:
            "Language"
        }
    }
}

@Observable
final class DemoSettings {
    private enum Key {
        static let darkMode = "demo.settings.darkMode"
        static let language = "demo.settings.language"
    }

    private let defaults: UserDefaults

    var isDarkModeEnabled: Bool {
        didSet {
            defaults.set(isDarkModeEnabled, forKey: Key.darkMode)
        }
    }

    var language: DemoLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDarkModeEnabled = defaults.bool(forKey: Key.darkMode)
        language = defaults.string(forKey: Key.language)
            .flatMap(DemoLanguage.init(rawValue:)) ?? .japanese
    }
}

// What this screen has to say to the rest of the app. A delegate rather than a
// closure, and `weak` here rather than a capture list at every call site: a
// screen must not hold its controller, and declaring that once is more reliable
// than remembering it everywhere.
@MainActor
protocol SettingsScreenDelegate: AnyObject {
    func settingsScreen(_ screen: SettingsScreen, didChangeDarkMode isEnabled: Bool)
    func settingsScreen(_ screen: SettingsScreen, didChangeLanguage language: DemoLanguage)
}

final class SettingsScreen: FineNavigating {
    let settings: DemoSettings
    weak var delegate: (any SettingsScreenDelegate)?

    init(settings: DemoSettings) {
        self.settings = settings
    }

    func navigation() -> FineNavigation? {
        FineNavigation(title: settings.language.settingsTitle)
    }

    func body() -> any Renderable {
        let language = settings.language

        return FineScrollView {
            FineStack.vertical(spacing: 12) {
                FineLabel(text: language.appearanceTitle)
                    .font(.preferredFont(forTextStyle: .headline))
                    .textColor(.secondaryLabel)

                FineStack.horizontal(spacing: 12, alignment: .center) {
                    FineLabel(text: language.darkModeTitle)
                    FineSpacer()
                    FineToggle(
                        isOn: .init(
                            get: { self.settings.isDarkModeEnabled },
                            set: { isEnabled in
                                self.settings.isDarkModeEnabled = isEnabled
                                self.delegate?.settingsScreen(self, didChangeDarkMode: isEnabled)
                            }
                        )
                    )
                    .hugging(.defaultHigh, axis: .horizontal)
                }
                .padding(16)
                .backgroundColor(.secondarySystemGroupedBackground)
                .cornerRadius(12)

                FineLabel(text: language.languageTitle)
                    .font(.preferredFont(forTextStyle: .headline))
                    .textColor(.secondaryLabel)
                    .padding(.init(top: 12, leading: 0, bottom: 0, trailing: 0))

                FineSegmentedControl(
                    titles: DemoLanguage.allCases.map(\.displayName),
                    selection: .init(
                        get: {
                            DemoLanguage.allCases.firstIndex(of: self.settings.language) ?? 0
                        },
                        set: { index in
                            guard DemoLanguage.allCases.indices.contains(index) else { return }
                            let language = DemoLanguage.allCases[index]
                            self.settings.language = language
                            self.delegate?.settingsScreen(self, didChangeLanguage: language)
                        }
                    )
                )
            }
            .padding(16)
        }
        .backgroundColor(.systemGroupedBackground)
    }
}

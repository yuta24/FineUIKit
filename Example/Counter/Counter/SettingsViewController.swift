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

final class SettingsViewController: FineViewController<DemoSettings> {
    private let onAppearanceChange: (Bool) -> Void
    private let onLanguageChange: (DemoLanguage) -> Void

    init(
        settings: DemoSettings,
        onAppearanceChange: @escaping (Bool) -> Void,
        onLanguageChange: @escaping (DemoLanguage) -> Void
    ) {
        self.onAppearanceChange = onAppearanceChange
        self.onLanguageChange = onLanguageChange
        super.init(state: settings)
    }

    override func navigation(_ settings: DemoSettings) -> FineNavigation? {
        FineNavigation(title: settings.language.settingsTitle)
    }

    override func body(_ settings: DemoSettings) -> any Renderable {
        let language = settings.language
        let onAppearanceChange = self.onAppearanceChange
        let onLanguageChange = self.onLanguageChange

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
                            get: { settings.isDarkModeEnabled },
                            set: { [onAppearanceChange] isEnabled in
                                settings.isDarkModeEnabled = isEnabled
                                onAppearanceChange(isEnabled)
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
                            DemoLanguage.allCases.firstIndex(of: settings.language) ?? 0
                        },
                        set: { [onLanguageChange] index in
                            guard DemoLanguage.allCases.indices.contains(index) else { return }
                            let language = DemoLanguage.allCases[index]
                            settings.language = language
                            onLanguageChange(language)
                        }
                    )
                )
            }
            .padding(16)
        }
        .backgroundColor(.systemGroupedBackground)
    }
}

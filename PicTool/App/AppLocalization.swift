import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    var id: Self { self }

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.language) ?? "") ?? .system
    }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(
            from: ["en", "zh-Hans", "zh-Hant"],
            forPreferences: preferredLanguages
        ).first ?? "en"
    }
}

@MainActor
@Observable
final class AppLocalization {
    static let shared = AppLocalization()

    private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: PreferenceKey.language) }
    }

    var locale: Locale {
        Locale(identifier: language.resolvedIdentifier())
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: PreferenceKey.language) ?? "") ?? .system
    }

    // Reading the observable language here also refreshes dynamically generated view text.
    func string(_ key: String.LocalizationValue) -> String {
        Self.string(key, language: language)
    }

    // Processing errors may be created away from the main actor.
    nonisolated static func string(_ key: String.LocalizationValue, language: AppLanguage = .current) -> String {
        let identifier = language.resolvedIdentifier()
        let bundle = Bundle.main.url(forResource: identifier, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? Bundle.main
        return String(localized: key, bundle: bundle, locale: Locale(identifier: identifier))
    }
}

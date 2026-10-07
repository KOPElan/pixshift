import XCTest
import Observation
@testable import PicTool

final class LocalizationTests: XCTestCase {
    @MainActor
    func testLanguageSwitchUpdatesTextAndPersistsTheSelection() throws {
        let suite = "LocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = AppLocalization(defaults: defaults)
        XCTAssertEqual(localization.language, .system)

        let changed = expectation(description: "Language-dependent text invalidates when switching languages")
        withObservationTracking {
            _ = localization.string("import.add_files")
        } onChange: {
            changed.fulfill()
        }

        for (language, expected) in [
            (AppLanguage.simplifiedChinese, "添加图片…"),
            (.traditionalChinese, "加入圖片…"),
            (.english, "Add Images…")
        ] {
            localization.language = language
            XCTAssertEqual(localization.string("import.add_files"), expected)
            XCTAssertEqual(localization.locale.identifier, language.rawValue)
            XCTAssertEqual(AppLocalization(defaults: defaults).language, language)
        }
        wait(for: [changed], timeout: 1)

        localization.language = .system
        XCTAssertEqual(AppLocalization(defaults: defaults).language, .system)
    }

    func testFollowSystemResolvesChineseRegionsAndFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-TW"]), "zh-Hant")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-HK"]), "zh-Hant")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP", "fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP", "zh-TW"]), "zh-Hant")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-CN"]), "en")
    }

    func testAllLanguagesIncludeEveryEnglishStringAndPreservePlaceholders() throws {
        let english = try strings(for: "en")
        XCTAssertFalse(english.isEmpty)
        let placeholders = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|d|@)|\{[a-z]+\}"#)

        for language in ["zh-Hans", "zh-Hant"] {
            let localized = try strings(for: language)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), language)
            for (key, source) in english {
                let translation = try XCTUnwrap(localized[key], "\(language): \(key)")
                XCTAssertFalse(translation.isEmpty, "\(language): \(key)")
                func tokens(in value: String) -> [String] {
                    placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value))
                        .map { (value as NSString).substring(with: $0.range) }
                        .sorted()
                }
                XCTAssertEqual(tokens(in: translation), tokens(in: source), "\(language): \(key)")
            }
        }
    }

    func testRegionalLanguageMatching() {
        let cases = [
            "en-US": "en", "en-GB": "en",
            "zh-Hans": "zh-Hans", "zh-CN": "zh-Hans", "zh-SG": "zh-Hans",
            "zh-Hant": "zh-Hant", "zh-TW": "zh-Hant", "zh-HK": "zh-Hant", "zh-MO": "zh-Hant"
        ]
        for (preference, expected) in cases {
            XCTAssertEqual(
                Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: [preference]).first,
                expected,
                preference
            )
        }
    }

    func testUnsupportedLanguagesFallBackToEnglish() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        for preferences in [["ja-JP"], ["fr-FR", "de-DE"], ["ko-KR"]] {
            XCTAssertEqual(
                Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferences).first,
                "en",
                preferences.joined(separator: ", ")
            )
        }
        XCTAssertEqual(
            Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["ja-JP", "zh-TW"]).first,
            "zh-Hant"
        )
    }

    func testEachLanguageHasLocalizedInterfaceText() throws {
        let cases = [
            "en": ("Add Images…", "PixShift: Resize & Convert Images"),
            "zh-Hans": ("添加图片…", "PixShift：调整尺寸与转换图片"),
            "zh-Hant": ("加入圖片…", "PixShift：調整尺寸與轉換圖片")
        ]
        for (language, expected) in cases {
            let values = try strings(for: language)
            XCTAssertEqual(values["import.add_files"], expected.0)
            XCTAssertEqual(values["PixShift: Resize & Convert Images"], expected.1)
        }
    }

    private func strings(for language: String) throws -> [String: String] {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let data = try Data(contentsOf: directory.appendingPathComponent("Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }
}

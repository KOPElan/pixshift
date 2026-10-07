import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var localization: AppLocalization
    @AppStorage(PreferenceKey.namingTemplate) private var namingTemplate = "{name}_{width}x{height}_{index}"
    @AppStorage(PreferenceKey.jpegQuality) private var jpegQuality = 85.0
    @AppStorage(PreferenceKey.webPQuality) private var webPQuality = 85.0
    @AppStorage(PreferenceKey.heicQuality) private var heicQuality = 85.0
    @AppStorage(PreferenceKey.successfulImageCount) private var successfulImageCount = 0

    var body: some View {
        TabView {
            Form {
                Section("settings.language") {
                    Picker("settings.language", selection: $localization.language) {
                        Text("settings.language.system").tag(AppLanguage.system)
                        Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                        Text(verbatim: "繁體中文").tag(AppLanguage.traditionalChinese)
                        Text(verbatim: "English").tag(AppLanguage.english)
                    }
                }

                Section("settings.naming") {
                    TextField("settings.naming_template", text: $namingTemplate)
                    Text("settings.naming_help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("settings.quality") {
                    qualityRow("JPEG", value: $jpegQuality)
                    qualityRow("WebP", value: $webPQuality)
                    qualityRow("HEIC", value: $heicQuality)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("settings.general", systemImage: "gear")
            }

            Form {
                LabeledContent("settings.successful_count") {
                    Text(successfulImageCount, format: .number)
                        .monospacedDigit()
                }
                Text("settings.local_only")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("settings.statistics", systemImage: "chart.bar")
            }
        }
        .scenePadding()
        .frame(width: 520, height: 460)
    }

    private func qualityRow(_ name: String, value: Binding<Double>) -> some View {
        LabeledContent(name) {
            HStack {
                Slider(value: integerQuality(value), in: 1...100)
                    .frame(width: 220)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    private func integerQuality(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.rounded() }
        )
    }
}

enum PreferenceKey {
    static let language = "preferences.language"
    static let namingTemplate = "preferences.namingTemplate"
    static let jpegQuality = "preferences.jpegQuality"
    static let webPQuality = "preferences.webPQuality"
    static let heicQuality = "preferences.heicQuality"
    static let successfulImageCount = "statistics.successfulImageCount"
    static let resizeMode = "lastBatch.resizeMode"
    static let resizeWidth = "lastBatch.resizeWidth"
    static let resizeHeight = "lastBatch.resizeHeight"
    static let resizePercentage = "lastBatch.resizePercentage"
    static let resizeEdge = "lastBatch.resizeEdge"
    static let allowsUpscaling = "lastBatch.allowsUpscaling"
    static let exportFormat = "lastBatch.exportFormat"
    static let exportQuality = "lastBatch.exportQuality"
    static let destinationMode = "lastBatch.destinationMode"
    static let outputDirectoryBookmark = "preferences.outputDirectoryBookmark"
    static let cropEnabled = "lastBatch.cropEnabled"
    static let cropPreset = "lastBatch.cropPreset"
    static let cropCustomWidth = "lastBatch.cropCustomWidth"
    static let cropCustomHeight = "lastBatch.cropCustomHeight"
    static let normalizedCrop = "lastBatch.normalizedCrop"
}

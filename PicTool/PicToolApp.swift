import SwiftUI

@main
struct PixShiftApp: App {
    @State private var localization = AppLocalization.shared
    @State private var importStore = ImportStore()
    @State private var configuration = BatchConfiguration()
    @State private var batchProcessor = BatchProcessorStore()

    var body: some Scene {
        WindowGroup(Text(localization.string("PixShift: Resize & Convert Images"))) {
            MainWindow(
                importStore: importStore,
                configuration: configuration,
                batchProcessor: batchProcessor
            )
                .environment(\.locale, localization.locale)
                .navigationTitle(localization.string("PixShift: Resize & Convert Images"))
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            ImportCommands(importStore: importStore, language: localization.language)
        }

        Settings {
            SettingsView(localization: localization)
                .environment(\.locale, localization.locale)
        }
    }
}

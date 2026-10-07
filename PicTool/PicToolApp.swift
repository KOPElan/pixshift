import SwiftUI

@main
struct PixShiftApp: App {
    @State private var importStore = ImportStore()
    @State private var configuration = BatchConfiguration()
    @State private var batchProcessor = BatchProcessorStore()

    var body: some Scene {
        WindowGroup("PixShift: Resize & Convert Images") {
            MainWindow(
                importStore: importStore,
                configuration: configuration,
                batchProcessor: batchProcessor
            )
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            ImportCommands(importStore: importStore)
        }

        Settings {
            SettingsView()
        }
    }
}

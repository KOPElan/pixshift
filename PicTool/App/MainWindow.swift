import SwiftUI

@MainActor
struct MainWindow: View {
    let importStore: ImportStore
    @Bindable var configuration: BatchConfiguration
    let batchProcessor: BatchProcessorStore

    var body: some View {
        HSplitView {
            ImageQueueView(store: importStore)
                .frame(
                    minWidth: 460,
                    idealWidth: 640,
                    maxHeight: .infinity,
                    alignment: .top
                )

            ConfigurationView(
                configuration: configuration,
                batchProcessor: batchProcessor,
                items: importStore.items
            )
                .frame(
                    minWidth: 320,
                    idealWidth: 360,
                    maxWidth: 420,
                    maxHeight: .infinity,
                    alignment: .top
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    importStore.chooseFiles()
                } label: {
                    Label("import.add_files", systemImage: "photo.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    importStore.chooseFolders()
                } label: {
                    Label("import.add_folder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    batchProcessor.start(
                        items: importStore.items,
                        configuration: configuration
                    )
                } label: {
                    Label("batch.start", systemImage: "play.fill")
                }
                .disabled(
                    importStore.items.isEmpty
                        || !configuration.isValid
                        || batchProcessor.phase.isActive
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importStore.importURLs(urls)
            return true
        } isTargeted: { isTargeted in
            importStore.isDropTargeted = isTargeted
        }
        .alert("import.error_title", isPresented: importStore.isShowingError) {
            Button("common.ok") {
                importStore.clearError()
            }
        } message: {
            Text(importStore.lastError ?? String(localized: "error.unknown"))
        }
        .alert(
            "recovery.title",
            isPresented: Binding(
                get: { batchProcessor.isShowingRecoveryPrompt },
                set: { batchProcessor.isShowingRecoveryPrompt = $0 }
            )
        ) {
            Button("recovery.cleanup", role: .destructive) {
                batchProcessor.recoverInterruptedRun()
            }
            Button("recovery.keep", role: .cancel) {
                batchProcessor.keepInterruptedFiles()
            }
        } message: {
            Text(String(
                format: String(localized: "recovery.message"),
                batchProcessor.recoveryFileCount
            ))
        }
        .task {
            await batchProcessor.checkForInterruptedRun()
        }
    }
}

@MainActor
struct ImportCommands: Commands {
    let importStore: ImportStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("import.add_files") {
                importStore.chooseFiles()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("import.add_folder") {
                importStore.chooseFolders()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

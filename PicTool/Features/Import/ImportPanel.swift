import AppKit
import UniformTypeIdentifiers

@MainActor
enum ImportPanel {
    static func chooseFiles() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .webP, .heic, .tiff]
        panel.prompt = AppLocalization.shared.string("import.choose")
        return await panel.begin() == .OK ? panel.urls : []
    }

    static func chooseFolders() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = AppLocalization.shared.string("import.choose")
        return await panel.begin() == .OK ? panel.urls : []
    }
}

@MainActor
enum OutputPanel {
    static func chooseDirectory() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = AppLocalization.shared.string("export.choose_folder")
        return await panel.begin() == .OK ? panel.url : nil
    }

    static func authorizeDirectories(required: [URL]) async -> [URL] {
        guard !required.isEmpty else { return [] }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = required.first?.deletingLastPathComponent()
        panel.prompt = AppLocalization.shared.string("permission.authorize")
        panel.message = String(
            format: AppLocalization.shared.string("permission.message"),
            required.count
        )
        return await panel.begin() == .OK ? panel.urls : []
    }
}

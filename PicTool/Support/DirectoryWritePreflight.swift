import Foundation

actor DirectoryWritePreflight {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func missingWritableDirectories(_ directories: [URL]) -> [URL] {
        uniqueDirectories(directories).filter { !canCreateAndRemoveProbe(in: $0) }
    }

    private func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var paths = Set<String>()
        return directories.filter {
            paths.insert($0.standardizedFileURL.path).inserted
        }
    }

    private func canCreateAndRemoveProbe(in directory: URL) -> Bool {
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }

        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return false
        }
        let probe = directory.appendingPathComponent(
            ".pictool-write-check-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            try? fileManager.removeItem(at: probe)
            return false
        }
    }
}

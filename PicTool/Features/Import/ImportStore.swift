import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ImportStore {
    private let scanner = ImportScanner()

    var items: [ImageItem] = []
    var selection = Set<ImageItem.ID>()
    var isImporting = false
    var isDropTargeted = false
    var ignoredCount = 0
    var lastError: String?

    var isShowingError: Binding<Bool> {
        Binding(
            get: { self.lastError != nil },
            set: { if !$0 { self.lastError = nil } }
        )
    }

    func chooseFiles() {
        Task {
            let urls = await ImportPanel.chooseFiles()
            importURLs(urls)
        }
    }

    func chooseFolders() {
        Task {
            let urls = await ImportPanel.chooseFolders()
            importURLs(urls)
        }
    }

    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            isImporting = true
            defer { isImporting = false }

            let result = await scanner.scan(urls)
            ignoredCount += result.ignoredCount

            var existingPaths = Set(items.map { $0.sourceURL.standardizedFileURL.path })
            for data in result.images where existingPaths.insert(data.sourceURL.standardizedFileURL.path).inserted {
                items.append(ImageItem(
                    id: UUID(),
                    sourceURL: data.sourceURL,
                    accessRootURL: data.accessRootURL,
                    typeIdentifier: data.typeIdentifier,
                    pixelSize: data.pixelSize,
                    thumbnail: data.thumbnailData.flatMap(NSImage.init(data:)),
                    importIndex: items.count
                ))
            }

            if !result.errors.isEmpty {
                lastError = String(
                    format: AppLocalization.shared.string("import.partial_failure"),
                    result.errors.count
                )
            }
        }
    }

    func removeSelection() {
        items.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func removeAll() {
        items.removeAll()
        selection.removeAll()
        ignoredCount = 0
    }

    func clearError() {
        lastError = nil
    }
}

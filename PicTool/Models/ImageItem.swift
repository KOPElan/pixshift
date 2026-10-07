import AppKit
import Foundation

struct ImageItem: Identifiable {
    let id: UUID
    let sourceURL: URL
    let accessRootURL: URL
    let typeIdentifier: String
    let pixelSize: PixelSize
    let thumbnail: NSImage?
    let importIndex: Int

    var filename: String { sourceURL.lastPathComponent }
    var formatName: String { sourceURL.pathExtension.uppercased() }
}

struct ImportedImageData: Sendable {
    let sourceURL: URL
    let accessRootURL: URL
    let typeIdentifier: String
    let pixelSize: PixelSize
    let thumbnailData: Data?
}

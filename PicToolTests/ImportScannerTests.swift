import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PicTool

final class ImportScannerTests: XCTestCase {
    func testFolderScanIsNonRecursiveAndSkipsHiddenFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicToolImportScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let visibleImage = root.appendingPathComponent("visible.png")
        let hiddenImage = root.appendingPathComponent(".hidden.png")
        let nestedFolder = root.appendingPathComponent("nested", isDirectory: true)
        let nestedImage = nestedFolder.appendingPathComponent("nested.png")
        let unsupported = root.appendingPathComponent("notes.txt")

        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try makePNG(at: visibleImage, width: 3, height: 2)
        try makePNG(at: hiddenImage, width: 3, height: 2)
        try makePNG(at: nestedImage, width: 3, height: 2)
        try Data("not an image".utf8).write(to: unsupported)

        let result = await ImportScanner().scan([root])

        XCTAssertEqual(result.images.map(\.sourceURL.lastPathComponent), ["visible.png"])
        XCTAssertEqual(result.images.first?.pixelSize, try PixelSize(width: 3, height: 2))
        XCTAssertEqual(result.images.first?.accessRootURL.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.ignoredCount, 2)
    }

    func testDuplicateURLsAreImportedOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicToolImportScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = root.appendingPathComponent("sample.png")
        try makePNG(at: image, width: 1, height: 1)

        let result = await ImportScanner().scan([image, image])
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images.first?.accessRootURL.standardizedFileURL, image.standardizedFileURL)
    }

    private func makePNG(at url: URL, width: Int, height: Int) throws {
        let bytesPerRow = width * 4
        let pixels = Data(repeating: 255, count: bytesPerRow * height)
        let provider = CGDataProvider(data: pixels as CFData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PicTool

final class OutputFolderAuthorizationTests: XCTestCase {
    @MainActor
    func testFirstLaunchRequiresOutputFolderBeforeStarting() throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = BatchConfiguration(defaults: defaults)

        XCTAssertEqual(configuration.destinationMode, .unifiedFolder)
        XCTAssertNil(configuration.unifiedOutputURL)
        XCTAssertFalse(configuration.isValid)
        let processor = BatchProcessorStore()
        processor.start(items: [], configuration: configuration)
        XCTAssertEqual(processor.phase, .idle)
    }

    @MainActor
    func testLegacySourceFolderDefaultRequiresNewOutputChoice() throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(OutputDestinationMode.sourceFolder.rawValue, forKey: PreferenceKey.destinationMode)

        let configuration = BatchConfiguration(defaults: defaults)

        XCTAssertEqual(configuration.destinationMode, .unifiedFolder)
        XCTAssertNil(configuration.unifiedOutputURL)
        XCTAssertFalse(configuration.isValid)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.outputDestinationWasChosen))
    }

    @MainActor
    func testExplicitSourceFolderChoiceIsRemembered() throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = BatchConfiguration(defaults: defaults)
        configuration.destinationMode = .sourceFolder

        let restored = BatchConfiguration(defaults: defaults)

        XCTAssertEqual(restored.destinationMode, .sourceFolder)
        XCTAssertTrue(restored.isValid)
        restored.destinationMode = .unifiedFolder
        XCTAssertFalse(restored.isValid)
        XCTAssertFalse(BatchConfiguration(defaults: defaults).isValid)
    }

    @MainActor
    func testRestoredOutputFolderCanExportFromSeparateSourceFolder() async throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        let sourceDirectory = workspace.appendingPathComponent("source", isDirectory: true)
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = sourceDirectory.appendingPathComponent("image.png")
        let canvas = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(canvas.makeImage())
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(
            source as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(encoder, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))

        let configuration = BatchConfiguration(defaults: defaults)
        configuration.destinationMode = .unifiedFolder
        configuration.unifiedOutputURL = outputDirectory
        XCTAssertNotNil(defaults.data(forKey: PreferenceKey.outputDirectoryBookmark))

        // Recreate configuration to exercise bookmark resolution, as on a subsequent launch.
        let restored = BatchConfiguration(defaults: defaults)
        let directory = try XCTUnwrap(restored.unifiedOutputURL)
        XCTAssertEqual(directory.standardizedFileURL.path, outputDirectory.standardizedFileURL.path)
        XCTAssertEqual(restored.destinationMode, .unifiedFolder)
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
        let missing = await DirectoryWritePreflight().missingWritableDirectories([directory])
        XCTAssertTrue(missing.isEmpty)
        let destination = directory.appendingPathComponent("export.png")
        let result = try await ImageProcessor().process(ImageProcessingRequest(
            sourceURL: source, sourceTypeIdentifier: UTType.png.identifier,
            resizeMode: .percentage(50), allowsUpscaling: false, outputFormat: .png,
            quality: 85, jpegBackground: .white, destinationURL: destination
        ))
        XCTAssertEqual(result.outputSize, try PixelSize(width: 8, height: 6))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path), ["image.png"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path), ["export.png"])
    }

    @MainActor
    func testInvalidBookmarkIsClearedAndRequiresFolderSelection() throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0, 1, 2]), forKey: PreferenceKey.outputDirectoryBookmark)
        defaults.set(OutputDestinationMode.unifiedFolder.rawValue, forKey: PreferenceKey.destinationMode)

        let configuration = BatchConfiguration(defaults: defaults)

        XCTAssertNil(configuration.unifiedOutputURL)
        XCTAssertFalse(configuration.isValid)
        XCTAssertNil(defaults.data(forKey: PreferenceKey.outputDirectoryBookmark))
    }
}

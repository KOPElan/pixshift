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
        XCTAssertTrue(configuration.hasValidProcessingSettings)
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
        XCTAssertTrue(configuration.hasValidProcessingSettings)
    }

    @MainActor
    func testStartingWithoutOutputFolderChoosesFolderAndContinuesExport() async throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let item = try makeImageItem(in: workspace)
        let output = workspace.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let configuration = BatchConfiguration(defaults: defaults)
        var choiceCount = 0
        let store = BatchProcessorStore(
            ledger: RunLedger(storageURL: workspace.appendingPathComponent("ledger.json")),
            chooseOutputDirectory: {
                choiceCount += 1
                return output
            }
        )

        store.start(items: [item], configuration: configuration)
        store.start(items: [item], configuration: configuration)
        try await waitUntilFinished(store)

        XCTAssertEqual(choiceCount, 1, "Repeated clicks must not open duplicate folder pickers")
        XCTAssertEqual(store.phase, .completed)
        XCTAssertEqual(store.successCount, 1)
        XCTAssertTrue(store.failures.isEmpty)
        XCTAssertEqual(configuration.unifiedOutputURL, output)
        XCTAssertNotNil(defaults.data(forKey: PreferenceKey.outputDirectoryBookmark))
        XCTAssertEqual(store.outputURLs.first?.deletingLastPathComponent().standardizedFileURL,
                       output.standardizedFileURL)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: item.sourceURL.deletingLastPathComponent().path), ["source.png"])

        // A subsequent run uses the saved folder without showing the picker again.
        store.start(items: [item], configuration: BatchConfiguration(defaults: defaults))
        try await waitUntilFinished(store)
        XCTAssertEqual(choiceCount, 1)
        XCTAssertEqual(store.phase, .completed)
        XCTAssertEqual(store.successCount, 1)
    }

    @MainActor
    func testCancellingOutputFolderSelectionCreatesNoFilesAndCanRetry() async throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let item = try makeImageItem(in: workspace)
        let ledgerURL = workspace.appendingPathComponent("ledger.json")
        let configuration = BatchConfiguration(defaults: defaults)
        var choiceCount = 0
        let store = BatchProcessorStore(
            ledger: RunLedger(storageURL: ledgerURL),
            chooseOutputDirectory: { choiceCount += 1; return nil }
        )

        for _ in 0..<2 {
            store.start(items: [item], configuration: configuration)
            try await waitUntilFinished(store)
            XCTAssertEqual(store.phase, .idle)
            XCTAssertEqual(store.successCount, 0)
            XCTAssertTrue(store.outputURLs.isEmpty)
            XCTAssertNil(configuration.unifiedOutputURL)
            XCTAssertNil(defaults.data(forKey: PreferenceKey.outputDirectoryBookmark))
            XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerURL.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path), ["input"])
        }
        XCTAssertEqual(choiceCount, 2)
    }

    @MainActor
    func testInvalidProcessingSettingsDoNotOpenFolderPicker() throws {
        let suite = "OutputFolderAuthorizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let item = try makeImageItem(in: workspace)
        let configuration = BatchConfiguration(defaults: defaults)
        configuration.edge = 0
        let store = BatchProcessorStore(chooseOutputDirectory: {
            XCTFail("Invalid settings must be corrected before requesting a folder")
            return nil
        })

        store.start(items: [item], configuration: configuration)

        XCTAssertFalse(configuration.hasValidProcessingSettings)
        XCTAssertEqual(store.phase, .idle)
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

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputFolderStartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    private func makeImageItem(in workspace: URL) throws -> ImageItem {
        let input = workspace.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("source.png")
        let canvas = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(
            source as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(canvas.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return ImageItem(
            id: UUID(), sourceURL: source, accessRootURL: input,
            typeIdentifier: UTType.png.identifier, pixelSize: try PixelSize(width: 16, height: 12),
            thumbnail: nil, importIndex: 0
        )
    }

    @MainActor
    private func waitUntilFinished(_ store: BatchProcessorStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.phase.isActive, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.phase.isActive, "Batch did not finish within five seconds")
    }
}

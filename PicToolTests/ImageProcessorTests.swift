import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PicTool

final class ImageProcessorTests: XCTestCase {
    func testExportsEverySupportedFormat() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("source.png")
        try makeImage(at: sourceURL, type: .png, width: 4, height: 3)

        for format in [ExportFormat.jpeg, .png, .webP, .heic, .tiff] {
            let concrete = try format.resolve(sourceTypeIdentifier: UTType.png.identifier)
            let destinationURL = workspace
                .appendingPathComponent("output-\(format.rawValue)")
                .appendingPathExtension(concrete.filenameExtension)
            let result = try await ImageProcessor().process(ImageProcessingRequest(
                sourceURL: sourceURL,
                sourceTypeIdentifier: UTType.png.identifier,
                resizeMode: .fixedWidth(2),
                allowsUpscaling: false,
                outputFormat: format,
                quality: 85,
                jpegBackground: .white,
                destinationURL: destinationURL
            ))

            XCTAssertEqual(result.outputSize, try PixelSize(width: 2, height: 2), "Format: \(format)")
            let properties = try imageProperties(at: destinationURL)
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2, "Format: \(format)")
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2, "Format: \(format)")
        }
    }

    func testExactModeCenterCropsToRequestedSize() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("source.png")
        let destinationURL = workspace.appendingPathComponent("square.png")
        try makeImage(at: sourceURL, type: .png, width: 8, height: 4)

        let result = try await ImageProcessor().process(ImageProcessingRequest(
            sourceURL: sourceURL,
            sourceTypeIdentifier: UTType.png.identifier,
            resizeMode: .exact(width: 3, height: 3),
            allowsUpscaling: true,
            outputFormat: .png,
            quality: 85,
            jpegBackground: .white,
            destinationURL: destinationURL
        ))

        XCTAssertEqual(result.outputSize, try PixelSize(width: 3, height: 3))
        let properties = try imageProperties(at: destinationURL)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 3)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 3)
    }

    func testCustomCropFeedsResizePipeline() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("source.png")
        let destinationURL = workspace.appendingPathComponent("cropped.png")
        try makeImage(at: sourceURL, type: .png, width: 8, height: 4)

        let result = try await ImageProcessor().process(ImageProcessingRequest(
            sourceURL: sourceURL,
            sourceTypeIdentifier: UTType.png.identifier,
            resizeMode: .fixedWidth(2),
            cropPolicy: CropPolicy(
                aspectRatio: 1,
                normalizedRect: NormalizedCropRect(x: 0.5, y: 0, width: 0.5, height: 1)
            ),
            allowsUpscaling: false,
            outputFormat: .png,
            quality: 85,
            jpegBackground: .white,
            destinationURL: destinationURL
        ))

        XCTAssertEqual(result.outputSize, try PixelSize(width: 2, height: 2))
        let properties = try imageProperties(at: destinationURL)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2)
    }

    func testProcessingLedgerRetainsOnlyCommittedOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("source.png")
        let destinationURL = workspace.appendingPathComponent("output.png")
        let ledger = RunLedger(storageURL: workspace.appendingPathComponent("ledger.json"))
        try makeImage(at: sourceURL, type: .png, width: 4, height: 3)
        try await ledger.begin()

        _ = try await ImageProcessor().process(ImageProcessingRequest(
            sourceURL: sourceURL,
            sourceTypeIdentifier: UTType.png.identifier,
            resizeMode: .percentage(100),
            allowsUpscaling: false,
            outputFormat: .png,
            quality: 85,
            jpegBackground: .white,
            destinationURL: destinationURL
        ), ledger: ledger)

        let snapshot = try await ledger.interruptedRun()
        XCTAssertEqual(snapshot?.files.count, 1)
        XCTAssertEqual(snapshot?.files.first?.kind, .output)
        XCTAssertEqual(snapshot?.files.first?.filename, "output.png")
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: workspace.path))
            .contains { $0.hasPrefix(".pictool-") })
    }

    func testNormalizesOrientationAndRemovesGPS() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("oriented.jpeg")
        let destinationURL = workspace.appendingPathComponent("normalized.jpeg")
        try makeImage(
            at: sourceURL,
            type: .jpeg,
            width: 3,
            height: 2,
            properties: [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 31.2304,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 121.4737,
                    kCGImagePropertyGPSLongitudeRef: "E",
                ],
            ]
        )

        let result = try await ImageProcessor().process(ImageProcessingRequest(
            sourceURL: sourceURL,
            sourceTypeIdentifier: UTType.jpeg.identifier,
            resizeMode: .fixedWidth(2),
            allowsUpscaling: false,
            outputFormat: .jpeg,
            quality: 90,
            jpegBackground: .white,
            destinationURL: destinationURL
        ))

        XCTAssertEqual(result.outputSize, try PixelSize(width: 2, height: 3))
        let properties = try imageProperties(at: destinationURL)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 3)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
    }

    func testNeverOverwritesExistingDestination() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("source.png")
        let destinationURL = workspace.appendingPathComponent("existing.png")
        try makeImage(at: sourceURL, type: .png, width: 1, height: 1)
        try Data("keep me".utf8).write(to: destinationURL)

        do {
            _ = try await ImageProcessor().process(ImageProcessingRequest(
                sourceURL: sourceURL,
                sourceTypeIdentifier: UTType.png.identifier,
                resizeMode: .percentage(100),
                allowsUpscaling: false,
                outputFormat: .png,
                quality: 85,
                jpegBackground: .white,
                destinationURL: destinationURL
            ))
            XCTFail("Expected destinationExists")
        } catch {
            XCTAssertEqual(error as? ImageProcessingError, .destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("keep me".utf8))
    }

    func testConcurrentProcessingPersistsEveryCommittedOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let ledger = RunLedger(storageURL: workspace.appendingPathComponent("ledger.json"))
        try await ledger.begin()

        var requests: [ImageProcessingRequest] = []
        for index in 0..<8 {
            let sourceURL = workspace.appendingPathComponent("source-\(index).png")
            try makeImage(at: sourceURL, type: .png, width: 16, height: 12)
            requests.append(ImageProcessingRequest(
                sourceURL: sourceURL,
                sourceTypeIdentifier: UTType.png.identifier,
                resizeMode: .fixedWidth(8),
                allowsUpscaling: false,
                outputFormat: .png,
                quality: 85,
                jpegBackground: .white,
                destinationURL: workspace.appendingPathComponent("output-\(index).png")
            ))
        }

        await BoundedTaskGroup.run(
            inputs: requests,
            maxConcurrentTasks: 4,
            operation: { _, request in
                try? await ImageProcessor().process(request, ledger: ledger)
            },
            onResult: { _ in }
        )

        let snapshot = try await ledger.interruptedRun()
        XCTAssertEqual(snapshot?.files.count, requests.count)
        XCTAssertTrue(snapshot?.files.allSatisfy { $0.kind == .output } == true)
        for request in requests {
            XCTAssertTrue(FileManager.default.fileExists(atPath: request.destinationURL.path))
        }
    }

    func testCancellationBeforeProcessingCreatesNoOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceURL = workspace.appendingPathComponent("source.png")
        let destinationURL = workspace.appendingPathComponent("cancelled.png")
        try makeImage(at: sourceURL, type: .png, width: 16, height: 12)
        let gate = AsyncGate()

        let task = Task {
            await gate.wait()
            return try await ImageProcessor().process(ImageProcessingRequest(
                sourceURL: sourceURL,
                sourceTypeIdentifier: UTType.png.identifier,
                resizeMode: .percentage(100),
                allowsUpscaling: false,
                outputFormat: .png,
                quality: 85,
                jpegBackground: .white,
                destinationURL: destinationURL
            ))
        }

        while await !gate.hasWaiter {
            await Task.yield()
        }
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicToolImageProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeImage(
        at url: URL,
        type: UTType,
        width: Int,
        height: Int,
        properties: [CFString: Any] = [:]
    ) throws {
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                bytes[offset] = UInt8((offset / 4 * 31) % 255)
                bytes[offset + 1] = 120
                bytes[offset + 2] = 220
                bytes[offset + 3] = 255
            }
        }
        let provider = CGDataProvider(data: pixels as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func imageProperties(at url: URL) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return properties
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasWaiter = false

    func wait() async {
        await withCheckedContinuation { continuation in
            hasWaiter = true
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

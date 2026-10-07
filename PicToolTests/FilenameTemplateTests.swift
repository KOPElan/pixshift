import XCTest
@testable import PicTool

final class FilenameTemplateTests: XCTestCase {
    func testDefaultTemplateRendersOutputMetadata() throws {
        let template = try FilenameTemplate(FilenameTemplate.defaultValue)
        let output = try template.render(
            sourceURL: URL(fileURLWithPath: "/tmp/Photo.png"),
            outputSize: try PixelSize(width: 2_048, height: 1_536),
            index: 2,
            totalCount: 12,
            format: .jpeg
        )
        XCTAssertEqual(output, "Photo_2048x1536_002.jpeg")
    }

    func testExtensionVariableIsNotDuplicated() throws {
        let template = try FilenameTemplate("{name}.{ext}")
        let output = try template.render(
            sourceURL: URL(fileURLWithPath: "/tmp/a.png"),
            outputSize: try PixelSize(width: 1, height: 1),
            index: 1,
            totalCount: 1,
            format: .webP
        )
        XCTAssertEqual(output, "a.webp")
    }

    func testInvalidCharactersAreReplaced() throws {
        let template = try FilenameTemplate("bad:name/{index}")
        let output = try template.render(
            sourceURL: URL(fileURLWithPath: "/tmp/a.png"),
            outputSize: try PixelSize(width: 1, height: 1),
            index: 1,
            totalCount: 1,
            format: .png
        )
        XCTAssertEqual(output, "bad_name_001.png")
    }

    func testRejectsUnknownVariable() throws {
        XCTAssertThrowsError(try FilenameTemplate("{unknown}"))
    }
}

@MainActor
final class BatchConfigurationTests: XCTestCase {
    func testRestoresLastBatchSettings() throws {
        let suiteName = "BatchConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let saved = BatchConfiguration(defaults: defaults)
        saved.mode = .fixedWidth
        saved.width = 1_920
        saved.edge = 1_280
        saved.allowsUpscaling = true
        saved.exportFormat = .webP
        saved.quality = 72
        saved.destinationMode = .unifiedFolder
        saved.namingTemplate = "{name}-{index}"
        saved.cropEnabled = true
        saved.cropPreset = .sixteenNine
        saved.normalizedCrop = NormalizedCropRect(x: 0.2, y: 0.1, width: 0.7, height: 0.6)

        let restored = BatchConfiguration(defaults: defaults)
        XCTAssertEqual(restored.mode, .fixedWidth)
        XCTAssertEqual(restored.width, 1_920)
        XCTAssertEqual(restored.edge, 1_280)
        XCTAssertTrue(restored.allowsUpscaling)
        XCTAssertEqual(restored.exportFormat, .webP)
        XCTAssertEqual(restored.quality, 72)
        XCTAssertEqual(restored.destinationMode, .unifiedFolder)
        XCTAssertEqual(restored.namingTemplate, "{name}-{index}")
        XCTAssertTrue(restored.cropEnabled)
        XCTAssertEqual(restored.cropPreset, .sixteenNine)
        XCTAssertEqual(restored.normalizedCrop, saved.normalizedCrop)
    }
}

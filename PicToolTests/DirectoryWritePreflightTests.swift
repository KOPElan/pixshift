import Foundation
import XCTest
@testable import PicTool

final class DirectoryWritePreflightTests: XCTestCase {
    func testWritableDirectoryPassesWithoutLeavingProbe() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicToolPreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = await DirectoryWritePreflight().missingWritableDirectories([directory, directory])

        XCTAssertTrue(missing.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testMissingPathFailsPreflight() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicToolMissing-\(UUID().uuidString)", isDirectory: true)
        let missing = await DirectoryWritePreflight().missingWritableDirectories([directory])
        XCTAssertEqual(missing.map(\.standardizedFileURL.path), [directory.standardizedFileURL.path])
    }
}

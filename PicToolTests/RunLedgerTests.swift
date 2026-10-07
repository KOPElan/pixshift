import Foundation
import XCTest
@testable import PicTool

final class RunLedgerTests: XCTestCase {
    func testPersistsTemporaryAndCommittedOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let storage = workspace.appendingPathComponent("ledger.json")
        let temporary = workspace.appendingPathComponent("temporary.tmp")
        let output = workspace.appendingPathComponent("output.png")
        let ledger = RunLedger(storageURL: storage)
        try Data("temporary".utf8).write(to: temporary)

        try await ledger.begin()
        try await ledger.recordTemporary(temporary)
        try await ledger.recordOutput(output, matchingFileAt: temporary)
        try await ledger.forget(temporary)

        let restored = try await RunLedger(storageURL: storage).interruptedRun()
        XCTAssertEqual(restored?.files.count, 1)
        XCTAssertEqual(restored?.files.first?.filename, "output.png")
        XCTAssertEqual(restored?.files.first?.kind, .output)
    }

    func testCleanupRemovesOnlyRecordedFilesAndLedger() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let storage = workspace.appendingPathComponent("state/ledger.json")
        let output = workspace.appendingPathComponent("output.png")
        let unrelated = workspace.appendingPathComponent("keep.png")
        try Data("created".utf8).write(to: output)
        try Data("keep".utf8).write(to: unrelated)
        let ledger = RunLedger(storageURL: storage)
        try await ledger.begin()
        try await ledger.recordTemporary(output)

        let failures = try await RunLedger(storageURL: storage).cleanupRecordedFiles()

        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.path))
    }

    func testMissingRecordedFileCountsAsAlreadyCleaned() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let storage = workspace.appendingPathComponent("ledger.json")
        let ledger = RunLedger(storageURL: storage)
        try await ledger.begin()
        try await ledger.recordTemporary(workspace.appendingPathComponent("missing.tmp"))

        let failures = try await ledger.cleanupRecordedFiles()
        let interrupted = try await ledger.interruptedRun()
        XCTAssertTrue(failures.isEmpty)
        XCTAssertNil(interrupted)
    }

    func testCleanupRefusesOutputWhoseFileIdentityChanged() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let storage = workspace.appendingPathComponent("ledger.json")
        let temporary = workspace.appendingPathComponent("temporary.tmp")
        let output = workspace.appendingPathComponent("output.png")
        try Data("owned".utf8).write(to: temporary)
        let ledger = RunLedger(storageURL: storage)
        try await ledger.begin()
        try await ledger.recordTemporary(temporary)
        try await ledger.recordOutput(output, matchingFileAt: temporary)
        try Data("someone else's file".utf8).write(to: output)

        let failures = try await ledger.cleanupRecordedFiles()

        XCTAssertEqual(failures.map(\.lastPathComponent), ["output.png"])
        XCTAssertEqual(try Data(contentsOf: output), Data("someone else's file".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.path))
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicToolRunLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import Foundation
import Darwin

enum RunLedgerError: Error {
    case noActiveRun
    case invalidRecord
}

enum RunLedgerFileKind: String, Codable, Sendable {
    case temporary
    case output
}

struct RunLedgerFileRecord: Codable, Equatable, Sendable {
    let directoryPath: String
    let directoryBookmark: Data?
    let filename: String
    let kind: RunLedgerFileKind
    let fileSystemDevice: UInt64?
    let fileSystemInode: UInt64?
}

struct RunLedgerSnapshot: Codable, Equatable, Sendable {
    let runID: UUID
    let startedAt: Date
    var files: [RunLedgerFileRecord]
}

actor RunLedger {
    private let storageURL: URL
    private let fileManager: FileManager
    private var snapshot: RunLedgerSnapshot?

    init(
        storageURL: URL = RunLedger.defaultStorageURL,
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    static var defaultStorageURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PicTool", isDirectory: true)
            .appendingPathComponent("ActiveRun.json", isDirectory: false)
    }

    func begin() throws {
        snapshot = RunLedgerSnapshot(runID: UUID(), startedAt: Date(), files: [])
        try persist()
    }

    func recordTemporary(_ url: URL) throws {
        try record(url, kind: .temporary)
    }

    func recordOutput(_ url: URL, matchingFileAt ownedURL: URL) throws {
        guard let identity = fileIdentity(at: ownedURL) else {
            throw RunLedgerError.invalidRecord
        }
        try record(url, kind: .output, identity: identity)
    }

    func forget(_ url: URL) throws {
        guard var snapshot else { throw RunLedgerError.noActiveRun }
        let identity = identity(for: url)
        snapshot.files.removeAll {
            $0.directoryPath == identity.directoryPath && $0.filename == identity.filename
        }
        self.snapshot = snapshot
        try persist()
    }

    func finish() throws {
        snapshot = nil
        if fileManager.fileExists(atPath: storageURL.path) {
            try fileManager.removeItem(at: storageURL)
        }
    }

    func interruptedRun() throws -> RunLedgerSnapshot? {
        if let snapshot { return snapshot }
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let data = try Data(contentsOf: storageURL)
        let decoded = try JSONDecoder().decode(RunLedgerSnapshot.self, from: data)
        snapshot = decoded
        return decoded
    }

    func cleanupRecordedFiles() throws -> [URL] {
        guard let snapshot = try interruptedRun() else { return [] }
        var failures: [URL] = []

        for record in snapshot.files {
            guard let resolved = resolve(record) else {
                failures.append(URL(fileURLWithPath: record.directoryPath).appendingPathComponent(record.filename))
                continue
            }
            let directory = resolved.deletingLastPathComponent()
            let accessed = directory.startAccessingSecurityScopedResource()
            do {
                if fileManager.fileExists(atPath: resolved.path) {
                    if let expectedDevice = record.fileSystemDevice,
                       let expectedInode = record.fileSystemInode {
                        guard let actual = fileIdentity(at: resolved),
                              actual.0 == expectedDevice,
                              actual.1 == expectedInode else {
                            failures.append(resolved)
                            if accessed { directory.stopAccessingSecurityScopedResource() }
                            continue
                        }
                    }
                    try fileManager.removeItem(at: resolved)
                }
            } catch {
                failures.append(resolved)
            }
            if accessed { directory.stopAccessingSecurityScopedResource() }
        }

        if failures.isEmpty {
            try finish()
        }
        return failures
    }

    private func record(
        _ url: URL,
        kind: RunLedgerFileKind,
        identity: (UInt64, UInt64)? = nil
    ) throws {
        guard var snapshot else { throw RunLedgerError.noActiveRun }
        let record = try makeRecord(url: url, kind: kind, identity: identity)
        if !snapshot.files.contains(record) {
            snapshot.files.append(record)
            self.snapshot = snapshot
            try persist()
        }
    }

    private func makeRecord(
        url: URL,
        kind: RunLedgerFileKind,
        identity: (UInt64, UInt64)? = nil
    ) throws -> RunLedgerFileRecord {
        let standardized = url.standardizedFileURL
        let filename = standardized.lastPathComponent
        guard !filename.isEmpty, filename != ".", filename != ".." else {
            throw RunLedgerError.invalidRecord
        }
        let directory = standardized.deletingLastPathComponent()
        let bookmark = try? directory.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return RunLedgerFileRecord(
            directoryPath: directory.path,
            directoryBookmark: bookmark,
            filename: filename,
            kind: kind,
            fileSystemDevice: identity?.0,
            fileSystemInode: identity?.1
        )
    }

    private func fileIdentity(at url: URL) -> (UInt64, UInt64)? {
        var information = stat()
        guard lstat(url.path, &information) == 0 else { return nil }
        return (UInt64(information.st_dev), UInt64(information.st_ino))
    }

    private func identity(for url: URL) -> (directoryPath: String, filename: String) {
        let standardized = url.standardizedFileURL
        return (standardized.deletingLastPathComponent().path, standardized.lastPathComponent)
    }

    private func resolve(_ record: RunLedgerFileRecord) -> URL? {
        let directory: URL
        if let bookmark = record.directoryBookmark {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                directory = resolved
            } else {
                directory = URL(fileURLWithPath: record.directoryPath, isDirectory: true)
            }
        } else {
            directory = URL(fileURLWithPath: record.directoryPath, isDirectory: true)
        }
        guard record.filename == URL(fileURLWithPath: record.filename).lastPathComponent else {
            return nil
        }
        return directory.appendingPathComponent(record.filename, isDirectory: false)
    }

    private func persist() throws {
        guard let snapshot else { throw RunLedgerError.noActiveRun }
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: storageURL, options: .atomic)
    }
}

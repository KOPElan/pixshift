import Foundation
import Observation

struct BatchFailure: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let reason: String
}

enum BatchPhase: Equatable {
    case idle
    case preparing
    case processing
    case cancelling
    case completed
    case cancelled
    case cleanupFailed
    case authorizationFailed
    case recoveryAvailable
    case recovering
    case recoveryFailed
    case ledgerFailed

    var isActive: Bool {
        self == .preparing || self == .processing || self == .cancelling || self == .recovering
    }
}

private struct BatchJobSeed: Sendable {
    let sourceURL: URL
    let accessRootURL: URL
    let sourceTypeIdentifier: String
    let sourceSize: PixelSize
    let index: Int
}

private struct BatchWorkItem: Sendable {
    let filename: String
    let request: ImageProcessingRequest
}

private enum BatchJobOutcome: Sendable {
    case success(URL)
    case failure(filename: String, reason: String)
    case cancelled
}

@MainActor
@Observable
final class BatchProcessorStore {
    private let preflight = DirectoryWritePreflight()
    private let ledger = RunLedger()
    private var task: Task<Void, Never>?

    var phase: BatchPhase = .idle
    var totalCount = 0
    var completedCount = 0
    var successCount = 0
    var failures: [BatchFailure] = []
    var cleanupFailureCount = 0
    var authorizationFailureCount = 0
    var recoveryFileCount = 0
    var recoveryFailureCount = 0
    var isShowingRecoveryPrompt = false
    var outputURLs: [URL] = []

    func checkForInterruptedRun() async {
        guard task == nil else { return }
        do {
            guard let interrupted = try await ledger.interruptedRun() else { return }
            if interrupted.files.isEmpty {
                try await ledger.finish()
                return
            }
            recoveryFileCount = interrupted.files.count
            phase = .recoveryAvailable
            isShowingRecoveryPrompt = true
        } catch {
            recoveryFailureCount = 1
            phase = .recoveryFailed
        }
    }

    func recoverInterruptedRun() {
        guard task == nil else { return }
        isShowingRecoveryPrompt = false
        phase = .recovering
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            do {
                let failures = try await ledger.cleanupRecordedFiles()
                recoveryFailureCount = failures.count
                phase = failures.isEmpty ? .cancelled : .recoveryFailed
            } catch {
                recoveryFailureCount = max(1, recoveryFailureCount)
                phase = .recoveryFailed
            }
        }
    }

    func keepInterruptedFiles() {
        guard task == nil else { return }
        isShowingRecoveryPrompt = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            do {
                try await ledger.finish()
                phase = .idle
            } catch {
                recoveryFailureCount = 1
                phase = .recoveryFailed
            }
        }
    }

    func start(items: [ImageItem], configuration: BatchConfiguration) {
        guard task == nil,
              let resizeMode = configuration.resizeMode,
              let template = try? FilenameTemplate(configuration.namingTemplate),
              configuration.isValid else {
            return
        }

        let seeds = items.enumerated().map { offset, item in
            BatchJobSeed(
                sourceURL: item.sourceURL,
                accessRootURL: item.accessRootURL,
                sourceTypeIdentifier: item.typeIdentifier,
                sourceSize: item.pixelSize,
                index: offset + 1
            )
        }
        let exportFormat = configuration.exportFormat
        let quality = configuration.quality
        let allowsUpscaling = configuration.allowsUpscaling
        let cropSettings = configuration.cropSettings
        let destinationMode = configuration.destinationMode
        let unifiedOutputURL = configuration.unifiedOutputURL

        reset(total: seeds.count)
        phase = .preparing
        task = Task { [weak self] in
            guard let self else { return }
            await self.prepareAndRun(
                seeds: seeds,
                resizeMode: resizeMode,
                allowsUpscaling: allowsUpscaling,
                cropSettings: cropSettings,
                exportFormat: exportFormat,
                quality: quality,
                template: template,
                destinationMode: destinationMode,
                unifiedOutputURL: unifiedOutputURL
            )
        }
    }

    private func prepareAndRun(
        seeds: [BatchJobSeed],
        resizeMode: ResizeMode,
        allowsUpscaling: Bool,
        cropSettings: CropSettings,
        exportFormat: ExportFormat,
        quality: Double,
        template: FilenameTemplate,
        destinationMode: OutputDestinationMode,
        unifiedOutputURL: URL?
    ) async {
        var heldURLs = seeds.map(\.accessRootURL)
        if let unifiedOutputURL { heldURLs.append(unifiedOutputURL) }
        var activeScopes = activateSecurityScopes(heldURLs)
        defer {
            for url in activeScopes { url.stopAccessingSecurityScopedResource() }
            task = nil
        }

        let destinations: [URL]
        switch destinationMode {
        case .sourceFolder:
            destinations = seeds.map { $0.sourceURL.deletingLastPathComponent() }
        case .unifiedFolder:
            guard let unifiedOutputURL else {
                authorizationFailureCount = 1
                phase = .authorizationFailed
                return
            }
            destinations = [unifiedOutputURL]
        }

        var missing = await preflight.missingWritableDirectories(destinations)
        if !missing.isEmpty, !Task.isCancelled {
            let grantedURLs = await OutputPanel.authorizeDirectories(required: missing)
            heldURLs.append(contentsOf: grantedURLs)
            activeScopes.append(contentsOf: activateSecurityScopes(grantedURLs))
            missing = await preflight.missingWritableDirectories(destinations)
        }

        guard !Task.isCancelled else {
            phase = .idle
            return
        }
        guard missing.isEmpty else {
            authorizationFailureCount = missing.count
            phase = .authorizationFailed
            return
        }

        do {
            if let interrupted = try await ledger.interruptedRun(), !interrupted.files.isEmpty {
                recoveryFileCount = interrupted.files.count
                phase = .recoveryAvailable
                isShowingRecoveryPrompt = true
                return
            }
            try await ledger.begin()
        } catch {
            phase = .ledgerFailed
            return
        }

        withExtendedLifetime(heldURLs) {}
        phase = .processing
        await run(
            seeds: seeds,
            resizeMode: resizeMode,
            allowsUpscaling: allowsUpscaling,
            cropSettings: cropSettings,
            exportFormat: exportFormat,
            quality: quality,
            template: template,
            destinationMode: destinationMode,
            unifiedOutputURL: unifiedOutputURL
        )
        withExtendedLifetime(heldURLs) {}
    }

    private func activateSecurityScopes(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.filter { url in
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else { return false }
            return url.startAccessingSecurityScopedResource()
        }
    }

    func cancel() {
        guard phase == .processing else { return }
        phase = .cancelling
        task?.cancel()
    }

    private func run(
        seeds: [BatchJobSeed],
        resizeMode: ResizeMode,
        allowsUpscaling: Bool,
        cropSettings: CropSettings,
        exportFormat: ExportFormat,
        quality: Double,
        template: FilenameTemplate,
        destinationMode: OutputDestinationMode,
        unifiedOutputURL: URL?
    ) async {
        let allocator = OutputURLAllocator()
        var workItems: [BatchWorkItem] = []
        workItems.reserveCapacity(seeds.count)

        for seed in seeds {
            if Task.isCancelled { break }
            do {
                let format = try exportFormat.resolve(sourceTypeIdentifier: seed.sourceTypeIdentifier)
                let cropPolicy = cropSettings.policy(for: seed.sourceSize, resizeMode: resizeMode)
                let sizingSource = try cropPolicy?.croppedPixelSize(in: seed.sourceSize)
                    ?? seed.sourceSize
                let outputSize = try resizeMode.outputSize(
                    for: sizingSource,
                    allowsUpscaling: allowsUpscaling
                )
                let filename = try template.render(
                    sourceURL: seed.sourceURL,
                    outputSize: outputSize,
                    index: seed.index,
                    totalCount: seeds.count,
                    format: format
                )
                let directoryURL: URL
                switch destinationMode {
                case .sourceFolder:
                    directoryURL = seed.sourceURL.deletingLastPathComponent()
                case .unifiedFolder:
                    guard let unifiedOutputURL else {
                        throw ImageProcessingError.unreadableSource
                    }
                    directoryURL = unifiedOutputURL
                }
                let destinationURL = await allocator.reserve(
                    directory: directoryURL,
                    filename: filename
                )
                workItems.append(BatchWorkItem(
                    filename: seed.sourceURL.lastPathComponent,
                    request: ImageProcessingRequest(
                        sourceURL: seed.sourceURL,
                        sourceTypeIdentifier: seed.sourceTypeIdentifier,
                        resizeMode: resizeMode,
                        cropPolicy: cropPolicy,
                        allowsUpscaling: allowsUpscaling,
                        outputFormat: exportFormat,
                        quality: quality,
                        jpegBackground: .white,
                        destinationURL: destinationURL
                    )
                ))
            } catch {
                failures.append(BatchFailure(
                    filename: seed.sourceURL.lastPathComponent,
                    reason: Self.failureDescription(error)
                ))
                completedCount += 1
            }
        }

        let ledger = ledger
        let workerCount = BatchConcurrencyPolicy.recommended()
        let processors = (0..<workerCount).map { _ in ImageProcessor() }
        await BoundedTaskGroup.run(
            inputs: workItems,
            maxConcurrentTasks: workerCount,
            operation: { workerIndex, workItem in
                do {
                    let result = try await processors[workerIndex].process(
                        workItem.request,
                        ledger: ledger
                    )
                    if Task.isCancelled { return .cancelled }
                    return .success(result.destinationURL)
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        return .cancelled
                    }
                    return .failure(
                        filename: workItem.filename,
                        reason: Self.failureDescription(error)
                    )
                }
            },
            onResult: { [weak self] outcome in
                await self?.consume(outcome)
            }
        )

        if Task.isCancelled || phase == .cancelling {
            phase = .cancelling
            do {
                let cleanupFailures = try await ledger.cleanupRecordedFiles()
                cleanupFailureCount = cleanupFailures.count
                if cleanupFailures.isEmpty {
                    outputURLs.removeAll()
                    successCount = 0
                    phase = .cancelled
                } else {
                    phase = .cleanupFailed
                }
            } catch {
                cleanupFailureCount = max(1, cleanupFailureCount)
                phase = .cleanupFailed
            }
        } else {
            let defaults = UserDefaults.standard
            let existingCount = defaults.integer(forKey: PreferenceKey.successfulImageCount)
            defaults.set(existingCount + successCount, forKey: PreferenceKey.successfulImageCount)
            do {
                try await ledger.finish()
                phase = .completed
            } catch {
                phase = .ledgerFailed
            }
        }
    }

    private func consume(_ outcome: BatchJobOutcome) {
        switch outcome {
        case let .success(url):
            outputURLs.append(url)
            successCount += 1
            completedCount += 1
        case let .failure(filename, reason):
            failures.append(BatchFailure(filename: filename, reason: reason))
            completedCount += 1
        case .cancelled:
            break
        }
    }

    private func reset(total: Int) {
        totalCount = total
        completedCount = 0
        successCount = 0
        failures.removeAll()
        cleanupFailureCount = 0
        authorizationFailureCount = 0
        recoveryFailureCount = 0
        outputURLs.removeAll()
    }

    nonisolated private static func failureDescription(_ error: Error) -> String {
        switch error {
        case ImageProcessingError.destinationExists:
            return String(localized: "error.destination_exists")
        case ImageProcessingError.encoderUnavailable:
            return String(localized: "error.encoder_unavailable")
        case ImageProcessingError.unreadableSource, ImageProcessingError.invalidImage:
            return String(localized: "error.unreadable_image")
        default:
            return String(localized: "error.processing_failed")
        }
    }
}

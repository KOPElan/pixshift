import Foundation

enum FilenameTemplateError: Error, Equatable {
    case empty
    case unsupportedVariable
}

struct FilenameTemplate: Sendable {
    static let defaultValue = "{name}_{width}x{height}_{index}"
    private static let supportedVariables = ["{name}", "{width}", "{height}", "{index}", "{ext}"]

    let value: String

    init(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FilenameTemplateError.empty
        }
        var remainder = value
        for variable in Self.supportedVariables {
            remainder = remainder.replacingOccurrences(of: variable, with: "")
        }
        guard !remainder.contains("{") && !remainder.contains("}") else {
            throw FilenameTemplateError.unsupportedVariable
        }
        self.value = value
    }

    func render(
        sourceURL: URL,
        outputSize: PixelSize,
        index: Int,
        totalCount: Int,
        format: ConcreteExportFormat
    ) throws -> String {
        let indexWidth = max(3, String(max(1, totalCount)).count)
        let paddedIndex = String(format: "%0*d", indexWidth, max(1, index))
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent

        var result = value
            .replacingOccurrences(of: "{name}", with: sourceName)
            .replacingOccurrences(of: "{width}", with: String(outputSize.width))
            .replacingOccurrences(of: "{height}", with: String(outputSize.height))
            .replacingOccurrences(of: "{index}", with: paddedIndex)
            .replacingOccurrences(of: "{ext}", with: format.filenameExtension)

        if result.lowercased().hasSuffix(".\(format.filenameExtension.lowercased())") {
            result.removeLast(format.filenameExtension.count + 1)
        }
        result = Self.sanitize(result)
        guard !result.isEmpty else { throw FilenameTemplateError.empty }
        return "\(result).\(format.filenameExtension)"
    }

    private static func sanitize(_ input: String) -> String {
        let sanitizedScalars = input.unicodeScalars.map { scalar -> Character in
            if scalar.value < 32 || scalar == "/" || scalar == ":" {
                return "_"
            }
            return Character(String(scalar))
        }
        let value = String(sanitizedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "." || value == ".." ? "image" : value
    }
}

actor OutputURLAllocator {
    private var reservedPaths = Set<String>()
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func reserve(directory: URL, filename: String) -> URL {
        let requested = directory.appendingPathComponent(filename, isDirectory: false)
        let base = requested.deletingPathExtension().lastPathComponent
        let ext = requested.pathExtension
        var candidate = requested
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path)
            || reservedPaths.contains(candidate.standardizedFileURL.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        reservedPaths.insert(candidate.standardizedFileURL.path)
        return candidate
    }
}


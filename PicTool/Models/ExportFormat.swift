import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case keepOriginal
    case jpeg
    case png
    case webP
    case heic
    case tiff

    var id: Self { self }

    var title: String {
        switch self {
        case .keepOriginal: String(localized: "export.format.keepOriginal")
        case .jpeg: String(localized: "export.format.jpeg")
        case .png: String(localized: "export.format.png")
        case .webP: String(localized: "export.format.webP")
        case .heic: String(localized: "export.format.heic")
        case .tiff: String(localized: "export.format.tiff")
        }
    }

    func resolve(sourceTypeIdentifier: String) throws -> ConcreteExportFormat {
        guard self == .keepOriginal else {
            return ConcreteExportFormat(rawValue: rawValue)!
        }
        guard let format = ConcreteExportFormat(typeIdentifier: sourceTypeIdentifier) else {
            throw ImageProcessingError.unsupportedOutputFormat
        }
        return format
    }
}

enum ConcreteExportFormat: String, Codable, Sendable {
    case jpeg
    case png
    case webP
    case heic
    case tiff

    init?(typeIdentifier: String) {
        switch typeIdentifier {
        case UTType.jpeg.identifier: self = .jpeg
        case UTType.png.identifier: self = .png
        case UTType.webP.identifier: self = .webP
        case UTType.heic.identifier, UTType.heif.identifier: self = .heic
        case UTType.tiff.identifier: self = .tiff
        default: return nil
        }
    }

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .webP: .webP
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    var filenameExtension: String {
        type.preferredFilenameExtension ?? rawValue.lowercased()
    }

    var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .webP, .heic: true
        case .png, .tiff: false
        }
    }

    var supportsAlpha: Bool {
        switch self {
        case .jpeg: false
        case .png, .webP, .heic, .tiff: true
        }
    }
}

import Foundation
import Observation

enum OutputDestinationMode: String, CaseIterable, Identifiable, Sendable {
    case sourceFolder
    case unifiedFolder

    var id: Self { self }

    var title: String {
        switch self {
        case .sourceFolder: String(localized: "export.destination.sourceFolder")
        case .unifiedFolder: String(localized: "export.destination.unifiedFolder")
        }
    }
}

@MainActor
@Observable
final class BatchConfiguration {
    enum Mode: String, CaseIterable, Identifiable {
        case exact
        case percentage
        case fixedWidth
        case fixedHeight
        case longestEdge
        case shortestEdge

        var id: Self { self }

        var title: String {
            switch self {
            case .exact: String(localized: "resize.mode.exact")
            case .percentage: String(localized: "resize.mode.percentage")
            case .fixedWidth: String(localized: "resize.mode.fixedWidth")
            case .fixedHeight: String(localized: "resize.mode.fixedHeight")
            case .longestEdge: String(localized: "resize.mode.longestEdge")
            case .shortestEdge: String(localized: "resize.mode.shortestEdge")
            }
        }
    }

    private let defaults: UserDefaults

    var mode: Mode = .longestEdge {
        didSet { defaults.set(mode.rawValue, forKey: PreferenceKey.resizeMode) }
    }
    var width = 2_048 {
        didSet { defaults.set(width, forKey: PreferenceKey.resizeWidth) }
    }
    var height = 2_048 {
        didSet { defaults.set(height, forKey: PreferenceKey.resizeHeight) }
    }
    var percentage = 50.0 {
        didSet { defaults.set(percentage, forKey: PreferenceKey.resizePercentage) }
    }
    var edge = 2_048 {
        didSet { defaults.set(edge, forKey: PreferenceKey.resizeEdge) }
    }
    var allowsUpscaling = false {
        didSet { defaults.set(allowsUpscaling, forKey: PreferenceKey.allowsUpscaling) }
    }
    var exportFormat: ExportFormat = .keepOriginal {
        didSet { defaults.set(exportFormat.rawValue, forKey: PreferenceKey.exportFormat) }
    }
    var quality = 85.0 {
        didSet { defaults.set(quality, forKey: PreferenceKey.exportQuality) }
    }
    var destinationMode: OutputDestinationMode = .sourceFolder {
        didSet { defaults.set(destinationMode.rawValue, forKey: PreferenceKey.destinationMode) }
    }
    var unifiedOutputURL: URL? {
        didSet { persistOutputDirectoryBookmark() }
    }
    var namingTemplate = FilenameTemplate.defaultValue {
        didSet { defaults.set(namingTemplate, forKey: PreferenceKey.namingTemplate) }
    }
    var cropEnabled = false {
        didSet { defaults.set(cropEnabled, forKey: PreferenceKey.cropEnabled) }
    }
    var cropPreset: CropAspectPreset = .original {
        didSet { defaults.set(cropPreset.rawValue, forKey: PreferenceKey.cropPreset) }
    }
    var cropCustomWidth = 1.0 {
        didSet { defaults.set(cropCustomWidth, forKey: PreferenceKey.cropCustomWidth) }
    }
    var cropCustomHeight = 1.0 {
        didSet { defaults.set(cropCustomHeight, forKey: PreferenceKey.cropCustomHeight) }
    }
    var normalizedCrop = NormalizedCropRect.full {
        didSet {
            if let data = try? JSONEncoder().encode(normalizedCrop) {
                defaults.set(data, forKey: PreferenceKey.normalizedCrop)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawMode = defaults.string(forKey: PreferenceKey.resizeMode),
           let savedMode = Mode(rawValue: rawMode) {
            mode = savedMode
        }
        width = Self.integer(defaults, key: PreferenceKey.resizeWidth, fallback: width)
        height = Self.integer(defaults, key: PreferenceKey.resizeHeight, fallback: height)
        percentage = Self.double(defaults, key: PreferenceKey.resizePercentage, fallback: percentage)
        edge = Self.integer(defaults, key: PreferenceKey.resizeEdge, fallback: edge)
        if defaults.object(forKey: PreferenceKey.allowsUpscaling) != nil {
            allowsUpscaling = defaults.bool(forKey: PreferenceKey.allowsUpscaling)
        }
        if let rawFormat = defaults.string(forKey: PreferenceKey.exportFormat),
           let savedFormat = ExportFormat(rawValue: rawFormat) {
            exportFormat = savedFormat
        }
        quality = Self.double(defaults, key: PreferenceKey.exportQuality, fallback: quality)
        if let rawDestination = defaults.string(forKey: PreferenceKey.destinationMode),
           let savedDestination = OutputDestinationMode(rawValue: rawDestination) {
            destinationMode = savedDestination
        }
        if let template = defaults.string(forKey: PreferenceKey.namingTemplate),
           (try? FilenameTemplate(template)) != nil {
            namingTemplate = template
        }
        unifiedOutputURL = Self.restoreOutputDirectory(from: defaults)
        if defaults.object(forKey: PreferenceKey.cropEnabled) != nil {
            cropEnabled = defaults.bool(forKey: PreferenceKey.cropEnabled)
        }
        if let rawPreset = defaults.string(forKey: PreferenceKey.cropPreset),
           let savedPreset = CropAspectPreset(rawValue: rawPreset) {
            cropPreset = savedPreset
        }
        cropCustomWidth = Self.double(defaults, key: PreferenceKey.cropCustomWidth, fallback: cropCustomWidth)
        cropCustomHeight = Self.double(defaults, key: PreferenceKey.cropCustomHeight, fallback: cropCustomHeight)
        if let data = defaults.data(forKey: PreferenceKey.normalizedCrop),
           let savedCrop = try? JSONDecoder().decode(NormalizedCropRect.self, from: data) {
            normalizedCrop = savedCrop
        }
    }

    var isValid: Bool {
        let resizeIsValid: Bool = switch mode {
        case .exact:
            width > 0 && height > 0
        case .percentage:
            percentage > 0 && percentage.isFinite
        case .fixedWidth, .fixedHeight, .longestEdge, .shortestEdge:
            edge > 0
        }
        let destinationIsValid = destinationMode == .sourceFolder || unifiedOutputURL != nil
        let templateIsValid = (try? FilenameTemplate(namingTemplate)) != nil
        let cropIsValid = !cropEnabled
            || cropPreset != .custom
            || (cropCustomWidth.isFinite && cropCustomHeight.isFinite
                && cropCustomWidth > 0 && cropCustomHeight > 0)
        return resizeIsValid
            && destinationIsValid
            && templateIsValid
            && cropIsValid
            && quality.isFinite
            && (1...100).contains(quality)
    }

    var resizeMode: ResizeMode? {
        guard isValid else { return nil }
        switch mode {
        case .exact:
            return ResizeMode.exact(width: width, height: height)
        case .percentage:
            return ResizeMode.percentage(percentage)
        case .fixedWidth:
            return ResizeMode.fixedWidth(edge)
        case .fixedHeight:
            return ResizeMode.fixedHeight(edge)
        case .longestEdge:
            return ResizeMode.longestEdge(edge)
        case .shortestEdge:
            return ResizeMode.shortestEdge(edge)
        }
    }

    var cropSettings: CropSettings {
        CropSettings(
            isEnabled: cropEnabled,
            preset: cropPreset,
            customWidth: cropCustomWidth,
            customHeight: cropCustomHeight,
            normalizedRect: normalizedCrop
        )
    }

    private func persistOutputDirectoryBookmark() {
        guard let unifiedOutputURL else {
            defaults.removeObject(forKey: PreferenceKey.outputDirectoryBookmark)
            return
        }
        guard let bookmark = try? unifiedOutputURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        defaults.set(bookmark, forKey: PreferenceKey.outputDirectoryBookmark)
    }

    private static func restoreOutputDirectory(from defaults: UserDefaults) -> URL? {
        guard let bookmark = defaults.data(forKey: PreferenceKey.outputDirectoryBookmark) else {
            return nil
        }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private static func integer(_ defaults: UserDefaults, key: String, fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    private static func double(_ defaults: UserDefaults, key: String, fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
}

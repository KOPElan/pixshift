import Foundation

struct PixelSize: Codable, Equatable, Hashable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw ImageConfigurationError.invalidDimensions
        }
        self.width = width
        self.height = height
    }

    var longestEdge: Int { max(width, height) }
    var shortestEdge: Int { min(width, height) }
    var aspectRatio: Double { Double(width) / Double(height) }

    func scaled(by scale: Double) throws -> PixelSize {
        guard scale.isFinite, scale > 0 else {
            throw ImageConfigurationError.invalidScale
        }
        return try PixelSize(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }
}

enum ImageConfigurationError: Error, Equatable, LocalizedError {
    case invalidDimensions
    case invalidScale

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            String(localized: "error.invalid_dimensions")
        case .invalidScale:
            String(localized: "error.invalid_scale")
        }
    }
}


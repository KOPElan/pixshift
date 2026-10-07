import Foundation

enum ResizeMode: Codable, Equatable, Hashable, Sendable {
    case exact(width: Int, height: Int)
    case percentage(Double)
    case fixedWidth(Int)
    case fixedHeight(Int)
    case longestEdge(Int)
    case shortestEdge(Int)

    func outputSize(for source: PixelSize, allowsUpscaling: Bool) throws -> PixelSize {
        switch self {
        case let .exact(width, height):
            let requested = try PixelSize(width: width, height: height)
            guard !allowsUpscaling else { return requested }

            let cropSize = source.maximumCropSize(forAspectRatio: requested.aspectRatio)
            let scale = min(
                1,
                Double(cropSize.width) / Double(requested.width),
                Double(cropSize.height) / Double(requested.height)
            )
            return try requested.scaled(by: scale)

        case let .percentage(percent):
            guard percent.isFinite, percent > 0 else {
                throw ImageConfigurationError.invalidScale
            }
            let scale = allowsUpscaling ? percent / 100 : min(1, percent / 100)
            return try source.scaled(by: scale)

        case let .fixedWidth(width):
            guard width > 0 else { throw ImageConfigurationError.invalidDimensions }
            let scale = Double(width) / Double(source.width)
            return try source.scaled(by: allowsUpscaling ? scale : min(1, scale))

        case let .fixedHeight(height):
            guard height > 0 else { throw ImageConfigurationError.invalidDimensions }
            let scale = Double(height) / Double(source.height)
            return try source.scaled(by: allowsUpscaling ? scale : min(1, scale))

        case let .longestEdge(edge):
            guard edge > 0 else { throw ImageConfigurationError.invalidDimensions }
            let scale = Double(edge) / Double(source.longestEdge)
            return try source.scaled(by: allowsUpscaling ? scale : min(1, scale))

        case let .shortestEdge(edge):
            guard edge > 0 else { throw ImageConfigurationError.invalidDimensions }
            let scale = Double(edge) / Double(source.shortestEdge)
            return try source.scaled(by: allowsUpscaling ? scale : min(1, scale))
        }
    }
}

private extension PixelSize {
    func maximumCropSize(forAspectRatio targetRatio: Double) -> PixelSize {
        if aspectRatio > targetRatio {
            return try! PixelSize(width: Int((Double(height) * targetRatio).rounded(.down)), height: height)
        }
        return try! PixelSize(width: width, height: Int((Double(width) / targetRatio).rounded(.down)))
    }
}


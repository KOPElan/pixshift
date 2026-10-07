import CoreGraphics
import Foundation

enum CropAspectPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case original
    case free
    case square
    case fourThree
    case threeTwo
    case sixteenNine
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .original: String(localized: "crop.ratio.original")
        case .free: String(localized: "crop.ratio.free")
        case .square: String(localized: "crop.ratio.square")
        case .fourThree: String(localized: "crop.ratio.four_three")
        case .threeTwo: String(localized: "crop.ratio.three_two")
        case .sixteenNine: String(localized: "crop.ratio.sixteen_nine")
        case .custom: String(localized: "crop.ratio.custom")
        }
    }

    func aspectRatio(
        for source: PixelSize,
        customWidth: Double,
        customHeight: Double
    ) -> Double? {
        switch self {
        case .original: return source.aspectRatio
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        case .custom:
            guard customWidth.isFinite, customHeight.isFinite,
                  customWidth > 0, customHeight > 0 else { return nil }
            return customWidth / customHeight
        }
    }
}

enum CropHandle: CaseIterable, Hashable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct NormalizedCropRect: Codable, Equatable, Sendable {
    static let full = NormalizedCropRect(x: 0, y: 0, width: 1, height: 1)
    static let minimumLength = 0.02

    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        let safeWidth = min(1, max(Self.minimumLength, width.isFinite ? width : 1))
        let safeHeight = min(1, max(Self.minimumLength, height.isFinite ? height : 1))
        self.width = safeWidth
        self.height = safeHeight
        self.x = min(1 - safeWidth, max(0, x.isFinite ? x : 0))
        self.y = min(1 - safeHeight, max(0, y.isFinite ? y : 0))
    }

    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }

    static func centered(aspectRatio: Double?, sourceSize: PixelSize) -> Self {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return .full }
        let normalizedRatio = aspectRatio / sourceSize.aspectRatio
        if normalizedRatio >= 1 {
            let height = 1 / normalizedRatio
            return Self(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
        return Self(x: (1 - normalizedRatio) / 2, y: 0, width: normalizedRatio, height: 1)
    }

    func fitted(aspectRatio: Double?, sourceSize: PixelSize) -> Self {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return self }
        let normalizedRatio = aspectRatio / sourceSize.aspectRatio
        var fittedWidth = width
        var fittedHeight = height
        if fittedWidth / fittedHeight > normalizedRatio {
            fittedWidth = fittedHeight * normalizedRatio
        } else {
            fittedHeight = fittedWidth / normalizedRatio
        }
        return Self(
            x: Double(center.x) - fittedWidth / 2,
            y: Double(center.y) - fittedHeight / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }

    func moved(dx: Double, dy: Double) -> Self {
        Self(x: x + dx, y: y + dy, width: width, height: height)
    }

    func resized(
        at handle: CropHandle,
        dx: Double,
        dy: Double,
        aspectRatio: Double?,
        sourceSize: PixelSize
    ) -> Self {
        var minX = x
        var minY = y
        var maxX = x + width
        var maxY = y + height

        switch handle {
        case .topLeft: minX += dx; minY += dy
        case .top: minY += dy
        case .topRight: maxX += dx; minY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; maxY += dy
        case .bottom: maxY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .left: minX += dx
        }

        minX = min(maxX - Self.minimumLength, max(0, minX))
        minY = min(maxY - Self.minimumLength, max(0, minY))
        maxX = max(minX + Self.minimumLength, min(1, maxX))
        maxY = max(minY + Self.minimumLength, min(1, maxY))
        let proposed = Self(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return proposed.fitted(aspectRatio: aspectRatio, sourceSize: sourceSize)
    }

    func pixelRect(in sourceSize: PixelSize, aspectRatio: Double?) -> CGRect {
        let fitted = fitted(aspectRatio: aspectRatio, sourceSize: sourceSize)
        let pixelWidth = fitted.width * Double(sourceSize.width)
        let pixelHeight = fitted.height * Double(sourceSize.height)
        let pixelX = fitted.x * Double(sourceSize.width)
        let topY = fitted.y * Double(sourceSize.height)
        return CGRect(
            x: pixelX,
            y: Double(sourceSize.height) - topY - pixelHeight,
            width: pixelWidth,
            height: pixelHeight
        )
    }
}

struct CropPolicy: Codable, Equatable, Sendable {
    let aspectRatio: Double?
    let normalizedRect: NormalizedCropRect

    func pixelRect(in sourceSize: PixelSize) -> CGRect {
        normalizedRect.pixelRect(in: sourceSize, aspectRatio: aspectRatio)
    }

    func croppedPixelSize(in sourceSize: PixelSize) throws -> PixelSize {
        let rect = pixelRect(in: sourceSize)
        return try PixelSize(
            width: max(1, Int(rect.width.rounded())),
            height: max(1, Int(rect.height.rounded()))
        )
    }
}

struct CropSettings: Equatable, Sendable {
    let isEnabled: Bool
    let preset: CropAspectPreset
    let customWidth: Double
    let customHeight: Double
    let normalizedRect: NormalizedCropRect

    func policy(for sourceSize: PixelSize, resizeMode: ResizeMode) -> CropPolicy? {
        guard isEnabled else { return nil }
        let ratio: Double?
        if case let .exact(width, height) = resizeMode {
            ratio = Double(width) / Double(height)
        } else {
            ratio = preset.aspectRatio(
                for: sourceSize,
                customWidth: customWidth,
                customHeight: customHeight
            )
        }
        return CropPolicy(aspectRatio: ratio, normalizedRect: normalizedRect)
    }
}

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGBAColor: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [red, green, blue, alpha]
        )!
    }
}

struct ImageProcessingRequest: Sendable {
    let sourceURL: URL
    let sourceTypeIdentifier: String
    let resizeMode: ResizeMode
    let cropPolicy: CropPolicy?
    let allowsUpscaling: Bool
    let outputFormat: ExportFormat
    let quality: Double
    let jpegBackground: RGBAColor
    let destinationURL: URL

    init(
        sourceURL: URL,
        sourceTypeIdentifier: String,
        resizeMode: ResizeMode,
        cropPolicy: CropPolicy? = nil,
        allowsUpscaling: Bool,
        outputFormat: ExportFormat,
        quality: Double,
        jpegBackground: RGBAColor,
        destinationURL: URL
    ) {
        self.sourceURL = sourceURL
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.resizeMode = resizeMode
        self.cropPolicy = cropPolicy
        self.allowsUpscaling = allowsUpscaling
        self.outputFormat = outputFormat
        self.quality = quality
        self.jpegBackground = jpegBackground
        self.destinationURL = destinationURL
    }
}

struct ImageProcessingResult: Sendable {
    let destinationURL: URL
    let outputSize: PixelSize
    let format: ConcreteExportFormat
}

enum ImageProcessingError: Error, Equatable {
    case unreadableSource
    case invalidImage
    case unsupportedOutputFormat
    case encoderUnavailable
    case renderFailed
    case encodeFailed
    case destinationExists
}

actor ImageProcessor {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: true,
    ])
    private let webPEncoder = WebPEncoder()
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func process(_ request: ImageProcessingRequest, ledger: RunLedger? = nil) async throws -> ImageProcessingResult {
        try Task.checkCancellation()
        guard !fileManager.fileExists(atPath: request.destinationURL.path) else {
            throw ImageProcessingError.destinationExists
        }

        let sourceAccessed = request.sourceURL.startAccessingSecurityScopedResource()
        defer { if sourceAccessed { request.sourceURL.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(request.sourceURL as CFURL, nil) else {
            throw ImageProcessingError.unreadableSource
        }
        guard let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw ImageProcessingError.invalidImage
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let orientedImage = normalizedImage(sourceImage, orientation: orientation)
        let sourceSize = try PixelSize(
            width: Int(orientedImage.extent.width.rounded()),
            height: Int(orientedImage.extent.height.rounded())
        )
        let cropRect = sourceCropRect(
            sourceSize: sourceSize,
            resizeMode: request.resizeMode,
            cropPolicy: request.cropPolicy
        )
        let croppedSourceSize = try PixelSize(
            width: max(1, Int(cropRect.width.rounded())),
            height: max(1, Int(cropRect.height.rounded()))
        )
        let outputSize = try request.resizeMode.outputSize(
            for: croppedSourceSize,
            allowsUpscaling: request.allowsUpscaling
        )
        let format = try request.outputFormat.resolve(
            sourceTypeIdentifier: request.sourceTypeIdentifier
        )
        let transformed = transformedImage(
            orientedImage,
            cropRect: cropRect,
            outputSize: outputSize
        )

        let colorSpace = sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard var outputImage = context.createCGImage(
            transformed,
            from: CGRect(x: 0, y: 0, width: outputSize.width, height: outputSize.height),
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw ImageProcessingError.renderFailed
        }

        if !format.supportsAlpha {
            outputImage = try flatten(
                outputImage,
                size: outputSize,
                background: request.jpegBackground.cgColor,
                colorSpace: colorSpace
            )
        }

        try Task.checkCancellation()
        try await write(
            outputImage,
            source: source,
            format: format,
            quality: request.quality,
            destinationURL: request.destinationURL,
            outputSize: outputSize,
            ledger: ledger
        )
        return ImageProcessingResult(
            destinationURL: request.destinationURL,
            outputSize: outputSize,
            format: format
        )
    }

    private func normalizedImage(_ image: CGImage, orientation: Int) -> CIImage {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let oriented = CIImage(cgImage: image, options: [.colorSpace: colorSpace])
            .oriented(forExifOrientation: Int32(orientation))
        return oriented.transformed(
            by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY)
        )
    }

    private func transformedImage(
        _ image: CIImage,
        cropRect: CGRect,
        outputSize: PixelSize
    ) -> CIImage {
        let cropped = image.cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        let scaleX = Double(outputSize.width) / cropRect.width
        let scaleY = Double(outputSize.height) / cropRect.height
        return cropped.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    private func sourceCropRect(
        sourceSize: PixelSize,
        resizeMode: ResizeMode,
        cropPolicy: CropPolicy?
    ) -> CGRect {
        if let cropPolicy {
            return cropPolicy.pixelRect(in: sourceSize)
        }
        let extent = CGRect(x: 0, y: 0, width: sourceSize.width, height: sourceSize.height)
        if case let .exact(width, height) = resizeMode {
            return centeredCropRect(
                in: extent,
                targetAspectRatio: Double(width) / Double(height)
            )
        }
        return extent
    }

    private func centeredCropRect(in extent: CGRect, targetAspectRatio: Double) -> CGRect {
        let sourceAspectRatio = extent.width / extent.height
        if sourceAspectRatio > targetAspectRatio {
            let width = extent.height * targetAspectRatio
            return CGRect(x: extent.midX - width / 2, y: extent.minY, width: width, height: extent.height)
        }
        let height = extent.width / targetAspectRatio
        return CGRect(x: extent.minX, y: extent.midY - height / 2, width: extent.width, height: height)
    }

    private func flatten(
        _ image: CGImage,
        size: PixelSize,
        background: CGColor,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        guard let canvas = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageProcessingError.renderFailed
        }
        canvas.setFillColor(background)
        canvas.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let flattened = canvas.makeImage() else {
            throw ImageProcessingError.renderFailed
        }
        return flattened
    }

    private func write(
        _ image: CGImage,
        source: CGImageSource,
        format: ConcreteExportFormat,
        quality: Double,
        destinationURL: URL,
        outputSize: PixelSize,
        ledger: RunLedger?
    ) async throws {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let directoryAccessed = directoryURL.startAccessingSecurityScopedResource()
        defer { if directoryAccessed { directoryURL.stopAccessingSecurityScopedResource() } }

        let temporaryURL = directoryURL
            .appendingPathComponent(".pictool-\(UUID().uuidString)")
            .appendingPathExtension("tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        if let ledger {
            try await ledger.recordTemporary(temporaryURL)
        }

        if format == .webP {
            let pixels = try rgbaPixels(from: image, size: outputSize)
            let data: Data
            do {
                data = try webPEncoder.encodeRGBA(
                    pixels,
                    width: outputSize.width,
                    height: outputSize.height,
                    bytesPerRow: outputSize.width * 4,
                    quality: quality
                )
            } catch {
                throw ImageProcessingError.encodeFailed
            }
            try data.write(to: temporaryURL, options: .withoutOverwriting)
        } else {
            let availableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            guard availableTypes.contains(format.type.identifier) else {
                throw ImageProcessingError.encoderUnavailable
            }
            guard let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL,
                format.type.identifier as CFString,
                1,
                nil
            ) else {
                throw ImageProcessingError.encodeFailed
            }

            var options: [CFString: Any] = [
                kCGImageMetadataShouldExcludeGPS: true,
            ]
            if format.supportsLossyQuality {
                options[kCGImageDestinationLossyCompressionQuality] = max(0.01, min(1, quality / 100))
            }
            if let sourceMetadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
               let metadata = CGImageMetadataCreateMutableCopy(sourceMetadata) {
                _ = CGImageMetadataSetValueWithPath(
                    metadata,
                    nil,
                    "tiff:Orientation" as CFString,
                    NSNumber(value: 1)
                )
                CGImageDestinationAddImageAndMetadata(
                    destination,
                    image,
                    metadata,
                    options as CFDictionary
                )
            } else {
                options[kCGImageDestinationOrientation] = 1
                CGImageDestinationAddImage(destination, image, options as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else {
                throw ImageProcessingError.encodeFailed
            }
        }

        try Task.checkCancellation()
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ImageProcessingError.destinationExists
        }
        if let ledger {
            try await ledger.recordOutput(destinationURL, matchingFileAt: temporaryURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        if let ledger {
            do {
                try await ledger.forget(temporaryURL)
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }
        }
    }

    private func rgbaPixels(from image: CGImage, size: PixelSize) throws -> Data {
        let bytesPerRow = size.width * 4
        var data = Data(count: bytesPerRow * size.height)
        let rendered = data.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let canvas = CGContext(
                    data: baseAddress,
                    width: size.width,
                    height: size.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        guard rendered else { throw ImageProcessingError.renderFailed }

        data.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = Int(bytes[offset + 3])
                guard alpha > 0, alpha < 255 else { continue }
                for channel in 0..<3 {
                    bytes[offset + channel] = UInt8(min(255, Int(bytes[offset + channel]) * 255 / alpha))
                }
            }
        }
        return data
    }
}

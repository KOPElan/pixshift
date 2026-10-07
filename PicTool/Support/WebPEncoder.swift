import Foundation

enum WebPEncodingError: Error, Equatable {
    case invalidDimensions
    case invalidPixelBuffer
    case invalidQuality
    case encodingFailed
}

struct WebPEncoder: Sendable {
    static let maximumDimension = 16_383

    func encodeRGBA(
        _ pixels: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        quality: Double
    ) throws -> Data {
        guard width > 0,
              height > 0,
              width <= Self.maximumDimension,
              height <= Self.maximumDimension else {
            throw WebPEncodingError.invalidDimensions
        }
        guard bytesPerRow >= width * 4,
              pixels.count >= bytesPerRow * height else {
            throw WebPEncodingError.invalidPixelBuffer
        }
        guard quality.isFinite, (1...100).contains(quality) else {
            throw WebPEncodingError.invalidQuality
        }

        var encodedBytes: UnsafeMutablePointer<UInt8>?
        let encodedSize = pixels.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return WebPEncodeRGBA(
                source,
                Int32(width),
                Int32(height),
                Int32(bytesPerRow),
                Float(quality),
                &encodedBytes
            )
        }

        guard encodedSize > 0, let encodedBytes else {
            throw WebPEncodingError.encodingFailed
        }
        defer { WebPFree(encodedBytes) }
        return Data(bytes: encodedBytes, count: encodedSize)
    }
}


import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PicTool

final class WebPEncoderTests: XCTestCase {
    func testEncodesRGBADataAsDecodableWebP() throws {
        let pixels = Data([
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 0,
        ])

        let encoded = try WebPEncoder().encodeRGBA(
            pixels,
            width: 2,
            height: 2,
            bytesPerRow: 8,
            quality: 85
        )

        XCTAssertEqual(String(data: encoded.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: encoded.dropFirst(8).prefix(4), encoding: .ascii), "WEBP")

        let source = CGImageSourceCreateWithData(encoded as CFData, nil)
        XCTAssertNotNil(source)
        XCTAssertEqual(source.flatMap(CGImageSourceGetType), UTType.webP.identifier as CFString)
        XCTAssertEqual(source.map(CGImageSourceGetCount), 1)
    }

    func testRejectsInvalidInputs() throws {
        let encoder = WebPEncoder()
        XCTAssertThrowsError(
            try encoder.encodeRGBA(Data(), width: 0, height: 1, bytesPerRow: 4, quality: 85)
        )
        XCTAssertThrowsError(
            try encoder.encodeRGBA(Data(repeating: 0, count: 4), width: 1, height: 1, bytesPerRow: 4, quality: 0)
        )
        XCTAssertThrowsError(
            try encoder.encodeRGBA(Data(repeating: 0, count: 4), width: 2, height: 2, bytesPerRow: 8, quality: 85)
        )
    }
}


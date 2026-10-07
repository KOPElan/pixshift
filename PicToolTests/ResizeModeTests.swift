import XCTest
@testable import PicTool

final class ResizeModeTests: XCTestCase {
    private let landscape = try! PixelSize(width: 4_000, height: 3_000)

    func testPercentageScalesBothDimensions() throws {
        XCTAssertEqual(
            try ResizeMode.percentage(50).outputSize(for: landscape, allowsUpscaling: false),
            try PixelSize(width: 2_000, height: 1_500)
        )
    }

    func testPercentageDoesNotUpscaleByDefault() throws {
        XCTAssertEqual(
            try ResizeMode.percentage(200).outputSize(for: landscape, allowsUpscaling: false),
            landscape
        )
    }

    func testPercentageCanUpscale() throws {
        XCTAssertEqual(
            try ResizeMode.percentage(200).outputSize(for: landscape, allowsUpscaling: true),
            try PixelSize(width: 8_000, height: 6_000)
        )
    }

    func testFixedWidthPreservesAspectRatio() throws {
        XCTAssertEqual(
            try ResizeMode.fixedWidth(1_000).outputSize(for: landscape, allowsUpscaling: false),
            try PixelSize(width: 1_000, height: 750)
        )
    }

    func testFixedHeightPreservesAspectRatio() throws {
        XCTAssertEqual(
            try ResizeMode.fixedHeight(600).outputSize(for: landscape, allowsUpscaling: false),
            try PixelSize(width: 800, height: 600)
        )
    }

    func testLongestEdge() throws {
        XCTAssertEqual(
            try ResizeMode.longestEdge(2_000).outputSize(for: landscape, allowsUpscaling: false),
            try PixelSize(width: 2_000, height: 1_500)
        )
    }

    func testShortestEdge() throws {
        XCTAssertEqual(
            try ResizeMode.shortestEdge(1_000).outputSize(for: landscape, allowsUpscaling: false),
            try PixelSize(width: 1_333, height: 1_000)
        )
    }

    func testExactSizeCenterCropDoesNotUpscaleWhenDisabled() throws {
        let small = try PixelSize(width: 800, height: 600)
        XCTAssertEqual(
            try ResizeMode.exact(width: 1_000, height: 1_000).outputSize(for: small, allowsUpscaling: false),
            try PixelSize(width: 600, height: 600)
        )
    }

    func testExactSizeCanUpscale() throws {
        let small = try PixelSize(width: 800, height: 600)
        XCTAssertEqual(
            try ResizeMode.exact(width: 1_000, height: 1_000).outputSize(for: small, allowsUpscaling: true),
            try PixelSize(width: 1_000, height: 1_000)
        )
    }

    func testInvalidValuesThrow() throws {
        XCTAssertThrowsError(try ResizeMode.percentage(0).outputSize(for: landscape, allowsUpscaling: false))
        XCTAssertThrowsError(try ResizeMode.fixedWidth(0).outputSize(for: landscape, allowsUpscaling: false))
        XCTAssertThrowsError(try ResizeMode.exact(width: -1, height: 10).outputSize(for: landscape, allowsUpscaling: false))
    }
}


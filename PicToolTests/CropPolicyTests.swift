import XCTest
@testable import PicTool

final class CropPolicyTests: XCTestCase {
    private let landscape = try! PixelSize(width: 4_000, height: 3_000)

    func testCenteredSquareUsesMaximumHeight() {
        let crop = NormalizedCropRect.centered(aspectRatio: 1, sourceSize: landscape)
        XCTAssertEqual(crop.x, 0.125, accuracy: 0.0001)
        XCTAssertEqual(crop.y, 0, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 0.75, accuracy: 0.0001)
        XCTAssertEqual(crop.height, 1, accuracy: 0.0001)
    }

    func testPixelRectConvertsTopLeftToCoreImageCoordinates() {
        let crop = NormalizedCropRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        let rect = crop.pixelRect(in: landscape, aspectRatio: nil)
        XCTAssertEqual(rect.minX, 2_000, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 1_500, accuracy: 0.001)
        XCTAssertEqual(rect.width, 2_000, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1_500, accuracy: 0.001)
    }

    func testMoveClampsWithoutChangingSize() {
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
            .moved(dx: 0.8, dy: -0.5)
        XCTAssertEqual(crop.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.y, 0, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.height, 0.5, accuracy: 0.0001)
    }

    func testAspectFitKeepsCenterAndStaysInsideBounds() {
        let crop = NormalizedCropRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)
            .fitted(aspectRatio: 16.0 / 9.0, sourceSize: landscape)
        let rect = crop.pixelRect(in: landscape, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(rect.width / rect.height, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(crop.x, 0)
        XCTAssertLessThanOrEqual(crop.x + crop.width, 1)
        XCTAssertLessThanOrEqual(crop.y + crop.height, 1)
    }

    func testSameNormalizedPositionMapsAcrossMixedSizes() {
        let crop = NormalizedCropRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        let portrait = try! PixelSize(width: 3_000, height: 4_000)
        let landscapeRect = crop.pixelRect(in: landscape, aspectRatio: 1)
        let portraitRect = crop.pixelRect(in: portrait, aspectRatio: 1)
        XCTAssertEqual(landscapeRect.midX / 4_000, 0.75, accuracy: 0.001)
        XCTAssertEqual(portraitRect.midX / 3_000, 0.75, accuracy: 0.001)
        XCTAssertEqual(landscapeRect.midY / 3_000, 0.75, accuracy: 0.001)
        XCTAssertEqual(portraitRect.midY / 4_000, 0.75, accuracy: 0.001)
    }
}

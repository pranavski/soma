import XCTest
@testable import Soma

/// MealPhoto prepares captured images for the meal-photos bucket: longest
/// edge capped, never upscaled, JPEG output. These tests pin that contract
/// since the detection model's input quality depends on it.
final class MealPhotoTests: XCTestCase {
    func testDownscalesLongEdgeToMaxDimension() throws {
        let image = solidImage(width: 4000, height: 3000)
        let data = try XCTUnwrap(
            MealPhoto.jpegData(from: image, maxDimension: 1280, quality: 0.7)
        )
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(out.size.width, out.size.height), 1280, accuracy: 1)
        // Aspect ratio survives the resize.
        XCTAssertEqual(out.size.height / out.size.width, 0.75, accuracy: 0.01)
    }

    func testPortraitImagesCapTheHeight() throws {
        let image = solidImage(width: 1500, height: 3000)
        let data = try XCTUnwrap(
            MealPhoto.jpegData(from: image, maxDimension: 1280, quality: 0.7)
        )
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.height, 1280, accuracy: 1)
        XCTAssertLessThanOrEqual(out.size.width, 1280)
    }

    func testNeverUpscalesSmallImages() throws {
        let image = solidImage(width: 600, height: 400)
        let data = try XCTUnwrap(
            MealPhoto.jpegData(from: image, maxDimension: 1280, quality: 0.7)
        )
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width, 600, accuracy: 1)
        XCTAssertEqual(out.size.height, 400, accuracy: 1)
    }

    func testDegenerateImageReturnsNil() {
        XCTAssertNil(MealPhoto.jpegData(from: UIImage(), maxDimension: 1280, quality: 0.7))
    }

    func testOutputIsJPEG() throws {
        let data = try XCTUnwrap(
            MealPhoto.uploadData(from: solidImage(width: 100, height: 100))
        )
        // JPEG magic bytes FF D8.
        XCTAssertEqual([UInt8](data.prefix(2)), [0xFF, 0xD8])
    }

    // MARK: - Helpers

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

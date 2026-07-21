import UIKit

/// Prepares a captured meal photo for upload. The detection model doesn't
/// benefit from more than ~1280px on the long edge, and the private bucket
/// shouldn't accumulate 12MP originals — downscale + JPEG on-device before
/// any bytes leave the phone.
enum MealPhoto {
    static let maxDimension: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.7

    static func uploadData(from image: UIImage) -> Data? {
        jpegData(from: image, maxDimension: maxDimension, quality: jpegQuality)
    }

    /// Scales so the longest edge is at most `maxDimension` (never
    /// upscales) and re-encodes as JPEG. Returns nil for degenerate images.
    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat,
        quality: CGFloat
    ) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(
            width: (size.width * scale).rounded(.down),
            height: (size.height * scale).rounded(.down)
        )
        guard target.width >= 1, target.height >= 1 else { return nil }

        // Renderer scale pinned to 1 so target points == output pixels,
        // regardless of the source image's screen scale.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

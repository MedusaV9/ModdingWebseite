import ImageIO
import UIKit

/// Decodes remote/picked images directly at their display budget instead of
/// materializing the full camera-resolution bitmap first.
enum BoundedImageDecoder {
    static func image(data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image)
    }

    /// EXIF capture time of the ORIGINAL picked bytes. Must run BEFORE the
    /// re-encode: `jpegData(compressionQuality:)` writes a metadata-free JPEG
    /// (good — GPS never leaves the phone), so the date would be gone after.
    static func takenAt(data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        return ExifDateParser.takenAt(
            dateTimeOriginal: stamp,
            offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
    }
}

import UIKit

/// Process-wide pipeline for authenticated media images (Linse 14):
/// one NSCache of DECODED images, decoding off the main thread, and
/// in-flight coalescing so ten recycled grid cells asking for the same
/// photo cost one fetch + one decode — not ten.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init(totalCostLimit: Int = 128 * 1024 * 1024) {
        // Cost = decoded bytes; NSCache additionally evicts under system
        // memory pressure on its own.
        cache.totalCostLimit = totalCostLimit
    }

    /// Same photo, different budgets (grid thumb vs. full screen) are
    /// separate entries — a 2048 px decode must never serve a 300 px cell
    /// budget check, nor vice versa.
    private static func key(baseURL: URL, path: String, maxPixelSize: Int) -> NSString {
        "\(baseURL.absoluteString)|\(path)|\(maxPixelSize)" as NSString
    }

    /// Synchronous cache peek — lets views skip the empty-phase flash
    /// entirely when the decoded image is already resident.
    func cachedImage(baseURL: URL, path: String, maxPixelSize: Int) -> UIImage? {
        cache.object(forKey: Self.key(baseURL: baseURL, path: path,
                                      maxPixelSize: maxPixelSize))
    }

    func image(api: API, path: String, maxPixelSize: Int) async throws -> UIImage {
        let key = Self.key(baseURL: api.baseURL, path: path, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) { return cached }

        let task: Task<UIImage, Error>
        let isOwner: Bool
        lock.lock()
        if let running = inFlight[key as String] {
            task = running
            isOwner = false
        } else {
            // Detached: fetch AND decode stay off the caller's (main) actor.
            task = Task.detached(priority: .userInitiated) {
                let data = try await api.mediaData(path)
                guard let image = BoundedImageDecoder.image(data: data,
                                                            maxPixelSize: maxPixelSize) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return image
            }
            inFlight[key as String] = task
            isOwner = true
        }
        lock.unlock()

        defer {
            if isOwner {
                lock.lock()
                inFlight[key as String] = nil
                lock.unlock()
            }
        }
        let image = try await task.value
        cache.setObject(image, forKey: key, cost: Self.decodedCost(of: image))
        return image
    }

    private static func decodedCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

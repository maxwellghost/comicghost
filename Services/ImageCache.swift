import Foundation
import AppKit
import ImageIO

/// Decoded-image cache so page turns don't re-read from disk, plus
/// background preloading of upcoming pages.
nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let thumbCache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 12   // a few units in each direction is plenty
        thumbCache.countLimit = 400
    }

    func image(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Decode ahead of time, off the main thread.
    func preload(_ urls: [URL]) {
        Task.detached(priority: .utility) { [weak self] in
            for url in urls {
                _ = self?.image(for: url)
            }
        }
    }

    /// Small decoded thumbnail for the reader filmstrip, cached separately.
    func thumbnail(for url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = NSURL(string: url.absoluteString + "#thumb\(Int(maxPixel))") ?? (url as NSURL)
        if let cached = thumbCache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbCache.setObject(image, forKey: key)
        return image
    }

    func clear() {
        cache.removeAllObjects()
        thumbCache.removeAllObjects()
    }
}

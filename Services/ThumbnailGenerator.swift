import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Extracts + caches cover thumbnails for the library grid.
/// Pulls ONLY the first image out of the archive — no full unpack.
nonisolated enum ThumbnailGenerator {
    static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicGhost/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cachedPath(for itemID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(itemID.uuidString).jpg")
    }

    /// Returns a cached thumbnail path, generating it on first request.
    static func thumbnail(for itemID: UUID, archivePath: String, maxDimension: CGFloat = 500) throws -> URL {
        let cached = cachedPath(for: itemID)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let archiveURL = URL(fileURLWithPath: archivePath)
        let extractor = try ArchiveExtractorRouter.extractor(for: archiveURL)
        let data = try extractor.coverImageData(from: archiveURL)

        try downscale(data: data, to: cached, maxDimension: maxDimension)
        return cached
    }

    /// Rebuilds the thumbnail from a page the caller already has on disk.
    ///
    /// Driven by the "use this page as the cover" action in the reader, which
    /// has the whole comic unpacked already. Taking the page from the caller
    /// avoids unpacking the archive a second time — on a long collection that
    /// is over a gigabyte of pointless work — and means nothing here writes to
    /// the shared unpack directory the open reader is reading from.
    static func regenerate(for itemID: UUID,
                           from pageURL: URL,
                           maxDimension: CGFloat = 500) throws -> URL {
        let cached = cachedPath(for: itemID)
        try? FileManager.default.removeItem(at: cached)

        let data = try Data(contentsOf: pageURL)
        guard !data.isEmpty else {
            throw ArchiveError.extractionFailed("That page couldn't be read")
        }

        try downscale(data: data, to: cached, maxDimension: maxDimension)
        return cached
    }

    private static func downscale(data: Data, to destination: URL, maxDimension: CGFloat) throws {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ArchiveError.extractionFailed("Couldn't read cover image")
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(
                destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
              )
        else {
            throw ArchiveError.extractionFailed("Couldn't generate thumbnail")
        }

        CGImageDestinationAddImage(
            dest, thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else {
            throw ArchiveError.extractionFailed("Couldn't write thumbnail")
        }
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

import Foundation
import ZIPFoundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import AppKit

nonisolated protocol ArchiveExtractor {
    func extractPages(from archiveURL: URL) throws -> [ComicPage]
    func pageCount(of archiveURL: URL) throws -> Int
    /// Just the first image, in memory — no full unpack. Used for thumbnails.
    func coverImageData(from archiveURL: URL) throws -> Data
}

nonisolated enum ArchiveError: Error, LocalizedError {
    case unsupportedFormat(String)
    case extractionFailed(String)
    case unrarNotFound
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        case .extractionFailed(let detail): return "Extraction failed: \(detail)"
        case .unrarNotFound: return "Bundled unrar binary not found."
        case .emptyArchive: return "No readable pages found."
        }
    }
}

nonisolated enum ArchiveSupport {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "avif",
    ]

    static func isImage(_ url: URL) -> Bool {
        isImageName(url.lastPathComponent)
    }

    static func isImageName(_ name: String) -> Bool {
        let base = (name as NSString).lastPathComponent
        guard !base.hasPrefix("."), !name.contains("__MACOSX") else { return false }
        return imageExtensions.contains((base as NSString).pathExtension.lowercased())
    }

    static func sortedByName(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func sortedNames(_ names: [String]) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Where formats that shell out to an external tool unpack their pages.
    /// Everything under `workingRoot` is disposable and rebuilt on demand.
    static var workingRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicGhost", isDirectory: true)
    }

    static func workingDirectory(for archiveURL: URL) throws -> URL {
        let dir = workingRoot
            .appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Throws away one archive's unpacked pages. A 900-page omnibus is well over
    /// a gigabyte on disk, so leaving these behind is not a rounding error.
    static func discardWorkingDirectory(for archiveURL: URL) {
        guard let dir = try? workingDirectory(for: archiveURL) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Clears everything unpacked by a previous run. Called at launch, since a
    /// crash or force quit strands pages that nothing else will ever collect.
    /// Safe unconditionally at that point: nothing is open yet.
    static func purgeWorkingDirectories() {
        try? FileManager.default.removeItem(at: workingRoot)
    }

    // MARK: - Page cache

    /// Defaults key for the cache ceiling, in bytes. 0 means keep nothing.
    static let cacheLimitKey = "unpackedPageCacheLimit"
    static let defaultCacheLimit = 5_000_000_000

    /// The archive the reader currently has open, if any.
    ///
    /// Eviction runs from the reader closing, from launch, and from Settings,
    /// none of which otherwise know what is on screen. Deleting the pages of an
    /// open comic would break it mid-read, so every eviction path consults this
    /// and skips that one directory.
    private static let openLock = NSLock()
    nonisolated(unsafe) private static var openArchiveURL: URL?

    static func markOpen(_ url: URL?) {
        openLock.lock()
        defer { openLock.unlock() }
        openArchiveURL = url
    }

    static var currentlyOpenArchive: URL? {
        openLock.lock()
        defer { openLock.unlock() }
        return openArchiveURL
    }

    /// A missing value means the setting was never touched, which is the
    /// default — reading it as a plain integer would give 0, "keep nothing".
    static var cacheLimit: Int64 {
        let stored = UserDefaults.standard.object(forKey: cacheLimitKey) as? NSNumber
        return stored?.int64Value ?? Int64(defaultCacheLimit)
    }

    /// Marks an archive's pages as just used, so eviction sorts by real reading
    /// order rather than by when the files happened to be written.
    static func touchWorkingDirectory(for archiveURL: URL) {
        guard let dir = try? workingDirectory(for: archiveURL) else { return }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: dir.path
        )
    }

    /// Trims the unpacked-page cache to `cacheLimit`, dropping least recently
    /// used comics first.
    ///
    /// Extraction unpacks an entire archive before the first page draws, and
    /// `extractPages` skips any page already on disk — so these directories are
    /// what makes reopening a comic instant instead of a fresh multi-gigabyte
    /// unpack. Discarding them on close cost 10-20 seconds on every open of a
    /// large omnibus, which is why the reader keeps them now and this bounds
    /// the total instead.
    ///
    /// `keeping` is the archive the reader currently has open. Deleting pages
    /// out from under it would break the open comic, so it is never evicted
    /// regardless of size or age.
    static func enforceCacheLimit(keeping openArchive: URL? = currentlyOpenArchive) {
        trim(to: cacheLimit, keeping: openArchive)
    }

    /// Drops every unpacked comic except the one being read.
    static func evictAll(keeping openArchive: URL? = currentlyOpenArchive) {
        trim(to: 0, keeping: openArchive)
    }

    private static func trim(to limit: Int64, keeping openArchive: URL?) {
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(
            at: workingRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let protectedPath = openArchive.flatMap { try? workingDirectory(for: $0) }?.standardizedFileURL.path

        var candidates: [(url: URL, size: Int64, used: Date)] = []
        var total: Int64 = 0

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let size = directorySize(of: entry)
            total += size
            guard entry.standardizedFileURL.path != protectedPath else { continue }
            let used = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            candidates.append((entry, size, used))
        }

        guard total > limit else { return }

        // Oldest first, so the comic read longest ago goes before a recent one.
        for candidate in candidates.sorted(by: { $0.used < $1.used }) {
            guard total > limit else { break }
            try? fm.removeItem(at: candidate.url)
            total -= candidate.size
        }
    }

    static func directorySize(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            )
            let bytes = values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
            total += Int64(bytes)
        }
        return total
    }

    /// How many loose images a folder needs before it counts as a comic.
    /// Low enough for short one-shots, high enough that a stray cover image
    /// in a series folder doesn't create a phantom entry.
    static let minimumLooseImages = 2

    /// True when a folder should be treated as one comic rather than walked into.
    ///
    /// A folder holding comic archives is a series folder that happens to have
    /// a cover image sitting in it, so it's explicitly excluded.
    static func qualifiesAsLooseComic(_ dir: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return false }

        var images = 0
        for url in contents {
            if ComicArchive.Format(fileExtension: url.pathExtension) != nil { return false }
            if isImage(url) { images += 1 }
        }
        return images >= minimumLooseImages
    }

    /// Images anywhere under a directory — archives often nest pages in a folder.
    static func imagesRecursively(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where isImage(url) {
            found.append(url)
        }
        return sortedByName(found)
    }

    /// Runs a command and returns stdout, or nil on non-zero exit.
    @discardableResult
    static func run(_ executable: URL, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

nonisolated struct ArchiveExtractorRouter {
    static func extractor(for url: URL) throws -> ArchiveExtractor {
        guard let format = ComicArchive.Format.detect(url) else {
            throw ArchiveError.unsupportedFormat(url.pathExtension)
        }
        switch format.backend {
        case .zipFoundation: return CBZExtractor()
        case .unrar: return CBRExtractor()
        case .bsdtar: return BSDTarExtractor()
        case .pdfKit: return PDFExtractor()
        case .loose: return FolderExtractor()
        }
    }
}

// MARK: - ZIP (cbz, zip)

nonisolated struct CBZExtractor: ArchiveExtractor {
    func extractPages(from archiveURL: URL) throws -> [ComicPage] {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let workDir = try ArchiveSupport.workingDirectory(for: archiveURL)

        var extracted: [URL] = []
        for entry in archive where entry.type == .file {
            guard ArchiveSupport.isImageName(entry.path) else { continue }
            let name = (entry.path as NSString).lastPathComponent
            let dest = workDir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) {
                _ = try archive.extract(entry, to: dest)
            }
            extracted.append(dest)
        }

        guard !extracted.isEmpty else { throw ArchiveError.emptyArchive }
        return ArchiveSupport.sortedByName(extracted).enumerated().map {
            ComicPage(index: $0.offset, imageURL: $0.element)
        }
    }

    func pageCount(of archiveURL: URL) throws -> Int {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        var count = 0
        for entry in archive where entry.type == .file {
            if ArchiveSupport.isImageName(entry.path) { count += 1 }
        }
        return count
    }

    func coverImageData(from archiveURL: URL) throws -> Data {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        var imageEntries: [(name: String, entry: Entry)] = []
        for entry in archive where entry.type == .file {
            guard ArchiveSupport.isImageName(entry.path) else { continue }
            imageEntries.append((entry.path, entry))
        }
        guard !imageEntries.isEmpty else { throw ArchiveError.emptyArchive }
        imageEntries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var data = Data()
        _ = try archive.extract(imageEntries[0].entry) { data.append($0) }
        guard !data.isEmpty else { throw ArchiveError.emptyArchive }
        return data
    }
}

// MARK: - Loose images (a folder of pages)

/// Reads a folder of images as a comic.
///
/// Nothing is unpacked — the pages are already files on disk, so this is the
/// only backend where opening an issue costs nothing.
nonisolated struct FolderExtractor: ArchiveExtractor {
    func extractPages(from archiveURL: URL) throws -> [ComicPage] {
        let images = ArchiveSupport.imagesRecursively(in: archiveURL)
        guard !images.isEmpty else { throw ArchiveError.emptyArchive }
        return images.enumerated().map { ComicPage(index: $0.offset, imageURL: $0.element) }
    }

    func pageCount(of archiveURL: URL) throws -> Int {
        ArchiveSupport.imagesRecursively(in: archiveURL).count
    }

    func coverImageData(from archiveURL: URL) throws -> Data {
        guard let first = ArchiveSupport.imagesRecursively(in: archiveURL).first,
              let data = try? Data(contentsOf: first), !data.isEmpty else {
            throw ArchiveError.emptyArchive
        }
        return data
    }
}

// MARK: - RAR (cbr, rar) — bundled unrar

nonisolated struct CBRExtractor: ArchiveExtractor {
    private var unrarURL: URL? {
        Bundle.main.url(forResource: "unrar", withExtension: nil)
    }

    func extractPages(from archiveURL: URL) throws -> [ComicPage] {
        guard let unrar = unrarURL else { throw ArchiveError.unrarNotFound }
        let workDir = try ArchiveSupport.workingDirectory(for: archiveURL)

        guard ArchiveSupport.run(
            unrar, ["e", "-o+", "-inul", archiveURL.path, workDir.path + "/"]
        ) != nil else {
            throw ArchiveError.extractionFailed("unrar failed")
        }

        let contents = ArchiveSupport.imagesRecursively(in: workDir)
        guard !contents.isEmpty else { throw ArchiveError.emptyArchive }
        return contents.enumerated().map { ComicPage(index: $0.offset, imageURL: $0.element) }
    }

    func pageCount(of archiveURL: URL) throws -> Int {
        try listImageNames(in: archiveURL).count
    }

    func coverImageData(from archiveURL: URL) throws -> Data {
        guard let unrar = unrarURL else { throw ArchiveError.unrarNotFound }
        guard let first = try listImageNames(in: archiveURL).first else {
            throw ArchiveError.emptyArchive
        }
        guard let data = ArchiveSupport.run(unrar, ["p", "-inul", archiveURL.path, first]),
              !data.isEmpty else {
            throw ArchiveError.extractionFailed("unrar couldn't read the cover")
        }
        return data
    }

    private func listImageNames(in archiveURL: URL) throws -> [String] {
        guard let unrar = unrarURL else { throw ArchiveError.unrarNotFound }
        guard let data = ArchiveSupport.run(unrar, ["lb", archiveURL.path]),
              let output = String(data: data, encoding: .utf8) else {
            throw ArchiveError.extractionFailed("unrar list failed")
        }
        return ArchiveSupport.sortedNames(
            output.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { ArchiveSupport.isImageName($0) }
        )
    }
}

// MARK: - 7z / tar — macOS bsdtar (libarchive), no bundled binary needed

nonisolated struct BSDTarExtractor: ArchiveExtractor {
    private let tar = URL(fileURLWithPath: "/usr/bin/tar")

    func extractPages(from archiveURL: URL) throws -> [ComicPage] {
        let workDir = try ArchiveSupport.workingDirectory(for: archiveURL)

        guard ArchiveSupport.run(
            tar, ["-xf", archiveURL.path, "-C", workDir.path]
        ) != nil else {
            throw ArchiveError.extractionFailed("Couldn't read \(archiveURL.pathExtension) archive")
        }

        let contents = ArchiveSupport.imagesRecursively(in: workDir)
        guard !contents.isEmpty else { throw ArchiveError.emptyArchive }
        return contents.enumerated().map { ComicPage(index: $0.offset, imageURL: $0.element) }
    }

    func pageCount(of archiveURL: URL) throws -> Int {
        try listImageNames(in: archiveURL).count
    }

    func coverImageData(from archiveURL: URL) throws -> Data {
        guard let first = try listImageNames(in: archiveURL).first else {
            throw ArchiveError.emptyArchive
        }
        // Extract just the one entry to a scratch dir. It belongs to this call
        // alone, so it goes away on the way out rather than waiting for launch.
        // The parent is left alone — an open reader may be using it.
        let scratch = try ArchiveSupport.workingDirectory(for: archiveURL)
            .appendingPathComponent("__cover", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        guard ArchiveSupport.run(
            tar, ["-xf", archiveURL.path, "-C", scratch.path, first]
        ) != nil else {
            throw ArchiveError.extractionFailed("Couldn't extract cover")
        }

        guard let coverURL = ArchiveSupport.imagesRecursively(in: scratch).first,
              let data = try? Data(contentsOf: coverURL), !data.isEmpty else {
            throw ArchiveError.emptyArchive
        }
        return data
    }

    private func listImageNames(in archiveURL: URL) throws -> [String] {
        guard let data = ArchiveSupport.run(tar, ["-tf", archiveURL.path]),
              let output = String(data: data, encoding: .utf8) else {
            throw ArchiveError.extractionFailed("Couldn't list archive")
        }
        return ArchiveSupport.sortedNames(
            output.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { ArchiveSupport.isImageName($0) }
        )
    }
}

// MARK: - PDF — PDFKit renders pages to images

nonisolated struct PDFExtractor: ArchiveExtractor {
    /// Long edge of rendered pages. High enough to zoom into, cheap enough to cache.
    private let renderLongEdge: CGFloat = 2200

    func extractPages(from archiveURL: URL) throws -> [ComicPage] {
        guard let document = PDFDocument(url: archiveURL) else {
            throw ArchiveError.extractionFailed("Couldn't open PDF")
        }
        let workDir = try ArchiveSupport.workingDirectory(for: archiveURL)
        var pages: [ComicPage] = []

        for index in 0..<document.pageCount {
            let dest = workDir.appendingPathComponent(String(format: "page%04d.jpg", index))

            // Re-use previously rendered pages.
            if !FileManager.default.fileExists(atPath: dest.path) {
                guard let page = document.page(at: index) else { continue }
                try render(page: page, to: dest)
            }
            pages.append(ComicPage(index: pages.count, imageURL: dest))
        }

        guard !pages.isEmpty else { throw ArchiveError.emptyArchive }
        return pages
    }

    func pageCount(of archiveURL: URL) throws -> Int {
        guard let document = PDFDocument(url: archiveURL) else {
            throw ArchiveError.extractionFailed("Couldn't open PDF")
        }
        return document.pageCount
    }

    func coverImageData(from archiveURL: URL) throws -> Data {
        guard let document = PDFDocument(url: archiveURL),
              let page = document.page(at: 0) else {
            throw ArchiveError.emptyArchive
        }
        return try renderData(page: page, longEdge: 800)
    }

    // MARK: - Rendering

    private func render(page: PDFPage, to destination: URL) throws {
        let data = try renderData(page: page, longEdge: renderLongEdge)
        try data.write(to: destination)
    }

    private func renderData(page: PDFPage, longEdge: CGFloat) throws -> Data {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            throw ArchiveError.extractionFailed("Empty PDF page")
        }

        let scale = longEdge / max(bounds.width, bounds.height)
        let pixelSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )

        let image = NSImage(size: pixelSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pixelSize).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(
                using: .jpeg, properties: [.compressionFactor: 0.85]
              ) else {
            throw ArchiveError.extractionFailed("Couldn't render PDF page")
        }
        return jpeg
    }
}

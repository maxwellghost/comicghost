import Foundation
import ZIPFoundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import AppKit

protocol ArchiveExtractor {
    func extractPages(from archiveURL: URL) throws -> [ComicPage]
    func pageCount(of archiveURL: URL) throws -> Int
    /// Just the first image, in memory — no full unpack. Used for thumbnails.
    func coverImageData(from archiveURL: URL) throws -> Data
}

enum ArchiveError: Error, LocalizedError {
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

    static func workingDirectory(for archiveURL: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicGhost", isDirectory: true)
            .appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
        guard let format = ComicArchive.Format(fileExtension: url.pathExtension) else {
            throw ArchiveError.unsupportedFormat(url.pathExtension)
        }
        switch format.backend {
        case .zipFoundation: return CBZExtractor()
        case .unrar: return CBRExtractor()
        case .bsdtar: return BSDTarExtractor()
        case .pdfKit: return PDFExtractor()
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
        // Extract just the one entry to a scratch dir.
        let scratch = try ArchiveSupport.workingDirectory(for: archiveURL)
            .appendingPathComponent("__cover", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

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

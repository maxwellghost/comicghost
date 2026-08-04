import Foundation
import ZIPFoundation

/// Extraction is behind a protocol so CBZ and CBR stay independently swappable.
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
        case .unsupportedFormat(let ext): return "Unsupported archive format: .\(ext)"
        case .extractionFailed(let detail): return "Extraction failed: \(detail)"
        case .unrarNotFound: return "Bundled unrar binary not found."
        case .emptyArchive: return "Archive contains no readable images."
        }
    }
}

nonisolated enum ArchiveSupport {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isImageName(_ name: String) -> Bool {
        let base = (name as NSString).lastPathComponent
        guard !base.hasPrefix("."), !base.hasPrefix("__MACOSX") else { return false }
        return imageExtensions.contains((base as NSString).pathExtension.lowercased())
    }

    /// Natural sort so "page2" < "page10".
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
}

nonisolated struct ArchiveExtractorRouter {
    static func extractor(for url: URL) throws -> ArchiveExtractor {
        guard let format = ComicArchive.Format(fileExtension: url.pathExtension) else {
            throw ArchiveError.unsupportedFormat(url.pathExtension)
        }
        switch format {
        case .cbz: return CBZExtractor()
        case .cbr: return CBRExtractor()
        }
    }
}

// MARK: - CBZ (ZIP) — via ZIPFoundation

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

        return ArchiveSupport.sortedByName(extracted).enumerated().map { index, url in
            ComicPage(index: index, imageURL: url)
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
        _ = try archive.extract(imageEntries[0].entry) { chunk in data.append(chunk) }
        guard !data.isEmpty else { throw ArchiveError.emptyArchive }
        return data
    }
}

// MARK: - CBR (RAR) — shells out to the bundled unrar binary

nonisolated struct CBRExtractor: ArchiveExtractor {
    private var unrarURL: URL? {
        Bundle.main.url(forResource: "unrar", withExtension: nil)
    }

    func extractPages(from archiveURL: URL) throws -> [ComicPage] {
        guard let unrar = unrarURL else { throw ArchiveError.unrarNotFound }
        let workDir = try ArchiveSupport.workingDirectory(for: archiveURL)

        let process = Process()
        process.executableURL = unrar
        process.arguments = ["e", "-o+", "-inul", archiveURL.path, workDir.path + "/"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ArchiveError.extractionFailed("unrar exited with status \(process.terminationStatus)")
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: workDir, includingPropertiesForKeys: nil
        ).filter(ArchiveSupport.isImage)

        guard !contents.isEmpty else { throw ArchiveError.emptyArchive }

        return ArchiveSupport.sortedByName(contents).enumerated().map { index, url in
            ComicPage(index: index, imageURL: url)
        }
    }

    func pageCount(of archiveURL: URL) throws -> Int {
        try listImageNames(in: archiveURL).count
    }

    func coverImageData(from archiveURL: URL) throws -> Data {
        guard let unrar = unrarURL else { throw ArchiveError.unrarNotFound }
        let names = try listImageNames(in: archiveURL)
        guard let first = names.first else { throw ArchiveError.emptyArchive }

        let process = Process()
        process.executableURL = unrar
        // p = print a single file to stdout — no unpacking the rest.
        process.arguments = ["p", "-inul", archiveURL.path, first]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            throw ArchiveError.extractionFailed("unrar couldn't read the cover")
        }
        return data
    }

    /// Bare listing of image entries, natural-sorted.
    private func listImageNames(in archiveURL: URL) throws -> [String] {
        guard let unrar = unrarURL else { throw ArchiveError.unrarNotFound }

        let process = Process()
        process.executableURL = unrar
        process.arguments = ["lb", archiveURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            throw ArchiveError.extractionFailed("unrar list failed")
        }

        let names = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { ArchiveSupport.isImageName($0) }

        return ArchiveSupport.sortedNames(names)
    }
}

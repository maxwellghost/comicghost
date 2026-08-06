import Foundation
import ZIPFoundation
import PDFKit

/// What kind of container a file is, from the writer's point of view.
/// Deliberately separate from `ComicArchive.Format` — this only cares about
/// whether the file can be written to, and what it would take to make it
/// writable if it can't.
nonisolated enum WritableKind: Sendable {
    case zip        // cbz, zip
    case rar        // cbr, rar
    case sevenZip   // cb7, 7z
    case tar        // tar
    case pdf
    /// A folder of loose images — ComicInfo.xml just sits inside it.
    case folder
    case unsupported

    static func of(_ url: URL) -> WritableKind {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .folder
        }
        switch url.pathExtension.lowercased() {
        case "cbz", "zip": return .zip
        case "cbr", "rar": return .rar
        case "cb7", "7z":  return .sevenZip
        case "tar":        return .tar
        case "pdf":        return .pdf
        default:           return .unsupported
        }
    }

    /// Containers we can edit without rebuilding them.
    var canWriteDirectly: Bool { self == .zip || self == .folder }

    /// Formats we can offer to rebuild as CBZ.
    var isConvertible: Bool {
        self == .rar || self == .sevenZip || self == .tar
    }

    var displayName: String {
        switch self {
        case .zip: return "CBZ"
        case .rar: return "CBR"
        case .sevenZip: return "CB7"
        case .tar: return "TAR"
        case .pdf: return "PDF"
        case .folder: return "Folder"
        case .unsupported: return "Unsupported"
        }
    }
}

nonisolated enum MetadataWriterError: LocalizedError {
    case unsupportedFormat(String)
    case unrarMissing
    case extractionFailed(String)
    case noImagesFound
    case verificationFailed(String)
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Comic Ghost can't edit metadata in .\(ext) files."
        case .unrarMissing:
            return "The bundled unrar binary is missing, so RAR-based files can't be read."
        case .extractionFailed(let detail):
            return "Couldn't unpack the archive. (\(detail))"
        case .noImagesFound:
            return "No page images were found inside the archive."
        case .verificationFailed(let detail):
            return "The rebuilt file failed verification, so nothing was changed. (\(detail))"
        case .cannotWrite(let detail):
            return detail
        }
    }
}

/// Result of a successful save.
nonisolated struct MetadataWriteResult: Sendable {
    /// Where the file lives now. Differs from the original when a conversion ran.
    let fileURL: URL
    /// True when the archive was rebuilt as a CBZ and the original was trashed.
    let didConvert: Bool
}

/// Reads and writes ComicInfo.xml inside comic archives.
///
/// ZIP work is in-process through ZIPFoundation, matching `CBZExtractor`.
/// RAR and 7z/tar still need their command line tools to unpack, exactly as
/// `CBRExtractor` and `BSDTarExtractor` do, but nothing is ever written back
/// into those formats — they can only be rebuilt as CBZ.
///
/// Every write goes to a temporary file, is verified, and only then replaces
/// the original.
nonisolated enum MetadataWriter {

    static let comicInfoName = "ComicInfo.xml"

    private static let tar = URL(fileURLWithPath: "/usr/bin/tar")

    // MARK: - Reading

    static func read(from url: URL) throws -> ComicInfo {
        switch WritableKind.of(url) {
        case .zip:
            return parseOrEmpty(try readFromZip(url))
        case .rar:
            return parseOrEmpty(try readFromRar(url))
        case .sevenZip, .tar:
            return parseOrEmpty(try readFromTar(url))
        case .pdf:
            return readFromPDF(url)
        case .folder:
            return parseOrEmpty(readFromFolder(url))
        case .unsupported:
            throw MetadataWriterError.unsupportedFormat(url.pathExtension)
        }
    }

    private static func parseOrEmpty(_ data: Data?) -> ComicInfo {
        guard let data, !data.isEmpty else {
            var empty = ComicInfo()
            empty.wasMissing = true
            return empty
        }
        return ComicInfo.parse(data)
    }

    /// Scene releases use every casing imaginable, and some bury the file in a
    /// subfolder, so match on the trailing component rather than the exact path.
    private static func isComicInfoPath(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.lowercased() == "comicinfo.xml"
    }

    private static func readFromZip(_ url: URL) throws -> Data? {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive.first(where: { isComicInfoPath($0.path) }) else { return nil }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    private static func readFromRar(_ url: URL) throws -> Data? {
        let unrar = try unrarURL()
        guard let listing = ArchiveSupport.run(unrar, ["lb", url.path]),
              let name = firstComicInfoName(in: listing) else { return nil }
        return ArchiveSupport.run(unrar, ["p", "-inul", url.path, name])
    }

    private static func readFromTar(_ url: URL) throws -> Data? {
        guard let listing = ArchiveSupport.run(tar, ["-tf", url.path]),
              let name = firstComicInfoName(in: listing) else { return nil }
        return ArchiveSupport.run(tar, ["-xOf", url.path, name])
    }

    private static func firstComicInfoName(in listing: Data) -> String? {
        guard let text = String(data: listing, encoding: .utf8) else { return nil }
        return text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { isComicInfoPath($0) }
    }

    private static func readFromFolder(_ url: URL) -> Data? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        guard let file = contents.first(where: { isComicInfoPath($0.lastPathComponent) }) else {
            return nil
        }
        return try? Data(contentsOf: file)
    }

    private static func readFromPDF(_ url: URL) -> ComicInfo {
        var info = ComicInfo()
        guard let doc = PDFDocument(url: url) else {
            info.wasMissing = true
            return info
        }
        let attrs = doc.documentAttributes ?? [:]
        if let v = attrs[PDFDocumentAttribute.titleAttribute] as? String { info[.title] = v }
        if let v = attrs[PDFDocumentAttribute.authorAttribute] as? String { info[.writer] = v }
        if let v = attrs[PDFDocumentAttribute.subjectAttribute] as? String { info[.summary] = v }
        if let v = attrs[PDFDocumentAttribute.keywordsAttribute] as? String {
            info[.tags] = v
        } else if let list = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            info[.tags] = list.joined(separator: ", ")
        }
        info[.pageCount] = String(doc.pageCount)
        info.wasMissing = attrs.isEmpty
        return info
    }

    // MARK: - Writing

    /// Writes `info` back into the file.
    ///
    /// - Parameter convertToCBZ: when true and the format can't be written to
    ///   directly, the archive is rebuilt as a CBZ beside the original and the
    ///   original is moved to the Trash.
    static func write(_ info: ComicInfo,
                      to url: URL,
                      convertToCBZ: Bool,
                      progress: (@Sendable (String) -> Void)? = nil) throws -> MetadataWriteResult {
        let kind = WritableKind.of(url)

        switch kind {
        case .zip:
            try writeIntoZip(info, at: url)
            return MetadataWriteResult(fileURL: url, didConvert: false)

        case .pdf:
            try writeIntoPDF(info, at: url)
            return MetadataWriteResult(fileURL: url, didConvert: false)

        case .folder:
            try writeIntoFolder(info, at: url)
            return MetadataWriteResult(fileURL: url, didConvert: false)

        case .rar, .sevenZip, .tar:
            guard convertToCBZ else {
                throw MetadataWriterError.cannotWrite(
                    "\(kind.displayName) archives can't be written to. Enable conversion to CBZ to save changes."
                )
            }
            let newURL = try convert(url, kind: kind, info: info, progress: progress)
            return MetadataWriteResult(fileURL: newURL, didConvert: true)

        case .unsupported:
            throw MetadataWriterError.unsupportedFormat(url.pathExtension)
        }
    }

    /// Converts an archive to CBZ, preserving whatever ComicInfo it already had.
    /// Used by the batch converter, where there's no edit to apply.
    static func convertPreservingMetadata(
        _ url: URL,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> MetadataWriteResult {
        let existing = (try? read(from: url)) ?? ComicInfo()
        return try write(existing, to: url, convertToCBZ: true, progress: progress)
    }

    // MARK: In-place CBZ write

    private static func writeIntoZip(_ info: ComicInfo, at url: URL) throws {
        let fm = FileManager.default

        // The temp file sits beside the original so replaceItemAt stays on one
        // volume, and the leading dot keeps the ingest scanner off it.
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".ComicGhost-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temp) }

        // On APFS this is a clone rather than a byte-for-byte copy.
        try fm.copyItem(at: url, to: temp)

        let originalCount = try entryCount(of: temp)

        let archive = try Archive(url: temp, accessMode: .update)

        // Removing an entry rewrites the whole archive, so only do it when
        // there is actually an old one to drop.
        if let existing = archive.first(where: { isComicInfoPath($0.path) }) {
            try archive.remove(existing)
        }

        try add(info, to: archive)
        try verifyZip(temp, expectedMinimumEntries: originalCount)

        _ = try fm.replaceItemAt(url, withItemAt: temp)
    }

    /// ComicInfo.xml is small and compresses well, unlike the pages.
    private static func add(_ info: ComicInfo, to archive: Archive) throws {
        let data = info.xmlData()
        try archive.addEntry(
            with: comicInfoName,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            guard start < end else { return Data() }
            return data.subdata(in: start..<end)
        }
    }

    /// Nothing to repack — the metadata is just a file in the folder.
    /// Any differently-cased existing copy is removed so there's only ever one.
    private static func writeIntoFolder(_ info: ComicInfo, at url: URL) throws {
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for file in contents where isComicInfoPath(file.lastPathComponent)
                && file.lastPathComponent != comicInfoName {
                try? fm.removeItem(at: file)
            }
        }
        try info.xmlData().write(to: url.appendingPathComponent(comicInfoName), options: .atomic)
    }

    // MARK: Conversion to CBZ

    private static func convert(_ url: URL,
                                kind: WritableKind,
                                info: ComicInfo,
                                progress: (@Sendable (String) -> Void)? = nil) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("ComicGhost-convert-\(UUID().uuidString)", isDirectory: true)
        let unpacked = work.appendingPathComponent("contents", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // 1. Unpack, preserving the internal folder structure so page order
        //    survives for nested releases.
        progress?("Unpacking")
        switch kind {
        case .rar:
            let unrar = try unrarURL()
            guard ArchiveSupport.run(unrar, ["x", "-o+", "-inul", url.path, unpacked.path + "/"]) != nil else {
                throw MetadataWriterError.extractionFailed("unrar failed")
            }
        case .sevenZip, .tar:
            guard ArchiveSupport.run(tar, ["-xf", url.path, "-C", unpacked.path]) != nil else {
                throw MetadataWriterError.extractionFailed("couldn't read \(url.pathExtension) archive")
            }
        default:
            throw MetadataWriterError.unsupportedFormat(url.pathExtension)
        }

        // 2. Everything that came out, minus any metadata file being replaced.
        let payload = try filesToRepack(in: unpacked)
        let imageCount = payload.filter { ArchiveSupport.isImage($0) }.count
        guard imageCount > 0 else { throw MetadataWriterError.noImagesFound }

        // 3. Build the new archive.
        progress?("Repacking \(imageCount) pages")
        let built = work.appendingPathComponent("out.cbz")
        let archive = try Archive(url: built, accessMode: .create)

        let prefix = unpacked.path.hasSuffix("/") ? unpacked.path : unpacked.path + "/"
        for file in payload {
            let relative = String(file.path.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }
            // Pages are already compressed; storing them is faster and no larger.
            try archive.addEntry(with: relative, fileURL: file, compressionMethod: .none)
        }
        try add(info, to: archive)

        progress?("Verifying")
        try verifyZip(built, expectedMinimumEntries: imageCount + 1)

        // 4. Pick a destination that can't collide.
        let destination = uniqueDestination(for: url)

        // 5. Original to the Trash first, so a failure here can't leave two
        //    copies of the same issue sitting in the watched folder.
        var trashed: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &trashed)
        } catch {
            throw MetadataWriterError.cannotWrite(
                "Couldn't move the original to the Trash, so the conversion was cancelled. (\(error.localizedDescription))"
            )
        }

        progress?("Finishing")
        do {
            try fm.moveItem(at: built, to: destination)
        } catch {
            // Put the original back rather than leaving nothing behind.
            if let recovered = trashed as URL? {
                try? fm.moveItem(at: recovered, to: url)
            }
            throw MetadataWriterError.cannotWrite(
                "Couldn't write the converted file, so the original was restored. (\(error.localizedDescription))"
            )
        }

        return destination
    }

    /// Every regular file under `dir` except hidden junk and the old metadata,
    /// in natural page order.
    private static func filesToRepack(in dir: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard !url.path.contains("__MACOSX") else { continue }
            guard !isComicInfoPath(url.lastPathComponent) else { continue }
            found.append(url)
        }
        return ArchiveSupport.sortedByName(found)
    }

    private static func uniqueDestination(for original: URL) -> URL {
        let fm = FileManager.default
        let directory = original.deletingLastPathComponent()
        let base = original.deletingPathExtension().lastPathComponent

        var candidate = directory.appendingPathComponent(base).appendingPathExtension("cbz")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base) (\(counter))")
                .appendingPathExtension("cbz")
            counter += 1
        }
        return candidate
    }

    // MARK: PDF write

    private static func writeIntoPDF(_ info: ComicInfo, at url: URL) throws {
        guard let doc = PDFDocument(url: url) else {
            throw MetadataWriterError.cannotWrite("This PDF couldn't be opened for writing.")
        }

        var attrs = doc.documentAttributes ?? [:]
        func set(_ key: PDFDocumentAttribute, _ value: String) {
            if value.isEmpty { attrs.removeValue(forKey: key) }
            else { attrs[key] = value }
        }
        set(.titleAttribute, info[.title])
        set(.authorAttribute, info[.writer])
        set(.subjectAttribute, info[.summary])
        set(.keywordsAttribute, info[.tags])
        doc.documentAttributes = attrs

        let fm = FileManager.default
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".ComicGhost-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temp) }

        guard doc.write(to: temp) else {
            throw MetadataWriterError.cannotWrite("The PDF couldn't be rewritten.")
        }
        guard let check = PDFDocument(url: temp), check.pageCount == doc.pageCount else {
            throw MetadataWriterError.verificationFailed("page count changed")
        }

        _ = try fm.replaceItemAt(url, withItemAt: temp)
    }

    // MARK: - Verification

    private static func entryCount(of url: URL) throws -> Int {
        let archive = try Archive(url: url, accessMode: .read)
        return archive.reduce(into: 0) { count, _ in count += 1 }
    }

    /// A rebuilt archive is only accepted if it reopens, still holds everything
    /// it should, and the metadata just written reads back and parses.
    private static func verifyZip(_ url: URL, expectedMinimumEntries: Int) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw MetadataWriterError.verificationFailed("the rebuilt archive wouldn't reopen")
        }

        var count = 0
        var metadataEntry: Entry?
        for entry in archive {
            count += 1
            if metadataEntry == nil, isComicInfoPath(entry.path) { metadataEntry = entry }
        }

        guard count >= expectedMinimumEntries else {
            throw MetadataWriterError.verificationFailed(
                "expected at least \(expectedMinimumEntries) entries, found \(count)"
            )
        }

        guard let metadataEntry else {
            throw MetadataWriterError.verificationFailed("metadata missing from the rebuilt file")
        }

        var data = Data()
        do {
            _ = try archive.extract(metadataEntry) { data.append($0) }
        } catch {
            throw MetadataWriterError.verificationFailed("metadata couldn't be read back")
        }

        guard !data.isEmpty, !ComicInfo.parse(data).isEmpty else {
            throw MetadataWriterError.verificationFailed("metadata read back empty")
        }
    }

    // MARK: - Tools

    private static func unrarURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "unrar", withExtension: nil) else {
            throw MetadataWriterError.unrarMissing
        }
        return url
    }
}

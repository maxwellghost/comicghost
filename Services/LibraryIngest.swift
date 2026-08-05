import Foundation
import SwiftData
import Observation

/// Scans library folders into SwiftData.
///
/// Work is parallelized across cores and inserts are batched. Scans can be
/// scoped to a whole library or to a single subfolder, so fixing metadata in
/// one series doesn't mean re-walking the entire collection.
@MainActor
@Observable
final class LibraryIngest {
    static let shared = LibraryIngest()

    var isImporting = false
    var processed = 0
    var total = 0
    var currentFileName = ""
    var scopeLabel = ""

    var progress: Double {
        total > 0 ? Double(processed) / Double(total) : 0
    }

    private init() {}

    private struct ScannedFile: Sendable {
        let id: UUID
        let path: String
        let title: String
        let seriesName: String?
        let masterSeries: String?
        let issueNumber: String?
        let pageCount: Int
        let isSpecial: Bool
        let thumbnailPath: String?
    }

    // MARK: - Path helpers

    private nonisolated static func comicFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            guard ComicArchive.Format(fileExtension: url.pathExtension) != nil else { continue }
            found.append(url)
        }
        return found
    }

    /// Folder names between the library root and the file.
    /// root/Dragon Ball/Dragon Ball Z/vol01.cbz -> ["Dragon Ball", "Dragon Ball Z"]
    private nonisolated static func folderChain(for fileURL: URL, root: URL) -> [String] {
        let rootParts = root.standardizedFileURL.pathComponents
        let fileParts = fileURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileParts.count > rootParts.count,
              Array(fileParts.prefix(rootParts.count)) == rootParts else { return [] }
        return Array(fileParts.dropFirst(rootParts.count))
    }

    nonisolated static func parsedMetadata(forPath path: String, rootPath: String? = nil) -> MetadataParser.ParsedMetadata {
        let url = URL(fileURLWithPath: path)
        var hint: String? = nil
        if let rootPath {
            hint = folderChain(for: url, root: URL(fileURLWithPath: rootPath)).last
        }
        return MetadataParser.metadata(for: url, folderHint: hint)
    }

    /// Everything expensive for one file — safe off the main actor.
    private nonisolated static func scan(fileURL: URL, root: URL) -> ScannedFile {
        let id = UUID()
        let chain = folderChain(for: fileURL, root: root)
        let seriesHint = chain.last
        // Anything above the immediate folder becomes the master grouping.
        let master = chain.count >= 2 ? chain[chain.count - 2] : nil

        let parsed = MetadataParser.metadata(for: fileURL, folderHint: seriesHint)
        let extractor = try? ArchiveExtractorRouter.extractor(for: fileURL)
        let count = (try? extractor?.pageCount(of: fileURL)) ?? 0
        let thumb = try? ThumbnailGenerator.thumbnail(for: id, archivePath: fileURL.path)

        return ScannedFile(
            id: id,
            path: fileURL.path,
            title: parsed.title,
            seriesName: parsed.seriesName,
            masterSeries: master.map(MetadataParser.cleanSeriesName),
            issueNumber: parsed.issueNumber,
            pageCount: count ?? 0,
            isSpecial: MetadataParser.looksSpecial(
                issueNumber: parsed.issueNumber, title: parsed.title
            ),
            thumbnailPath: thumb?.path
        )
    }

    // MARK: - Scanning

    /// Scans every library.
    func syncAll(context: ModelContext) async {
        let libraries = (try? context.fetch(FetchDescriptor<ComicLibrary>())) ?? []
        for library in libraries {
            await sync(library: library, context: context)
        }
    }

    /// Scans one library, optionally restricted to a subfolder of it.
    /// A scoped scan only adds and removes within that subfolder.
    func sync(library: ComicLibrary, subfolder: URL? = nil, context: ModelContext) async {
        guard !isImporting else { return }
        guard let root = library.resolveURL() else { return }

        let scanRoot = subfolder ?? root
        let libraryID = library.id
        let scopePath = scanRoot.standardizedFileURL.path

        let filesOnDisk = Self.comicFiles(under: scanRoot)
        let diskPaths = Set(filesOnDisk.map(\.path))

        // Only consider items inside the scanned scope.
        let existing = ((try? context.fetch(FetchDescriptor<LibraryItem>())) ?? [])
            .filter { $0.libraryID == libraryID && $0.filePath.hasPrefix(scopePath) }

        for item in existing where !diskPaths.contains(item.filePath) {
            context.delete(item)
        }

        let existingPaths = Set(existing.map(\.filePath))
        let newFiles = filesOnDisk.filter { !existingPaths.contains($0.path) }
        guard !newFiles.isEmpty else {
            try? context.save()
            return
        }

        isImporting = true
        processed = 0
        total = newFiles.count
        scopeLabel = subfolder?.lastPathComponent ?? library.name
        defer {
            isImporting = false
            currentFileName = ""
            scopeLabel = ""
        }

        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        var pendingSaves = 0

        await withTaskGroup(of: ScannedFile.self) { group in
            var nextIndex = 0

            func addTask() {
                guard nextIndex < newFiles.count else { return }
                let fileURL = newFiles[nextIndex]
                nextIndex += 1
                group.addTask(priority: .utility) {
                    Self.scan(fileURL: fileURL, root: root)
                }
            }

            for _ in 0..<min(maxConcurrent, newFiles.count) { addTask() }

            for await scanned in group {
                let item = LibraryItem(
                    id: scanned.id,
                    filePath: scanned.path,
                    title: scanned.title,
                    pageCount: scanned.pageCount
                )
                item.seriesName = scanned.seriesName
                item.masterSeries = scanned.masterSeries
                item.issueNumber = scanned.issueNumber
                item.isSpecial = scanned.isSpecial
                item.coverThumbnailPath = scanned.thumbnailPath
                item.libraryID = libraryID
                context.insert(item)

                processed += 1
                currentFileName = (scanned.path as NSString).lastPathComponent

                pendingSaves += 1
                if pendingSaves >= 100 {
                    try? context.save()
                    pendingSaves = 0
                }

                addTask()
            }
        }

        try? context.save()
    }

    // MARK: - Metadata refresh

    /// Re-parses metadata. Scope to a library and/or subfolder so fixing one
    /// series doesn't re-walk everything.
    func refreshMetadata(
        context: ModelContext,
        library: ComicLibrary? = nil,
        subfolder: URL? = nil
    ) {
        let all = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        let scopePath = subfolder?.standardizedFileURL.path

        let targets = all.filter { item in
            guard !item.isMetadataLocked else { return false }
            if let library, item.libraryID != library.id { return false }
            if let scopePath, !item.filePath.hasPrefix(scopePath) { return false }
            return true
        }

        // Root path per library, for folder-chain resolution.
        let libraries = (try? context.fetch(FetchDescriptor<ComicLibrary>())) ?? []
        var roots: [UUID: URL] = [:]
        for lib in libraries {
            if let url = lib.resolveURL() { roots[lib.id] = url }
        }

        for item in targets {
            let url = URL(fileURLWithPath: item.filePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let root = item.libraryID.flatMap { roots[$0] }
            let chain = root.map { Self.folderChain(for: url, root: $0) } ?? []
            let parsed = MetadataParser.metadata(for: url, folderHint: chain.last)

            item.title = parsed.title
            item.seriesName = parsed.seriesName
            item.issueNumber = parsed.issueNumber
            item.masterSeries = chain.count >= 2
                ? MetadataParser.cleanSeriesName(chain[chain.count - 2])
                : nil
            item.isSpecial = MetadataParser.looksSpecial(
                issueNumber: parsed.issueNumber, title: parsed.title
            )
        }
        try? context.save()
    }

    // MARK: - Migration

    /// Moves a pre-libraries install onto the new model: creates a library from
    /// the old watched folder and claims any items that have no library yet.
    func migrateLegacyFolderIfNeeded(context: ModelContext) {
        let libraries = (try? context.fetch(FetchDescriptor<ComicLibrary>())) ?? []
        guard libraries.isEmpty else { return }

        let legacyPath = UserDefaults.standard.string(forKey: "watchedFolderPath") ?? ""
        guard !legacyPath.isEmpty else { return }

        let bookmark = UserDefaults.standard.data(forKey: "watchedFolderBookmark")
        let library = ComicLibrary(
            name: (legacyPath as NSString).lastPathComponent,
            path: legacyPath,
            bookmark: bookmark
        )
        context.insert(library)

        let orphans = ((try? context.fetch(FetchDescriptor<LibraryItem>())) ?? [])
            .filter { $0.libraryID == nil }
        for item in orphans {
            item.libraryID = library.id
        }
        try? context.save()
    }
}

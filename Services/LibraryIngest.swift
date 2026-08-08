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
        let issueNumber: String?
        let pageCount: Int
        let isSpecial: Bool
        let thumbnailPath: String?
        let chaptersRaw: String
        let extras: ComicInfoExtras
    }

    /// Everything worth indexing out of ComicInfo beyond series and number.
    nonisolated struct ComicInfoExtras: Sendable {
        var creditsRaw = ""
        var charactersRaw = ""
        var teamsRaw = ""
        var genresRaw = ""
        var storyArc: String?
        var publisher: String?
        var seriesGroup: String?

        static let empty = ComicInfoExtras()
    }

    /// UserDefaults key holding the id of the most recent import, so the
    /// library can offer a review pass over just those items.
    /// nonisolated so `@AppStorage` can reach it from a property initializer.
    nonisolated static let lastImportBatchKey = "lastImportBatch"

    // MARK: - Path helpers

    private nonisolated static func comicFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                // A folder of loose images is one comic, so it gets added and
                // then sealed off — descending would turn every page into an
                // entry of its own.
                if ArchiveSupport.qualifiesAsLooseComic(url) {
                    found.append(url)
                    enumerator.skipDescendants()
                }
                continue
            }
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

        let parsed = MetadataParser.metadata(for: fileURL, folderHint: seriesHint)
        let extractor = try? ArchiveExtractorRouter.extractor(for: fileURL)
        let count = (try? extractor?.pageCount(of: fileURL)) ?? 0
        let thumb = try? ThumbnailGenerator.thumbnail(for: id, archivePath: fileURL.path)
        let parsed_info = comicInfoDetails(in: fileURL)

        return ScannedFile(
            id: id,
            path: fileURL.path,
            title: parsed.title,
            seriesName: parsed.seriesName,
            issueNumber: parsed.issueNumber,
            pageCount: count,
            isSpecial: MetadataParser.looksSpecial(
                issueNumber: parsed.issueNumber, title: parsed.title
            ),
            thumbnailPath: thumb?.path,
            chaptersRaw: parsed_info.chapters,
            extras: parsed_info.extras
        )
    }

    /// Chapter markers and credits, from a single read of ComicInfo.xml.
    ///
    /// Collections mark issue boundaries with a Bookmark attribute on the
    /// relevant <Page>. Files without them come back empty and are treated as
    /// one run of pages.
    private nonisolated static func comicInfoDetails(
        in fileURL: URL
    ) -> (chapters: String, extras: ComicInfoExtras) {
        guard let xml = MetadataParser.readComicInfoXML(from: fileURL),
              let data = xml.data(using: .utf8) else { return ("", .empty) }

        let info = ComicInfo.parse(data)

        let marks = info.chapters
        let chapters = marks.count > 1
            ? marks.map { "\($0.image)\t\($0.bookmark)" }.joined(separator: "\n")
            : ""

        var extras = ComicInfoExtras()
        extras.creditsRaw = LibraryItem.creditRoles
            .compactMap { role -> String? in
                guard let key = ComicInfo.Key(rawValue: role) else { return nil }
                let value = info[key]
                return value.isEmpty ? nil : "\(role)\t\(value)"
            }
            .joined(separator: "\n")

        extras.charactersRaw = LibraryItem.encodeList(
            LibraryItem.splitNames(info[.characters])
        )
        extras.teamsRaw = LibraryItem.encodeList(
            LibraryItem.splitNames(info[.teams])
        )
        extras.genresRaw = LibraryItem.encodeList(
            LibraryItem.splitNames(info[.genre])
        )
        extras.storyArc = info[.storyArc].isEmpty ? nil : info[.storyArc]
        extras.publisher = info[.publisher].isEmpty ? nil : info[.publisher]
        extras.seriesGroup = info[.seriesGroup].isEmpty ? nil : info[.seriesGroup]

        return (chapters, extras)
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

        // Files the user removed from the library but kept on disk.
        let ignored = Set(
            ((try? context.fetch(FetchDescriptor<IgnoredFile>())) ?? []).map(\.path)
        )
        let filesOnDisk = Self.comicFiles(under: scanRoot).filter { !ignored.contains($0.path) }
        let diskPaths = Set(filesOnDisk.map(\.path))

        // Only consider items inside the scanned scope.
        let existing = ((try? context.fetch(FetchDescriptor<LibraryItem>())) ?? [])
            .filter { $0.libraryID == libraryID && $0.filePath.hasPrefix(scopePath) }

        // Reading progress cascades off LibraryItem, and the save below
        // snapshots every progress row the deletes drag in. A row never read
        // from disk is still a fault, which SwiftData traps on instead of
        // snapshotting. Touching the relationship loads it first. This runs at
        // every launch, so missing it meant one moved file crashed the app on
        // startup with no way back in.
        for item in existing where !diskPaths.contains(item.filePath) {
            _ = item.progress?.currentPage
            context.delete(item)
        }

        let existingPaths = Set(existing.map(\.filePath))
        let newFiles = filesOnDisk.filter { !existingPaths.contains($0.path) }
        guard !newFiles.isEmpty else {
            try? context.save()
            return
        }

        let batchID = UUID()
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
                item.issueNumber = scanned.issueNumber
                item.isSpecial = scanned.isSpecial
                item.coverThumbnailPath = scanned.thumbnailPath
                item.libraryID = libraryID
                item.chaptersRaw = scanned.chaptersRaw
                item.creditsRaw = scanned.extras.creditsRaw
                item.charactersRaw = scanned.extras.charactersRaw
                item.teamsRaw = scanned.extras.teamsRaw
                item.genresRaw = scanned.extras.genresRaw
                item.storyArcName = scanned.extras.storyArc
                item.publisherName = scanned.extras.publisher
                item.seriesGroupName = scanned.extras.seriesGroup
                item.importBatchID = batchID
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
        UserDefaults.standard.set(batchID.uuidString, forKey: Self.lastImportBatchKey)
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
            item.isSpecial = MetadataParser.looksSpecial(
                issueNumber: parsed.issueNumber, title: parsed.title
            )

            // Credits and chapters too, so a refresh backfills everything the
            // library was scanned before this existed.
            let details = Self.comicInfoDetails(in: url)
            item.chaptersRaw = details.chapters
            item.creditsRaw = details.extras.creditsRaw
            item.charactersRaw = details.extras.charactersRaw
            item.teamsRaw = details.extras.teamsRaw
            item.genresRaw = details.extras.genresRaw
            item.storyArcName = details.extras.storyArc
            item.publisherName = details.extras.publisher
            item.seriesGroupName = details.extras.seriesGroup
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

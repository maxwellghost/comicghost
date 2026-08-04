import Foundation
import SwiftData
import Observation

/// Scans the watched folder (including subfolders) and syncs it into SwiftData.
///
/// Import runs in parallel across cores: metadata parsing, page counting, and
/// thumbnail generation all happen off the main actor, and inserts are batched
/// so SwiftData isn't saving once per file.
@MainActor
@Observable
final class LibraryIngest {
    static let shared = LibraryIngest()

    var isImporting = false
    var processed = 0
    var total = 0
    var currentFileName = ""

    var progress: Double {
        total > 0 ? Double(processed) / Double(total) : 0
    }

    private init() {}

    /// Everything computed off the main actor for one file.
    private struct ScannedFile: Sendable {
        let id: UUID
        let path: String
        let title: String
        let seriesName: String?
        let issueNumber: String?
        let pageCount: Int
        let isSpecial: Bool
        let thumbnailPath: String?
    }

    // MARK: - Scanning

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

    private nonisolated static func folderHint(for fileURL: URL, root: URL) -> String? {
        let parent = fileURL.deletingLastPathComponent()
        guard parent.standardizedFileURL != root.standardizedFileURL else { return nil }
        return parent.lastPathComponent
    }

    nonisolated static func parsedMetadata(forPath path: String) -> MetadataParser.ParsedMetadata {
        let url = URL(fileURLWithPath: path)
        var hint: String? = nil
        if let root = WatchedFolder.resolve() {
            hint = folderHint(for: url, root: root)
        }
        return MetadataParser.metadata(for: url, folderHint: hint)
    }

    /// All the expensive work for a single file — safe to run off the main actor.
    private nonisolated static func scan(fileURL: URL, hint: String?) -> ScannedFile {
        let id = UUID()
        let parsed = MetadataParser.metadata(for: fileURL, folderHint: hint)
        let extractor = try? ArchiveExtractorRouter.extractor(for: fileURL)
        let count = (try? extractor?.pageCount(of: fileURL)) ?? 0
        let thumb = try? ThumbnailGenerator.thumbnail(for: id, archivePath: fileURL.path)

        return ScannedFile(
            id: id,
            path: fileURL.path,
            title: parsed.title,
            seriesName: parsed.seriesName,
            issueNumber: parsed.issueNumber,
            pageCount: count ?? 0,
            isSpecial: MetadataParser.looksSpecial(
                issueNumber: parsed.issueNumber, title: parsed.title
            ),
            thumbnailPath: thumb?.path
        )
    }

    // MARK: - Sync

    func sync(context: ModelContext) async {
        guard !isImporting else { return }
        guard let root = WatchedFolder.resolve() else { return }

        let filesOnDisk = Self.comicFiles(under: root)

        let existing = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        let existingPaths = Set(existing.map(\.filePath))
        let diskPaths = Set(filesOnDisk.map(\.path))

        for item in existing where !diskPaths.contains(item.filePath) {
            context.delete(item)
        }

        let newFiles = filesOnDisk.filter { !existingPaths.contains($0.path) }
        guard !newFiles.isEmpty else {
            try? context.save()
            return
        }

        isImporting = true
        processed = 0
        total = newFiles.count
        defer {
            isImporting = false
            currentFileName = ""
        }

        // Leave a core free so the UI stays responsive.
        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        var pendingSaves = 0

        await withTaskGroup(of: ScannedFile.self) { group in
            var nextIndex = 0

            func addTask() {
                guard nextIndex < newFiles.count else { return }
                let fileURL = newFiles[nextIndex]
                let hint = Self.folderHint(for: fileURL, root: root)
                nextIndex += 1
                group.addTask(priority: .utility) {
                    Self.scan(fileURL: fileURL, hint: hint)
                }
            }

            // Prime the pipeline.
            for _ in 0..<min(maxConcurrent, newFiles.count) { addTask() }

            // Insert each result as it lands, then top the group back up.
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

    /// Re-runs metadata parsing on everything already in the library —
    /// EXCEPT items the user has edited by hand (isMetadataLocked).
    func refreshMetadata(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        for item in existing where !item.isMetadataLocked {
            guard FileManager.default.fileExists(atPath: item.filePath) else { continue }
            let parsed = Self.parsedMetadata(forPath: item.filePath)
            item.title = parsed.title
            item.seriesName = parsed.seriesName
            item.issueNumber = parsed.issueNumber
            item.isSpecial = MetadataParser.looksSpecial(
                issueNumber: parsed.issueNumber, title: parsed.title
            )
        }
        try? context.save()
    }
}

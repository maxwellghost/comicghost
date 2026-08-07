import Foundation
import SwiftUI
import SwiftData
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers
import Observation

/// Files handed to the app from outside — Finder double-clicks, "Open With",
/// Spotlight results, and drag-and-drop all funnel through here.
@MainActor
@Observable
final class OpenRequests {
    static let shared = OpenRequests()
    private init() {}

    /// Paths waiting to be opened once the library is on screen.
    var pendingPaths: [String] = []
    /// A library item id to jump to, from a Spotlight result.
    var pendingItemID: UUID?

    func enqueue(_ urls: [URL]) {
        let comics = urls.filter { ComicArchive.Format(fileExtension: $0.pathExtension) != nil }
        guard !comics.isEmpty else { return }
        pendingPaths.append(contentsOf: comics.map(\.path))
    }
}

/// Bridges AppKit's file-opening callbacks into SwiftUI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pages unpacked by a previous run are dead weight, and a crash or force
        // quit leaves them with nothing to collect them. Nothing is open yet, so
        // clearing the lot here is safe.
        ArchiveSupport.purgeWorkingDirectories()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            OpenRequests.shared.enqueue(urls)
        }
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = UUID(uuidString: identifier) else { return false }
        Task { @MainActor in
            OpenRequests.shared.pendingItemID = id
        }
        return true
    }
}

/// Unread count on the Dock icon.
@MainActor
enum DockBadge {
    static func update(newCount: Int) {
        NSApp.dockTile.badgeLabel = newCount > 0 ? String(newCount) : nil
    }
}

/// Publishes the library to Spotlight so system search finds comics.
@MainActor
enum SpotlightIndex {
    static let domain = "com.comicghost.library"
    static let enabledKey = "spotlightEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func index(_ items: [LibraryItem]) async {
        guard isEnabled else { return }

        let payloads = items.map {
            (id: $0.id.uuidString,
             title: $0.title,
             series: $0.seriesKey,
             issue: $0.issueNumber ?? "",
             path: $0.filePath,
             thumbnail: $0.coverThumbnailPath)
        }

        let searchables: [CSSearchableItem] = payloads.map { payload in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = payload.title
            attributes.displayName = payload.title
            attributes.contentDescription = payload.issue.isEmpty
                ? payload.series
                : "\(payload.series) · Issue \(payload.issue)"
            attributes.keywords = [payload.series, "comic", "Comic Ghost"]
            attributes.contentURL = URL(fileURLWithPath: payload.path)
            if let thumbnail = payload.thumbnail {
                attributes.thumbnailURL = URL(fileURLWithPath: thumbnail)
            }

            return CSSearchableItem(
                uniqueIdentifier: payload.id,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }

        // Replace wholesale — simpler than diffing, and the index is small.
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
        try? await CSSearchableIndex.default().indexSearchableItems(searchables)
    }

    static func clear() async {
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}

/// Imports files dropped onto the window.
@MainActor
enum DropImport {
    struct Result {
        var opened: [LibraryItem] = []
        var copied = 0
        var skipped = 0
    }

    /// Files already in a library open directly. Files from elsewhere are
    /// copied into the destination library folder, then registered.
    static func handle(
        paths: [String],
        into destination: ComicLibrary?,
        context: ModelContext
    ) -> Result {
        var result = Result()
        let existing = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        let byPath = Dictionary(existing.map { ($0.filePath, $0) }, uniquingKeysWith: { a, _ in a })

        for path in paths {
            if let item = byPath[path] {
                result.opened.append(item)
                continue
            }

            guard let destination, let root = destination.resolveURL() else {
                result.skipped += 1
                continue
            }

            let source = URL(fileURLWithPath: path)
            var target = root.appendingPathComponent(source.lastPathComponent)

            // Don't clobber an existing file of the same name.
            var suffix = 2
            while FileManager.default.fileExists(atPath: target.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                target = root.appendingPathComponent(
                    "\(stem) (\(suffix)).\(source.pathExtension)"
                )
                suffix += 1
            }

            do {
                try FileManager.default.copyItem(at: source, to: target)
                result.copied += 1
            } catch {
                result.skipped += 1
            }
        }

        return result
    }

    /// Creates a library entry for a file that isn't in any watched folder,
    /// so it can be opened without importing the whole folder it came from.
    static func adopt(path: String, context: ModelContext) -> LibraryItem? {
        let url = URL(fileURLWithPath: path)
        guard ComicArchive.Format(fileExtension: url.pathExtension) != nil,
              FileManager.default.fileExists(atPath: path) else { return nil }

        let parsed = LibraryIngest.parsedMetadata(forPath: path)
        let count = (try? ArchiveExtractorRouter.extractor(for: url).pageCount(of: url)) ?? 0

        let item = LibraryItem(filePath: path, title: parsed.title, pageCount: count)
        item.seriesName = parsed.seriesName
        item.issueNumber = parsed.issueNumber
        item.isNew = false
        context.insert(item)

        if let thumb = try? ThumbnailGenerator.thumbnail(for: item.id, archivePath: path) {
            item.coverThumbnailPath = thumb.path
        }
        try? context.save()
        return item
    }
}

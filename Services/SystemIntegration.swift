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
        // Pages unpacked by a previous run are kept, not dumped: reopening a
        // comic you were part-way through is the common case, and re-unpacking
        // an omnibus costs 10-20 seconds. Trim to the ceiling instead, which
        // also collects whatever a crash or force quit stranded. Nothing is
        // open yet, so nothing here can be evicted out from under a reader.
        Task.detached(priority: .utility) {
            ArchiveSupport.enforceCacheLimit()
        }
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

/// Checks GitHub Releases for a newer version.
///
/// This is the app's only outbound connection, and it stays off until switched
/// on in Settings. Nothing about the library is ever sent — the request is an
/// anonymous GET, and the only thing GitHub learns is an IP and a timestamp.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    @ObservationIgnored static let enabledKey = "checkForUpdates"
    @ObservationIgnored private static let lastCheckKey = "lastUpdateCheckDate"
    @ObservationIgnored private static let latestSeenKey = "lastSeenReleaseVersion"

    private init() {
        restoreBadge()
    }

    /// The throttle is written to disk but the result was not, so after the
    /// first check of the day every later launch found nothing to show and
    /// refused to look again — the badge vanished for a day at a time. The last
    /// version seen is remembered and re-checked against this build at launch.
    func restoreBadge() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey),
              let seen = UserDefaults.standard.string(forKey: Self.latestSeenKey),
              Self.isNewer(seen, than: currentVersion)
        else {
            availableVersion = nil
            return
        }
        availableVersion = seen
    }

    /// Switching the setting off clears the badge without waiting for a launch.
    func forget() {
        availableVersion = nil
    }

    /// Set when a release newer than this build exists. Drives the title bar badge.
    private(set) var availableVersion: String?
    private(set) var isChecking = false

    private let api = URL(string: "https://api.github.com/repos/maxwellghost/comicghost/releases/latest")!

    /// Where the badge sends you. Opening a page needs no entitlement.
    let releasesPage = URL(string: "https://github.com/maxwellghost/comicghost/releases/latest")!

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Launch path. Does nothing unless enabled, and at most once a day.
    func checkIfDue() async {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date.now.timeIntervalSince(last) < 60 * 60 * 24 {
            return
        }
        await check()
    }

    /// Offline is this app's normal state, so a failure here is silent by design.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: api)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return }

        UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        UserDefaults.standard.set(latest, forKey: Self.latestSeenKey)
        availableVersion = Self.isNewer(latest, than: currentVersion) ? latest : nil
    }

    /// Compares version numbers a field at a time. String comparison would put
    /// 1.1.10 before 1.1.9, which only starts mattering after ten patches.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

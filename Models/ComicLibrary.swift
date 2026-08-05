import Foundation
import SwiftData

/// A named library — a watched root folder with its own security-scoped bookmark.
@Model
final class ComicLibrary {
    @Attribute(.unique) var id: UUID
    var name: String
    var path: String
    var bookmark: Data?
    var sortIndex: Int
    var dateAdded: Date

    init(name: String, path: String, bookmark: Data?, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.sortIndex = sortIndex
        self.dateAdded = .now
    }

    /// Resolves the folder, restoring sandbox access. Falls back to the raw path.
    func resolveURL() -> URL? {
        if let bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                if isStale, let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    self.bookmark = refreshed
                }
                return url
            }
        }
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}

/// Helpers for creating libraries from an open panel.
nonisolated enum LibraryFolder {
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Subfolders directly under a library root — the scan-one-folder targets.
    static func topLevelFolders(in root: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

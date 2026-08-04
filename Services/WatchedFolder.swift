import Foundation

/// Persists the watched folder as a security-scoped bookmark so access
/// survives app relaunches (required under App Sandbox; harmless without it).
nonisolated enum WatchedFolder {
    static let pathKey = "watchedFolderPath"
    static let bookmarkKey = "watchedFolderBookmark"

    /// Call when the user picks a folder in the open panel.
    static func save(url: URL) {
        UserDefaults.standard.set(url.path, forKey: pathKey)
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    /// Resolves the saved folder, restoring sandbox access if needed.
    /// Falls back to the raw path when no bookmark exists.
    static func resolve() -> URL? {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // Keep access for the app's lifetime — we read from this
                // folder continuously, so we never stopAccessing.
                _ = url.startAccessingSecurityScopedResource()
                if isStale { save(url: url) }
                return url
            }
        }

        let path = UserDefaults.standard.string(forKey: pathKey) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}

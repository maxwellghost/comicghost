import Foundation

/// Watches the user's comic folder(s) for new/removed CBR/CBZ files.
///
/// Strategy:
///  - On app launch: full scan of watched folders to catch files added while
///    Comic Ghost wasn't running → new LibraryItems get isNew = true.
///  - While running: DispatchSource file-system events for live updates.
final class FolderWatcher {
    typealias ChangeHandler = (_ added: [URL], _ removed: [URL]) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let watchedURL: URL
    private let onChange: ChangeHandler
    private var knownFiles: Set<URL> = []

    init(watching url: URL, onChange: @escaping ChangeHandler) {
        self.watchedURL = url
        self.onChange = onChange
    }

    deinit { stop() }

    /// Full scan — call at launch and before starting live watch.
    func scan() -> [URL] {
        let comics = (try? FileManager.default.contentsOfDirectory(
            at: watchedURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { ComicArchive.Format(fileExtension: $0.pathExtension) != nil } ?? []
        knownFiles = Set(comics)
        return comics
    }

    func start() {
        descriptor = open(watchedURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.diff() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.descriptor, fd >= 0 { close(fd) }
        }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Compares current folder contents against the last known set.
    private func diff() {
        let current = Set(scanCurrent())
        let added = current.subtracting(knownFiles)
        let removed = knownFiles.subtracting(current)
        knownFiles = current
        if !added.isEmpty || !removed.isEmpty {
            onChange(Array(added), Array(removed))
        }
    }

    private func scanCurrent() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: watchedURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { ComicArchive.Format(fileExtension: $0.pathExtension) != nil } ?? []
    }
}

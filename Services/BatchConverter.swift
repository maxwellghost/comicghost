import Foundation
import SwiftData

/// Converts every non-CBZ archive in the library to CBZ, one at a time.
///
/// Worth doing beyond tidiness: CBZ reads in-process through ZIPFoundation,
/// while CBR spawns unrar and CB7/TAR spawn bsdtar on every single open. A
/// normalised library is a faster library.
@MainActor
@Observable
final class BatchConverter {
    static let shared = BatchConverter()

    private(set) var isRunning = false
    private(set) var processed = 0
    private(set) var total = 0
    private(set) var currentName = ""
    private(set) var stage = ""
    private(set) var converted = 0
    private(set) var failures: [Failure] = []
    private(set) var lastSummary: String?

    struct Failure: Identifiable {
        let id = UUID()
        let name: String
        let reason: String
    }

    private var task: Task<Void, Never>?

    private init() {}

    /// Everything that could be converted. CBZ and PDF are left alone — PDFs
    /// would have to be rasterised, which is a lossy rewrite, not a conversion.
    nonisolated func candidates(in items: [LibraryItem]) -> [LibraryItem] {
        items.filter { WritableKind.of(URL(fileURLWithPath: $0.filePath)).isConvertible }
    }

    func cancel() {
        task?.cancel()
    }

    /// Wipes the result of the last run. Failures otherwise sit in the list
    /// forever with no way to acknowledge them.
    func clearResults() {
        guard !isRunning else { return }
        failures = []
        lastSummary = nil
    }

    func run(_ items: [LibraryItem], context: ModelContext) {
        guard !isRunning else { return }

        let queue = candidates(in: items)
        guard !queue.isEmpty else {
            lastSummary = "Nothing to convert — everything is already CBZ or PDF."
            return
        }

        isRunning = true
        processed = 0
        converted = 0
        total = queue.count
        failures = []
        lastSummary = nil

        // Strong self throughout: this is a MainActor singleton that outlives
        // any conversion, and a weak capture can't be read from inside the
        // detached progress closure without tripping Swift 6 concurrency.
        task = Task {
            defer { Task { @MainActor in self.finish() } }

            for item in queue {
                if Task.isCancelled { break }

                let path = item.filePath
                let name = (path as NSString).lastPathComponent

                self.currentName = name
                self.stage = "Starting"

                // Progress hops back to the main actor on its own, so the
                // detached work never touches isolated state directly.
                let report: @Sendable (String) -> Void = { stage in
                    Task { @MainActor in self.stage = stage }
                }

                // Cancellation lands between files: a half-finished repack has
                // nowhere safe to stop, and the original is already in the Trash
                // by the time the new archive is being moved into place.
                let outcome = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
                    do {
                        let result = try MetadataWriter.convertPreservingMetadata(
                            URL(fileURLWithPath: path),
                            progress: report
                        )
                        return .success(result.fileURL)
                    } catch {
                        return .failure(error)
                    }
                }.value

                switch outcome {
                case .success(let newURL):
                    item.filePath = newURL.path
                    self.converted += 1
                case .failure(let error):
                    self.failures.append(
                        Failure(name: name, reason: error.localizedDescription)
                    )
                }
                self.processed += 1
                try? context.save()
            }
        }
    }

    private func finish() {
        let wasCancelled = task?.isCancelled ?? false
        isRunning = false
        currentName = ""
        stage = ""
        task = nil

        var parts: [String] = []
        parts.append("\(converted) converted")
        if !failures.isEmpty { parts.append("\(failures.count) failed") }
        if wasCancelled { parts.append("stopped early") }
        lastSummary = parts.joined(separator: " · ")
    }

    var progressFraction: Double {
        guard total > 0 else { return 0 }
        return Double(processed) / Double(total)
    }
}

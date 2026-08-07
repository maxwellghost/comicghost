import Foundation
import SwiftData
import Observation

/// Reports about the library itself: gaps in a run, duplicate issues,
/// unreadable files, and where the disk space is going.
@MainActor
@Observable
final class LibraryAnalysis {
    static let shared = LibraryAnalysis()
    private init() {}

    // MARK: - Results

    struct Gap: Identifiable {
        let series: String
        let ranges: [ClosedRange<Int>]
        var id: String { series }

        var missingCount: Int {
            ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound + 1) }
        }

        var summary: String {
            ranges.map { range in
                range.lowerBound == range.upperBound
                    ? "#\(range.lowerBound)"
                    : "#\(range.lowerBound)–\(range.upperBound)"
            }.joined(separator: ", ")
        }
    }

    struct DuplicateGroup: Identifiable {
        let series: String
        let issue: String
        let items: [LibraryItem]
        var id: String { "\(series)#\(issue)" }
    }

    struct SeriesSize: Identifiable {
        let series: String
        let bytes: Int64
        let count: Int
        var id: String { series }

        var formatted: String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    struct IntegrityIssue: Identifiable {
        let item: LibraryItem
        let reason: String
        var id: UUID { item.id }
    }

    // MARK: - State

    var isScanning = false
    var scanProgress: Double = 0
    var scanLabel = ""

    var integrityIssues: [IntegrityIssue] = []
    var didRunIntegrity = false

    var sizes: [SeriesSize] = []
    var totalBytes: Int64 = 0
    var didRunSizes = false

    var coverSummary: String?
    /// Bumped when cover files change on disk under paths that did not change,
    /// so grid cells know to re-read them.
    var coverGeneration = 0

    // MARK: - Gaps

    /// Numeric part of an issue number: "170b" -> 170, "Annual 3" -> nil.
    private static func issueValue(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        // Skip labelled entries — annuals and volumes aren't part of the run.
        guard !raw.lowercased().contains("annual"),
              !raw.lowercased().contains("vol") else { return nil }
        let digits = raw.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Gaps in each series' numbered run. Specials are excluded, and a series
    /// needs at least three issues before absences mean anything.
    func gaps(in items: [LibraryItem], maxMissingPerSeries: Int = 400) -> [Gap] {
        let bySeries = Dictionary(grouping: items.filter { !$0.isSpecial }, by: \.seriesKey)

        return bySeries.compactMap { series, members -> Gap? in
            let numbers = Set(members.compactMap { Self.issueValue($0.issueNumber) })
            guard numbers.count >= 3, let low = numbers.min(), let high = numbers.max() else {
                return nil
            }

            let missing = (low...high).filter { !numbers.contains($0) }
            guard !missing.isEmpty, missing.count <= maxMissingPerSeries else { return nil }

            // Collapse consecutive numbers into ranges.
            var ranges: [ClosedRange<Int>] = []
            var start = missing[0]
            var previous = missing[0]
            for value in missing.dropFirst() {
                if value == previous + 1 {
                    previous = value
                } else {
                    ranges.append(start...previous)
                    start = value
                    previous = value
                }
            }
            ranges.append(start...previous)

            return Gap(series: series, ranges: ranges)
        }
        .sorted { $0.missingCount > $1.missingCount }
    }

    // MARK: - Duplicates

    /// Same series and same issue number appearing more than once.
    func duplicates(in items: [LibraryItem]) -> [DuplicateGroup] {
        var buckets: [String: [LibraryItem]] = [:]
        for item in items {
            guard let issue = item.issueNumber?
                .lowercased()
                .trimmingCharacters(in: .whitespaces), !issue.isEmpty else { continue }
            buckets["\(item.seriesKey.lowercased())#\(issue)", default: []].append(item)
        }

        return buckets.values
            .filter { $0.count > 1 }
            .map { group in
                DuplicateGroup(
                    series: group[0].seriesKey,
                    issue: group[0].issueNumber ?? "?",
                    items: group.sorted { $0.filePath < $1.filePath }
                )
            }
            .sorted {
                $0.series.localizedStandardCompare($1.series) == .orderedAscending
            }
    }

    // MARK: - Storage

    func computeSizes(for items: [LibraryItem]) async {
        guard !isScanning else { return }
        isScanning = true
        scanLabel = "Measuring files"
        scanProgress = 0
        defer { isScanning = false; scanLabel = "" }

        let paths = items.map { (series: $0.seriesKey, path: $0.filePath) }
        let measured = await Task.detached(priority: .utility) { () -> [String: (Int64, Int)] in
            var totals: [String: (Int64, Int)] = [:]
            for entry in paths {
                let attrs = try? FileManager.default.attributesOfItem(atPath: entry.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                var current = totals[entry.series] ?? (0, 0)
                current.0 += size
                current.1 += 1
                totals[entry.series] = current
            }
            return totals
        }.value

        sizes = measured
            .map { SeriesSize(series: $0.key, bytes: $0.value.0, count: $0.value.1) }
            .sorted { $0.bytes > $1.bytes }
        totalBytes = sizes.reduce(0) { $0 + $1.bytes }
        didRunSizes = true
        scanProgress = 1
    }

    // MARK: - Integrity

    /// Opens every archive far enough to confirm it has readable pages.
    func checkIntegrity(for items: [LibraryItem]) async {
        guard !isScanning else { return }
        isScanning = true
        scanLabel = "Checking files"
        scanProgress = 0
        integrityIssues = []
        defer { isScanning = false; scanLabel = "" }

        let total = max(items.count, 1)
        var found: [IntegrityIssue] = []

        for (index, item) in items.enumerated() {
            let path = item.filePath
            let result = await Task.detached(priority: .utility) { () -> String? in
                guard FileManager.default.fileExists(atPath: path) else {
                    return "File is missing"
                }
                let url = URL(fileURLWithPath: path)
                do {
                    let extractor = try ArchiveExtractorRouter.extractor(for: url)
                    let count = try extractor.pageCount(of: url)
                    return count > 0 ? nil : "No readable pages"
                } catch {
                    return error.localizedDescription
                }
            }.value

            if let result {
                found.append(IntegrityIssue(item: item, reason: result))
            }
            scanProgress = Double(index + 1) / Double(total)
        }

        integrityIssues = found
        didRunIntegrity = true
    }

    // MARK: - Covers

    /// Regenerates every cover thumbnail whose cached file has gone missing.
    ///
    /// The cache lives in the container's Caches directory, which macOS and any
    /// cleanup utility are free to empty. A rescan will not repair it — scans
    /// skip files already in the library — and the grid only rebuilds a cover
    /// for a cell it happens to draw, so anything never scrolled past stays
    /// blank. This is the deliberate sweep.
    func rebuildMissingCovers(for items: [LibraryItem], context: ModelContext) async {
        guard !isScanning else { return }
        isScanning = true
        scanLabel = "Rebuilding covers"
        scanProgress = 0
        coverSummary = nil
        defer { isScanning = false; scanLabel = "" }

        // Comics sit outside the sandbox, so reading one needs the security
        // scope its library's bookmark carries. Nothing resolves that at
        // launch, so without this every extraction below fails on permissions.
        for library in (try? context.fetch(FetchDescriptor<ComicLibrary>())) ?? [] {
            _ = library.resolveURL()
        }

        let missing = items.filter {
            !FileManager.default.fileExists(atPath: ThumbnailGenerator.cachedPath(for: $0.id).path)
        }
        guard !missing.isEmpty else {
            coverSummary = "Every cover is already cached."
            scanProgress = 1
            return
        }

        let total = missing.count
        var rebuilt = 0
        var failed = 0

        for (index, item) in missing.enumerated() {
            let id = item.id
            let path = item.filePath
            let generated = await Task.detached(priority: .utility) { () -> String? in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return (try? ThumbnailGenerator.thumbnail(for: id, archivePath: path))?.path
            }.value

            if let generated {
                item.coverThumbnailPath = generated
                rebuilt += 1
            } else {
                failed += 1
            }
            scanProgress = Double(index + 1) / Double(total)
        }

        try? context.save()
        // The path a cell watches is unchanged when a thumbnail is rebuilt in
        // place, so nothing would redraw without this.
        coverGeneration += 1

        coverSummary = failed == 0
            ? "Rebuilt \(rebuilt) cover\(rebuilt == 1 ? "" : "s")."
            : "Rebuilt \(rebuilt), skipped \(failed) whose file could not be read."
    }

    // MARK: - Export

    static func csv(for items: [LibraryItem]) -> String {
        func escape(_ value: String) -> String {
            let cleaned = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(cleaned)\""
        }

        var lines = ["Series,Issue,Title,Status,Rating,Pages,Favorite,Special,Date Added,Path"]
        let formatter = ISO8601DateFormatter()

        for item in items.sorted(by: {
            if $0.seriesKey != $1.seriesKey {
                return $0.seriesKey.localizedStandardCompare($1.seriesKey) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }) {
            let status: String
            switch item.status {
            case .new: status = "New"
            case .unread: status = "Unread"
            case .inProgress: status = "In Progress"
            case .completed: status = "Completed"
            }

            lines.append([
                escape(item.seriesKey),
                escape(item.issueNumber ?? ""),
                escape(item.title),
                escape(status),
                String(item.rating),
                String(item.pageCount),
                item.isFavorite ? "yes" : "no",
                item.isSpecial ? "yes" : "no",
                escape(formatter.string(from: item.dateAdded)),
                escape(item.filePath),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func json(for items: [LibraryItem]) throws -> Data {
        struct Row: Encodable {
            let series: String
            let issue: String?
            let title: String
            let status: String
            let rating: Int
            let pages: Int
            let favorite: Bool
            let special: Bool
            let dateAdded: Date
            let path: String
        }

        let rows = items.map { item -> Row in
            let status: String
            switch item.status {
            case .new: status = "New"
            case .unread: status = "Unread"
            case .inProgress: status = "In Progress"
            case .completed: status = "Completed"
            }
            return Row(
                series: item.seriesKey, issue: item.issueNumber, title: item.title,
                status: status, rating: item.rating, pages: item.pageCount,
                favorite: item.isFavorite, special: item.isSpecial,
                dateAdded: item.dateAdded, path: item.filePath
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(rows)
    }
}

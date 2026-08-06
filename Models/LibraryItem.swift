import Foundation
import SwiftData

@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    var filePath: String
    var title: String
    var seriesName: String?
    var issueNumber: String?
    var coverThumbnailPath: String?
    var dateAdded: Date
    var pageCount: Int
    var isNew: Bool
    var isFavorite: Bool = false
    var isMetadataLocked: Bool = false
    var rating: Int = 0
    var readingListOrder: Int?
    var isSpecial: Bool = false

    /// Which named library this belongs to.
    var libraryID: UUID?

    /// Attached label ids, stored as newline-separated UUID strings.
    var labelIDsRaw: String = ""

    /// Which page to use as the cover, when the first one is a scanner credits
    /// page or similar. nil means "whatever the extractor hands back first".
    var coverPageIndex: Int?

    /// Groups everything added by a single scan, so an import can be reviewed
    /// as a batch afterwards.
    var importBatchID: UUID?

    /// Credits from ComicInfo, as "Role<tab>Name, Name" per line.
    /// One field rather than eight columns — these are only ever read as a
    /// group, and it keeps the schema from sprouting a property per role.
    var creditsRaw: String = ""

    /// Newline-separated, straight from ComicInfo.
    var charactersRaw: String = ""
    var teamsRaw: String = ""
    var genresRaw: String = ""

    var storyArcName: String?
    var publisherName: String?

    /// ComicInfo's SeriesGroup — the franchise a series belongs to, e.g.
    /// "X-Men" for Uncanny, Astonishing and Ultimate. Set deliberately in the
    /// metadata editor rather than inferred from where the file happens to sit.
    var seriesGroupName: String?

    /// Chapter markers from ComicInfo's <Pages> Bookmark attributes, encoded as
    /// "startPage<tab>title" per line. Empty for anything that isn't a
    /// collection — a single issue is just one unmarked run of pages.
    var chaptersRaw: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.item)
    var progress: ReadingProgress?

    init(id: UUID = UUID(), filePath: String, title: String, pageCount: Int) {
        self.id = id
        self.filePath = filePath
        self.title = title
        self.pageCount = pageCount
        self.dateAdded = .now
        self.isNew = true
        self.isFavorite = false
        self.isMetadataLocked = false
        self.rating = 0
        self.isSpecial = false
    }

    // MARK: - Computed status

    enum Status {
        case new
        case unread
        case inProgress
        case completed
    }

    var status: Status {
        if progress?.isFinished == true { return .completed }
        if isNew { return .new }
        if let page = progress?.currentPage, page > 0 { return .inProgress }
        return .unread
    }

    // MARK: - Credits and tags

    /// Roles in ComicInfo's own order, so Writer comes before Letterer.
    static let creditRoles = [
        "Writer", "Penciller", "Inker", "Colorist", "Letterer",
        "CoverArtist", "Editor", "Translator"
    ]

    static func roleLabel(_ role: String) -> String {
        role == "CoverArtist" ? "Cover Artist" : role
    }

    /// Splits "A, B & C" into individual names.
    nonisolated static func splitNames(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: " & ", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func encodeList(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func decodeList(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var credits: [(role: String, names: [String])] {
        creditsRaw
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let names = Self.splitNames(String(parts[1]))
                guard !names.isEmpty else { return nil }
                return (String(parts[0]), names)
            }
    }

    /// Everyone credited on this issue, deduped, order preserved.
    var creators: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in credits {
            for name in entry.names where !seen.contains(name.lowercased()) {
                seen.insert(name.lowercased())
                result.append(name)
            }
        }
        return result
    }

    func names(forRole role: String) -> [String] {
        credits.first { $0.role == role }?.names ?? []
    }

    var characters: [String] { Self.decodeList(charactersRaw) }
    var teams: [String] { Self.decodeList(teamsRaw) }
    var genres: [String] { Self.decodeList(genresRaw) }

    var hasCredits: Bool {
        !creditsRaw.isEmpty || !charactersRaw.isEmpty
            || storyArcName != nil || publisherName != nil
    }

    // MARK: - Chapters

    /// One issue inside a collected volume.
    struct Chapter: Identifiable, Hashable, Sendable {
        let startPage: Int      // 0-based
        let title: String
        var id: Int { startPage }
    }

    var chapters: [Chapter] {
        get {
            chaptersRaw
                .split(separator: "\n")
                .compactMap { line in
                    let parts = line.split(separator: "\t", maxSplits: 1)
                    guard let first = parts.first, let page = Int(first) else { return nil }
                    let title = parts.count > 1 ? String(parts[1]) : "Chapter"
                    return Chapter(startPage: page, title: title)
                }
                .sorted { $0.startPage < $1.startPage }
        }
        set {
            chaptersRaw = newValue
                .sorted { $0.startPage < $1.startPage }
                .map { "\($0.startPage)\t\($0.title)" }
                .joined(separator: "\n")
        }
    }

    /// Only true for collections. Everything downstream degrades to normal
    /// single-issue behaviour when this is false.
    var hasChapters: Bool { !chaptersRaw.isEmpty && chapters.count > 1 }

    func chapterIndex(forPage page: Int) -> Int? {
        let marks = chapters
        guard !marks.isEmpty else { return nil }
        var found: Int?
        for (index, chapter) in marks.enumerated() where chapter.startPage <= page {
            found = index
        }
        return found
    }

    func chapter(forPage page: Int) -> Chapter? {
        guard let index = chapterIndex(forPage: page) else { return nil }
        return chapters[index]
    }

    /// Last page of the chapter containing `page`, or the last page of the file.
    func chapterLastPage(forPage page: Int) -> Int {
        let marks = chapters
        guard let index = chapterIndex(forPage: page) else { return max(pageCount - 1, 0) }
        if index + 1 < marks.count { return marks[index + 1].startPage - 1 }
        return max(pageCount - 1, 0)
    }

    func isChapterEnd(page: Int) -> Bool {
        hasChapters && page == chapterLastPage(forPage: page)
    }

    var seriesKey: String { seriesName ?? title }

    var isQueued: Bool { readingListOrder != nil }

    // MARK: - Labels

    var labelIDs: [UUID] {
        get { labelIDsRaw.split(separator: "\n").compactMap { UUID(uuidString: String($0)) } }
        set { labelIDsRaw = newValue.map(\.uuidString).joined(separator: "\n") }
    }

    func hasLabel(_ id: UUID) -> Bool { labelIDs.contains(id) }

    func toggleLabel(_ id: UUID) {
        var ids = labelIDs
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        labelIDs = ids
    }

    func addLabel(_ id: UUID) {
        var ids = labelIDs
        guard !ids.contains(id) else { return }
        ids.append(id)
        labelIDs = ids
    }

    func removeLabel(_ id: UUID) {
        labelIDs = labelIDs.filter { $0 != id }
    }

}

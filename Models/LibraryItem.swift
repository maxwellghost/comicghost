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

    /// Parent grouping when a series sits inside a bigger umbrella folder —
    /// e.g. "Dragon Ball" for "Dragon Ball/Dragon Ball Z/...".
    var masterSeries: String?

    /// Attached label ids, stored as newline-separated UUID strings.
    var labelIDsRaw: String = ""

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

    var seriesKey: String { seriesName ?? title }

    /// Top-level grouping key — the master folder if there is one.
    var masterKey: String { masterSeries ?? seriesKey }

    var hasMaster: Bool { masterSeries != nil }

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

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

    /// 0 = unrated, 1–5 stars.
    var rating: Int = 0

    /// Position in the reading queue; nil means not queued.
    var readingListOrder: Int?

    /// Annual / special / one-shot — grouped separately from the numbered run.
    var isSpecial: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.item)
    var progress: ReadingProgress?

    /// `id` can be supplied so the importer can generate a thumbnail
    /// off the main actor before the model is inserted.
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

    var isQueued: Bool { readingListOrder != nil }
}

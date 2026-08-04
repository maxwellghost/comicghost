import Foundation
import SwiftData

/// One per LibraryItem. Single resume point — no multi-bookmarks by design.
@Model
final class ReadingProgress {
    var item: LibraryItem?
    var currentPage: Int        // 0-based; last page the reader was on
    var lastReadDate: Date
    var isFinished: Bool

    init(item: LibraryItem, currentPage: Int = 0) {
        self.item = item
        self.currentPage = currentPage
        self.lastReadDate = .now
        self.isFinished = false
    }

    /// Call on every page turn. Marks finished when the last page is reached.
    func update(page: Int, of totalPages: Int) {
        currentPage = page
        lastReadDate = .now
        if page >= totalPages - 1 {
            isFinished = true
        }
    }
}

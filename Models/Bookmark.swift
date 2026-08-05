import Foundation
import SwiftData

/// A saved page within an issue. Separate from reading progress, which
/// tracks one resume point — bookmarks are things you want to come back to.
@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    var itemID: UUID          // the LibraryItem this belongs to
    var page: Int             // 0-based
    var label: String
    var dateCreated: Date

    init(itemID: UUID, page: Int, label: String = "") {
        self.id = UUID()
        self.itemID = itemID
        self.page = page
        self.label = label
        self.dateCreated = .now
    }

    var displayLabel: String {
        label.isEmpty ? "Page \(page + 1)" : label
    }
}

import Foundation
import SwiftData

/// A written note, either attached to one issue or standing on its own.
///
/// Both kinds live in the same model so the sidebar can show everything in one
/// place. `itemID` nil means a general note; otherwise it points at the
/// `LibraryItem` it belongs to. The link is by ID rather than a SwiftData
/// relationship so that removing a comic from the library doesn't silently take
/// your notes with it — orphans stay readable and can be re-pointed or deleted
/// deliberately.
@Model
final class ComicNote {
    var id: UUID = UUID()

    /// The issue this note is about, or nil for a general note.
    var itemID: UUID?

    /// Cached at write time so orphaned notes still say what they were about.
    var itemTitle: String?

    /// 1-based page the note refers to, or nil when it's about the issue as a
    /// whole. This is what makes an editor's-note reference findable later.
    var page: Int?

    var title: String = ""
    var body: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    /// Pinned notes sort to the top of the general list.
    var isPinned: Bool = false

    init(itemID: UUID? = nil,
         itemTitle: String? = nil,
         page: Int? = nil,
         title: String = "",
         body: String = "") {
        self.id = UUID()
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.page = page
        self.title = title
        self.body = body
        self.dateCreated = Date()
        self.dateModified = Date()
        self.isPinned = false
    }

    var isGeneral: Bool { itemID == nil }

    /// "Page 13", or nil for issue-level and general notes.
    var pageLabel: String? {
        guard let page else { return nil }
        return "Page \(page)"
    }

    /// What to show in a list when the note has no title of its own.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        let firstLine = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if firstLine.isEmpty { return "Untitled note" }
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }

    /// Second line in list rows.
    var preview: String {
        let flattened = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return "No content" }
        return flattened.count > 140 ? String(flattened.prefix(140)) + "…" : flattened
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func touch() {
        dateModified = Date()
    }
}

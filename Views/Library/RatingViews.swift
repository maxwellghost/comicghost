import SwiftUI
import SwiftData

/// Interactive 1–5 star control. Click the current rating again to clear it.
struct StarRating: View {
    @Binding var rating: Int
    var size: CGFloat = 13
    var interactive: Bool = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? CGTheme.peach : CGTheme.surface1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard interactive else { return }
                        rating = (rating == star) ? 0 : star
                    }
            }
        }
    }
}

/// Read-only star display for averages (supports halves visually).
struct StarDisplay: View {
    let value: Double
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(for: star))
                    .font(.system(size: size))
                    .foregroundStyle(Double(star) - 0.5 <= value ? CGTheme.peach : CGTheme.surface1)
            }
        }
    }

    private func symbol(for star: Int) -> String {
        if value >= Double(star) { return "star.fill" }
        if value >= Double(star) - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Reading queue mutations.
@MainActor
enum ReadingListActions {
    static func add(_ item: LibraryItem, allItems: [LibraryItem]) {
        guard item.readingListOrder == nil else { return }
        let maxOrder = allItems.compactMap(\.readingListOrder).max() ?? -1
        item.readingListOrder = maxOrder + 1
    }

    static func addAll(_ items: [LibraryItem], allItems: [LibraryItem]) {
        var next = (allItems.compactMap(\.readingListOrder).max() ?? -1) + 1
        for item in items where item.readingListOrder == nil {
            item.readingListOrder = next
            next += 1
        }
    }

    static func remove(_ item: LibraryItem) {
        item.readingListOrder = nil
    }

    static func clear(_ items: [LibraryItem]) {
        for item in items {
            item.readingListOrder = nil
        }
    }

    /// Reorders the queue after a drag, renumbering from zero.
    static func reorder(_ queue: [LibraryItem], from source: IndexSet, to destination: Int) {
        var working = queue
        working.move(fromOffsets: source, toOffset: destination)
        for (index, item) in working.enumerated() {
            item.readingListOrder = index
        }
    }

    /// Removes finished issues from the queue.
    static func pruneCompleted(_ items: [LibraryItem]) {
        for item in items where item.status == .completed {
            item.readingListOrder = nil
        }
    }
}

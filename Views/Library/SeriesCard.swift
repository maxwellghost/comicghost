import SwiftUI
import SwiftData

/// A series in the library grid: stacked-cover look, issue count, read progress.
struct SeriesCard: View {
    let series: Series
    var allItems: [LibraryItem] = []
    var onRename: () -> Void = {}
    var onMerge: () -> Void = {}
    /// Opens the next issue you haven't finished.
    var onContinue: (LibraryItem) -> Void = { _ in }
    /// Assigns this whole series to a franchise.
    var onSetGroup: () -> Void = {}
    /// Sets the publisher for every issue in this series.
    var onSetPublisher: () -> Void = {}

    @Environment(\.modelContext) private var context
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @State private var isHovering = false

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topTrailing) {
                    stackedCovers
                    if series.newCount > 0 {
                        Text("\(series.newCount) NEW")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CGTheme.crust)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(CGTheme.peach, in: Capsule())
                            .padding(6)
                    }
                }
            }

            Text(series.name)
                .font(.callout)
                .foregroundStyle(CGTheme.text)
                .lineLimit(2)

            Text(series.subtitle)
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)

            if let average = series.averageRating {
                HStack(spacing: 5) {
                    StarDisplay(value: average)
                    Text(String(format: "%.1f", average))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
            }

            ProgressView(value: Double(series.readCount), total: Double(max(series.items.count, 1)))
                .tint(series.readCount == series.items.count ? CGTheme.green : CGTheme.sky)
        }
        .onHover { isHovering = $0 }
        .softGlow(accent, radius: 7, isActive: isHovering)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .contextMenu {
            if let next = series.nextUnread {
                Button {
                    onContinue(next)
                } label: {
                    Label("Continue: \(next.title)", systemImage: "play.fill")
                }
                Divider()
            }

            Button {
                onSetGroup()
            } label: {
                Label("Set Series Group…", systemImage: "square.stack")
            }

            Button {
                onSetPublisher()
            } label: {
                Label("Set Publisher…", systemImage: "building.2")
            }

            Divider()

            Button {
                for item in series.items {
                    StatusActions.markRead(item, context: context)
                }
                try? context.save()
            } label: {
                Label(countLabel("Mark", series.items.count, suffix: "as Read"),
                      systemImage: "checkmark.circle")
            }

            Button {
                for item in series.items {
                    StatusActions.markUnread(item, context: context)
                }
                try? context.save()
            } label: {
                Label(countLabel("Mark", series.items.count, suffix: "as Unread"),
                      systemImage: "circle")
            }

            Divider()

            let favorited = series.items.filter(\.isFavorite).count
            let unfavorited = series.items.count - favorited

            if unfavorited > 0 {
                Button {
                    for item in series.items { item.isFavorite = true }
                    try? context.save()
                } label: {
                    Label(countLabel("Favorite", unfavorited), systemImage: "heart")
                }
            }

            if favorited > 0 {
                Button {
                    for item in series.items { item.isFavorite = false }
                    try? context.save()
                } label: {
                    Label(countLabel("Unfavorite", favorited), systemImage: "heart.slash")
                }
            }

            Divider()

            Button {
                let unread = series.sortedItems.filter { $0.status != .completed }
                ReadingListActions.addAll(unread, allItems: allItems)
                try? context.save()
            } label: {
                Label(
                    countLabel("Queue", series.sortedItems.filter { $0.status != .completed }.count,
                               suffix: "in Reading List"),
                    systemImage: "text.badge.plus"
                )
            }

            Divider()

            Button {
                onRename()
            } label: {
                Label("Rename Series…", systemImage: "pencil")
            }

            Button {
                onMerge()
            } label: {
                Label("Merge Into…", systemImage: "arrow.triangle.merge")
            }
        }
    }

    /// Menu labels that name exactly how many issues an action touches,
    /// so a one-issue series doesn't read as "All" of the library.
    private func countLabel(_ verb: String, _ count: Int, suffix: String = "") -> String {
        let noun = count == 1 ? "1 Issue" : "All \(count) Issues"
        return suffix.isEmpty ? "\(verb) \(noun)" : "\(verb) \(noun) \(suffix)"
    }

    /// Fanned-out stack hinting at multiple issues behind the cover.
    private var stackedCovers: some View {
        ZStack {
            if series.items.count > 2 {
                coverLayer(offset: 10, opacity: 0.35, scale: 0.94)
            }
            if series.items.count > 1 {
                coverLayer(offset: 5, opacity: 0.6, scale: 0.97)
            }
            coverImage
        }
        .frame(minHeight: 210)
    }

    private func coverLayer(offset: CGFloat, opacity: Double, scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(CGTheme.surface0.opacity(opacity))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(CGTheme.surface1.opacity(opacity), lineWidth: 1)
            }
            .scaleEffect(scale)
            .offset(x: offset, y: -offset / 2)
    }

    private var coverImage: some View {
        Group {
            if let path = series.coverPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(CGTheme.surface0)
                    .overlay {
                        Image(systemName: "books.vertical")
                            .font(.largeTitle)
                            .foregroundStyle(CGTheme.subtext0)
                    }
            }
        }
        .frame(minHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovering ? accent.opacity(0.6) : CGTheme.surface0, lineWidth: 1)
        }
    }
}

/// Grouping wrapper for a series and its issues.
struct Series: Identifiable {
    let name: String
    let items: [LibraryItem]

    var id: String { name }

    /// Cover comes from the earliest issue of the main run (issue 1 / volume 1),
    /// falling back to specials only if there's nothing else.
    var coverPath: String? {
        let ordered = items
            .sorted {
                if $0.isSpecial != $1.isSpecial { return !$0.isSpecial }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        return ordered.first(where: { $0.coverThumbnailPath != nil })?.coverThumbnailPath
    }

    var readCount: Int {
        items.filter { $0.status == .completed }.count
    }

    /// The issue to pick up next: whatever's part-read, otherwise the earliest
    /// unstarted one. Main run before specials, natural order within each.
    var nextUnread: LibraryItem? {
        let ordered = items.sorted {
            if $0.isSpecial != $1.isSpecial { return !$0.isSpecial }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        if let inProgress = ordered.first(where: { $0.status == .inProgress }) { return inProgress }
        return ordered.first { $0.status == .new || $0.status == .unread }
    }

    var newCount: Int {
        items.filter { $0.status == .new }.count
    }

    var inProgressCount: Int {
        items.filter { $0.status == .inProgress }.count
    }

    /// Rolled-up average of rated issues; nil when nothing's rated.
    var averageRating: Double? {
        let rated = items.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
    }

    var mainRun: [LibraryItem] {
        items.filter { !$0.isSpecial }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var specials: [LibraryItem] {
        items.filter(\.isSpecial)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var subtitle: String {
        let issues = items.count == 1 ? "1 issue" : "\(items.count) issues"
        var parts = [issues]
        if !specials.isEmpty {
            parts.append("\(specials.count) special\(specials.count == 1 ? "" : "s")")
        }
        if readCount > 0 {
            parts.append("\(readCount) read")
        }
        return parts.joined(separator: " · ")
    }

    /// Issues in natural order (#2 before #10).
    var sortedItems: [LibraryItem] {
        items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// Applies a series rename/merge to a set of items, fixing titles that
/// embed the old series name and locking so refresh won't undo it.
@MainActor
enum SeriesActions {
    static func move(_ items: [LibraryItem], from oldName: String, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        for item in items {
            if item.title.hasPrefix(oldName) {
                item.title = clean + item.title.dropFirst(oldName.count)
            }
            item.seriesName = clean
            item.isMetadataLocked = true
        }
    }
}

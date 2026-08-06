import SwiftUI
import SwiftData

/// Every bookmark in the library, grouped by comic.
///
/// Bookmarks were write-only before this — you could set them in the reader but
/// nothing ever showed them again. In a 900-page omnibus that made them close
/// to useless.
struct BookmarksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bookmark.dateCreated, order: .reverse) private var bookmarks: [Bookmark]

    let items: [LibraryItem]
    /// Opens a comic at a given page.
    var onOpen: (LibraryItem, Int) -> Void = { _, _ in }

    @State private var search = ""
    @State private var renaming: Bookmark?
    @State private var draftLabel = ""

    private struct Group: Identifiable {
        let item: LibraryItem
        let bookmarks: [Bookmark]
        var id: UUID { item.id }
    }

    /// Bookmarks whose comic is still in the library, newest comic first.
    private var groups: [Group] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var buckets: [UUID: [Bookmark]] = [:]
        for bookmark in bookmarks {
            guard let item = byID[bookmark.itemID] else { continue }
            if !query.isEmpty {
                let matches = item.title.lowercased().contains(query)
                    || bookmark.displayLabel.lowercased().contains(query)
                    || (item.seriesName ?? "").lowercased().contains(query)
                guard matches else { continue }
            }
            buckets[bookmark.itemID, default: []].append(bookmark)
        }

        return buckets
            .compactMap { key, value -> Group? in
                guard let item = byID[key] else { return nil }
                return Group(item: item, bookmarks: value.sorted { $0.page < $1.page })
            }
            .sorted {
                $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
            }
    }

    private var orphanCount: Int {
        let known = Set(items.map(\.id))
        return bookmarks.filter { !known.contains($0.itemID) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if groups.isEmpty {
                GhostEmptyState(
                    title: search.isEmpty ? "No bookmarks yet" : "Nothing matches",
                    message: search.isEmpty
                        ? "Press B while reading to mark a page worth coming back to."
                        : "Try a different search."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $renaming) { bookmark in
            renameSheet(bookmark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bookmarks")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(CGTheme.text)
                Spacer()
                if orphanCount > 0 {
                    Button {
                        clearOrphans()
                    } label: {
                        Label("Clear \(orphanCount) orphaned", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CGTheme.subtext0)
                    .help("Bookmarks whose comic is no longer in the library")
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CGTheme.subtext0)
                TextField("Search bookmarks", text: $search)
                    .textFieldStyle(.plain)
                    .foregroundStyle(CGTheme.text)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CGTheme.subtext0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(CGTheme.surface0.opacity(0.6))
            )
            .frame(maxWidth: 360)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func groupSection(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.item.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(1)
                Text("\(group.bookmarks.count)")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                Spacer()
            }

            ForEach(group.bookmarks) { bookmark in
                BookmarkRow(
                    bookmark: bookmark,
                    chapter: chapterTitle(for: bookmark, in: group.item)
                )
                .onTapGesture { onOpen(group.item, bookmark.page) }
                .contextMenu {
                    Button { onOpen(group.item, bookmark.page) } label: {
                        Label("Open at Page \(bookmark.page + 1)", systemImage: "book")
                    }
                    Button {
                        draftLabel = bookmark.label
                        renaming = bookmark
                    } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        context.delete(bookmark)
                        try? context.save()
                    } label: {
                        Label("Delete Bookmark", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Collections know which issue a page belongs to, so say so.
    private func chapterTitle(for bookmark: Bookmark, in item: LibraryItem) -> String? {
        guard item.hasChapters else { return nil }
        return item.chapter(forPage: bookmark.page)?.title
    }

    private func renameSheet(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Bookmark")
                .font(.headline)
                .foregroundStyle(CGTheme.text)

            TextField("Label", text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(bookmark) }

            Text("Leave blank to show the page number instead.")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)

            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { commitRename(bookmark) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(CGTheme.base)
    }

    private func commitRename(_ bookmark: Bookmark) {
        bookmark.label = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        renaming = nil
    }

    private func clearOrphans() {
        let known = Set(items.map(\.id))
        for bookmark in bookmarks where !known.contains(bookmark.itemID) {
            context.delete(bookmark)
        }
        try? context.save()
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let chapter: String?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundStyle(CGTheme.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.displayLabel)
                    .font(.callout)
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("Page \(bookmark.page + 1)")
                    if let chapter {
                        Text("·")
                        Text(chapter)
                    }
                    Text("·")
                    Text(bookmark.dateCreated.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption2)
                .foregroundStyle(CGTheme.subtext0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CGTheme.surface0.opacity(isHovering ? 0.65 : 0.3))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

import SwiftUI
import SwiftData

/// A triage pass over the comics added by the most recent scan.
///
/// Before this, an import dropped a pile of items into Recently Added with New
/// badges that only cleared by reading each one. This gives the batch a place to
/// live and a way to clear it in one action.
struct ImportReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ComicLabel.sortIndex) private var labels: [ComicLabel]

    let items: [LibraryItem]
    var onOpen: (LibraryItem) -> Void = { _ in }

    @AppStorage(LibraryIngest.lastImportBatchKey) private var lastBatchRaw: String = ""

    @State private var selection: Set<UUID> = []
    @State private var sort: Sort = .fileOrder

    enum Sort: String, CaseIterable, Identifiable {
        case fileOrder = "Order added"
        case series = "Series"
        case title = "Title"
        var id: String { rawValue }
    }

    private var batchID: UUID? { UUID(uuidString: lastBatchRaw) }

    private var batchItems: [LibraryItem] {
        guard let batchID else { return [] }
        let matched = items.filter { $0.importBatchID == batchID }
        switch sort {
        case .fileOrder:
            return matched.sorted { $0.dateAdded < $1.dateAdded }
        case .series:
            return matched.sorted {
                let left = $0.seriesKey.localizedStandardCompare($1.seriesKey)
                if left != .orderedSame { return left == .orderedAscending }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .title:
            return matched.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    private var selectedItems: [LibraryItem] {
        batchItems.filter { selection.contains($0.id) }
    }

    /// Actions apply to the selection, or to everything when nothing's picked.
    private var targets: [LibraryItem] {
        selectedItems.isEmpty ? batchItems : selectedItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if batchItems.isEmpty {
                GhostEmptyState(
                    title: "Nothing to review",
                    message: "New comics land here after a scan, so you can label and triage them in one pass."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(batchItems) { item in
                            ImportRow(
                                item: item,
                                isSelected: selection.contains(item.id),
                                labels: labels
                            )
                            .onTapGesture { toggle(item) }
                            .contextMenu {
                                Button { onOpen(item) } label: {
                                    Label("Open", systemImage: "book")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Import")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(CGTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
                Spacer()
                Picker("", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if !batchItems.isEmpty {
                actionBar
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var subtitle: String {
        let count = batchItems.count
        guard count > 0 else { return "No batch on record" }
        let selected = selection.count
        if selected > 0 { return "\(selected) of \(count) selected" }
        return "\(count) comic\(count == 1 ? "" : "s") added · actions apply to all unless you select some"
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                selection = selection.count == batchItems.count
                    ? []
                    : Set(batchItems.map(\.id))
            } label: {
                Text(selection.count == batchItems.count ? "Deselect All" : "Select All")
            }

            Divider().frame(height: 16)

            Button {
                apply { $0.isNew = false }
            } label: {
                Label("Clear New", systemImage: "checkmark.circle")
            }

            Button {
                apply { StatusActions.markRead($0, context: context) }
            } label: {
                Label("Mark Read", systemImage: "book.closed")
            }

            Button {
                apply { $0.isFavorite = true }
            } label: {
                Label("Favorite", systemImage: "heart")
            }

            if !labels.isEmpty {
                Menu {
                    ForEach(labels) { label in
                        Button(label.name) {
                            apply { $0.addLabel(label.id) }
                        }
                    }
                } label: {
                    Label("Add Label", systemImage: "tag")
                }
                .frame(width: 130)
            }

            Spacer()

            Button(role: .destructive) {
                lastBatchRaw = ""
                selection = []
            } label: {
                Label("Dismiss Batch", systemImage: "xmark")
            }
            .help("Clears this review list. The comics stay in your library.")
        }
        .font(.callout)
        .buttonStyle(.plain)
        .foregroundStyle(CGTheme.subtext1)
    }

    private func toggle(_ item: LibraryItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private func apply(_ change: (LibraryItem) -> Void) {
        for item in targets { change(item) }
        try? context.save()
    }
}

private struct ImportRow: View {
    let item: LibraryItem
    let isSelected: Bool
    let labels: [ComicLabel]

    @State private var isHovering = false

    private var attached: [ComicLabel] {
        labels.filter { item.hasLabel($0.id) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? CGTheme.accent : CGTheme.subtext0.opacity(0.6))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.seriesKey)
                        .lineLimit(1)
                    if item.pageCount > 0 {
                        Text("·")
                        Text("\(item.pageCount) pages")
                    }
                    if item.hasChapters {
                        Text("·")
                        Text("\(item.chapters.count) issues")
                            .foregroundStyle(CGTheme.accent)
                    }
                }
                .font(.caption2)
                .foregroundStyle(CGTheme.subtext0)
            }

            Spacer(minLength: 0)

            ForEach(attached) { label in
                LabelChip(label: label)
            }

            if item.isNew {
                Text("NEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CGTheme.crust)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CGTheme.peach, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CGTheme.surface0.opacity(isSelected ? 0.7 : (isHovering ? 0.5 : 0.25)))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

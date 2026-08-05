import SwiftUI
import SwiftData

/// One cover in the grid. Badges live in a single bottom strip.
struct LibraryItemCell: View {
    let item: LibraryItem
    var allItems: [LibraryItem] = []
    var coverHeight: CGFloat = 200

    @Environment(\.modelContext) private var context
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @Query(sort: \ComicLabel.sortIndex) private var allLabels: [ComicLabel]

    @State private var isHovering = false
    @State private var showEditSheet = false
    @State private var showRemoveConfirm = false
    @State private var cover: NSImage?
    @State private var didAttemptLoad = false
    @State private var showLabelManager = false

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    private var attachedLabels: [ComicLabel] {
        let ids = Set(item.labelIDs)
        return allLabels.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverArea

            Text(item.title)
                .font(.callout)
                .foregroundStyle(CGTheme.text)
                .lineLimit(2)

            if !attachedLabels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(attachedLabels.prefix(3)) { label in
                        LabelChip(label: label)
                    }
                    if attachedLabels.count > 3 {
                        Text("+\(attachedLabels.count - 3)")
                            .font(.system(size: 9))
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
            }

            if item.rating > 0 || isHovering {
                StarRating(rating: Binding(
                    get: { item.rating },
                    set: { item.rating = $0 }
                ))
            }

            if item.status == .inProgress, let progress = item.progress {
                ProgressView(value: Double(progress.currentPage + 1), total: Double(max(item.pageCount, 1)))
                    .tint(CGTheme.sky)
            }
        }
        .onHover { isHovering = $0 }
        .softGlow(accent, radius: 7, isActive: isHovering)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .contextMenu { ItemContextMenu(item: item, allItems: allItems,
                                       showEditSheet: $showEditSheet,
                                       showRemoveConfirm: $showRemoveConfirm,
                                       showLabelManager: $showLabelManager) }
        .sheet(isPresented: $showEditSheet) { EditInfoSheet(item: item) }
        .sheet(isPresented: $showLabelManager) { LabelManager() }
        .confirmationDialog(
            "Remove “\(item.title)”?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove from Library") { removeFromLibraryOnly(item, context: context) }
            Button("Move File to Trash", role: .destructive) { removeFromLibrary(item, context: context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing from the library leaves the file where it is and stops future scans picking it up. Moving to the Trash deletes it from disk.")
        }
        .task(id: item.coverThumbnailPath) { await loadCover() }
    }

    private var coverArea: some View {
        Group {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if didAttemptLoad {
                RoundedRectangle(cornerRadius: 8)
                    .fill(CGTheme.surface0)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(CGTheme.subtext0)
                    }
            } else {
                SkeletonBox(cornerRadius: 8)
            }
        }
        .frame(height: coverHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovering ? accent.opacity(0.6) : CGTheme.surface0, lineWidth: 1)
        }
        .overlay(alignment: .bottom) { badgeStrip }
    }

    /// Single consolidated strip along the bottom of the cover.
    @ViewBuilder
    private var badgeStrip: some View {
        let showsStatus = item.status == .new || item.status == .unread
        if showsStatus || item.isQueued || item.isFavorite || item.isSpecial {
            HStack(spacing: 6) {
                if item.status == .new {
                    pill("NEW", color: CGTheme.peach)
                } else if item.status == .unread {
                    pill("UNREAD", color: CGTheme.lavender)
                }
                if item.isSpecial {
                    icon("star.square.fill", color: CGTheme.peach)
                }
                Spacer(minLength: 0)
                if item.isQueued {
                    Button {
                        ReadingListActions.remove(item)
                        try? context.save()
                    } label: {
                        icon("text.badge.plus", color: CGTheme.sapphire)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from reading list")
                }
                if item.isFavorite {
                    Button {
                        item.isFavorite = false
                        try? context.save()
                    } label: {
                        icon("heart.fill", color: CGTheme.pink)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from favorites")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                LinearGradient(
                    colors: [.clear, CGTheme.crust.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    private func pill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(CGTheme.crust)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private func icon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(color)
    }

    private func loadCover() async {
        guard let path = item.coverThumbnailPath else {
            didAttemptLoad = true
            return
        }
        let image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOfFile: path)
        }.value
        cover = image
        didAttemptLoad = true
    }
}

/// Compact row for list view.
struct LibraryItemRow: View {
    let item: LibraryItem
    var allItems: [LibraryItem] = []

    @Environment(\.modelContext) private var context
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @Query(sort: \ComicLabel.sortIndex) private var allLabels: [ComicLabel]
    @State private var isHovering = false
    @State private var showEditSheet = false
    @State private var showRemoveConfirm = false
    @State private var showLabelManager = false

    private var rowLabels: [ComicLabel] {
        let ids = Set(item.labelIDs)
        return allLabels.filter { ids.contains($0.id) }
    }

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let path = item.coverThumbnailPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(CGTheme.surface0)
                }
            }
            .frame(width: 32, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(item.title)
                .font(.callout)
                .foregroundStyle(CGTheme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(rowLabels.prefix(4)) { label in
                    LabelChip(label: label, compact: true)
                }
            }

            if item.isSpecial {
                Image(systemName: "star.square.fill")
                    .font(.caption)
                    .foregroundStyle(CGTheme.peach)
            }
            if item.isQueued {
                Image(systemName: "text.badge.plus")
                    .font(.caption)
                    .foregroundStyle(CGTheme.sapphire)
            }
            if item.isFavorite {
                Button {
                    item.isFavorite = false
                    try? context.save()
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(CGTheme.pink)
                }
                .buttonStyle(.plain)
                .help("Remove from favorites")
            }

            StarRating(rating: Binding(
                get: { item.rating },
                set: { item.rating = $0 }
            ), size: 11)
            .frame(width: 74, alignment: .leading)

            Text("\(item.pageCount)p")
                .font(.caption.monospacedDigit())
                .foregroundStyle(CGTheme.subtext0)
                .frame(width: 44, alignment: .trailing)

            statusLabel
                .frame(width: 92, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? CGTheme.surface0.opacity(0.55) : .clear)
        }
        .onHover { isHovering = $0 }
        .contextMenu { ItemContextMenu(item: item, allItems: allItems,
                                       showEditSheet: $showEditSheet,
                                       showRemoveConfirm: $showRemoveConfirm,
                                       showLabelManager: $showLabelManager) }
        .sheet(isPresented: $showEditSheet) { EditInfoSheet(item: item) }
        .sheet(isPresented: $showLabelManager) { LabelManager() }
        .confirmationDialog(
            "Remove “\(item.title)”?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove from Library") { removeFromLibraryOnly(item, context: context) }
            Button("Move File to Trash", role: .destructive) { removeFromLibrary(item, context: context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing from the library leaves the file where it is and stops future scans picking it up. Moving to the Trash deletes it from disk.")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .new:
            Text("New").font(.caption).foregroundStyle(CGTheme.peach)
        case .unread:
            Text("Unread").font(.caption).foregroundStyle(CGTheme.subtext0)
        case .inProgress:
            if let progress = item.progress {
                Text("p\(progress.currentPage + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CGTheme.sky)
            }
        case .completed:
            Text("Read").font(.caption).foregroundStyle(CGTheme.green)
        }
    }
}

/// Shared context menu for grid cells and list rows.
struct ItemContextMenu: View {
    let item: LibraryItem
    let allItems: [LibraryItem]
    @Binding var showEditSheet: Bool
    @Binding var showRemoveConfirm: Bool
    @Binding var showLabelManager: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \ComicLabel.sortIndex) private var labels: [ComicLabel]

    var body: some View {
        Button {
            item.isFavorite.toggle()
            try? context.save()
        } label: {
            Label(item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: item.isFavorite ? "heart.slash" : "heart")
        }

        if item.isQueued {
            Button {
                ReadingListActions.remove(item)
                try? context.save()
            } label: {
                Label("Remove from Reading List", systemImage: "text.badge.minus")
            }
        } else {
            Button {
                ReadingListActions.add(item, allItems: allItems)
                try? context.save()
            } label: {
                Label("Add to Reading List", systemImage: "text.badge.plus")
            }
        }

        LabelPickerMenu(
            items: [item],
            labels: labels,
            onManage: { showLabelManager = true },
            onChange: { try? context.save() }
        )

        Divider()

        Menu("Rating") {
            ForEach((1...5).reversed(), id: \.self) { stars in
                Button(String(repeating: "★", count: stars)) {
                    item.rating = stars
                    try? context.save()
                }
            }
            if item.rating > 0 {
                Divider()
                Button("Clear Rating") {
                    item.rating = 0
                    try? context.save()
                }
            }
        }

        Divider()

        if item.status != .completed {
            Button {
                StatusActions.markRead(item, context: context)
                try? context.save()
            } label: {
                Label("Mark as Read", systemImage: "checkmark.circle")
            }
        }

        if item.progress != nil || item.isNew {
            Button {
                StatusActions.markUnread(item, context: context)
                try? context.save()
            } label: {
                Label("Mark as Unread", systemImage: "circle")
            }
        }

        Divider()

        Button {
            item.isSpecial.toggle()
            item.isMetadataLocked = true
            try? context.save()
        } label: {
            Label(item.isSpecial ? "Move to Main Run" : "Mark as Special",
                  systemImage: item.isSpecial ? "arrow.up.doc" : "star.square")
        }

        Button {
            showEditSheet = true
        } label: {
            Label("Edit Info…", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            showRemoveConfirm = true
        } label: {
            Label("Remove…", systemImage: "trash")
        }
    }
}

/// Drops the entry and remembers the path so scans skip it. File untouched.
@MainActor
func removeFromLibraryOnly(_ item: LibraryItem, context: ModelContext) {
    let ignored = IgnoredFile(
        path: item.filePath, title: item.title, seriesName: item.seriesName
    )
    context.insert(ignored)
    if let progress = item.progress { context.delete(progress) }
    context.delete(item)
    try? context.save()
}

@MainActor
func removeFromLibrary(_ item: LibraryItem, context: ModelContext) {
    let url = URL(fileURLWithPath: item.filePath)
    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    if let progress = item.progress { context.delete(progress) }
    context.delete(item)
    try? context.save()
}

/// Shared status mutations.
@MainActor
enum StatusActions {
    static func markRead(_ item: LibraryItem, context: ModelContext) {
        if item.progress == nil {
            let progress = ReadingProgress(item: item)
            context.insert(progress)
            item.progress = progress
        }
        item.progress?.currentPage = max(item.pageCount - 1, 0)
        item.progress?.lastReadDate = .now
        item.progress?.isFinished = true
        item.isNew = false
    }

    static func markUnread(_ item: LibraryItem, context: ModelContext) {
        if let progress = item.progress {
            context.delete(progress)
            item.progress = nil
        }
        item.isNew = false
    }
}

/// Manual metadata editor.
struct EditInfoSheet: View {
    let item: LibraryItem
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue

    @State private var title = ""
    @State private var series = ""
    @State private var issue = ""
    @State private var special = false
    @State private var rating = 0

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Info")
                .font(.headline)
                .foregroundStyle(CGTheme.text)

            Form {
                TextField("Title", text: $title)
                TextField("Series", text: $series)
                TextField("Issue #", text: $issue)
                Toggle("Special / annual / one-shot", isOn: $special)
                HStack {
                    Text("Rating")
                    Spacer()
                    StarRating(rating: $rating, size: 15)
                }
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)

            Text("Filename: \((item.filePath as NSString).lastPathComponent)")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Saved edits are protected from “Refresh titles & series.”")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)

            HStack {
                Button("Re-parse from Filename") {
                    let parsed = LibraryIngest.parsedMetadata(forPath: item.filePath)
                    title = parsed.title
                    series = parsed.seriesName ?? ""
                    issue = parsed.issueNumber ?? ""
                    special = MetadataParser.looksSpecial(issueNumber: parsed.issueNumber, title: parsed.title)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(CGTheme.base)
        .onAppear {
            title = item.title
            series = item.seriesName ?? ""
            issue = item.issueNumber ?? ""
            special = item.isSpecial
            rating = item.rating
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanSeries = series.trimmingCharacters(in: .whitespaces)
        let cleanIssue = issue.trimmingCharacters(in: .whitespaces)

        item.title = cleanTitle
        item.seriesName = cleanSeries.isEmpty ? nil : cleanSeries
        item.issueNumber = cleanIssue.isEmpty ? nil : cleanIssue
        item.isSpecial = special
        item.rating = rating
        item.isMetadataLocked = true
        dismiss()
    }
}

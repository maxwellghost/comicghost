import SwiftUI
import SwiftData

/// The Notes route in the sidebar.
///
/// Shows general notes and issue notes side by side. Issue notes stay visible
/// here even when you're not looking at the comic they belong to, which is the
/// point — cross-references are only useful if you can find them again.
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ComicNote.dateModified, order: .reverse) private var notes: [ComicNote]

    let items: [LibraryItem]
    /// Opens a comic from an issue note.
    var onOpen: (LibraryItem) -> Void = { _ in }

    @State private var selected: ComicNote?
    @State private var search = ""
    @State private var scope: Scope = .all

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case general = "General"
        case issues = "Issues"
        var id: String { rawValue }
    }

    private var filtered: [ComicNote] {
        var result = notes

        switch scope {
        case .all: break
        case .general: result = result.filter(\.isGeneral)
        case .issues: result = result.filter { !$0.isGeneral }
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query)
                    || $0.body.lowercased().contains(query)
                    || ($0.itemTitle ?? "").lowercased().contains(query)
            }
        }

        // Pinned first, then most recently edited. Notes on the same issue stay
        // in page order so a run of editor's notes reads top to bottom.
        return result.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if let a = lhs.itemID, let b = rhs.itemID, a == b {
                return (lhs.page ?? Int.max) < (rhs.page ?? Int.max)
            }
            return lhs.dateModified > rhs.dateModified
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { note in
                            NoteRow(note: note, onOpenItem: openItem(for:))
                                .onTapGesture { selected = note }
                                .contextMenu { rowMenu(note) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selected) { note in
            NoteEditorSheet(note: note)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(CGTheme.text)
                Spacer()
                Button {
                    let note = ComicNote()
                    context.insert(note)
                    try? context.save()
                    selected = note
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(CGTheme.accent)
            }

            HStack(spacing: 12) {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CGTheme.subtext0)
                    TextField("Search notes", text: $search)
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
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            GhostEmptyState(
                title: search.isEmpty ? "No notes yet" : "Nothing matches",
                message: search.isEmpty
                    ? "Keep track of cross-references, reading order, or anything else worth remembering."
                    : "Try a different search."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowMenu(_ note: ComicNote) -> some View {
        Button {
            note.isPinned.toggle()
            note.touch()
            try? context.save()
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }

        if let item = openItem(for: note) {
            Button {
                onOpen(item)
            } label: {
                Label("Open \(item.title)", systemImage: "book")
            }
        }

        Divider()

        Button(role: .destructive) {
            context.delete(note)
            try? context.save()
        } label: {
            Label("Delete Note", systemImage: "trash")
        }
    }

    private func openItem(for note: ComicNote) -> LibraryItem? {
        guard let itemID = note.itemID else { return nil }
        return items.first { $0.id == itemID }
    }
}

// MARK: - Row

private struct NoteRow: View {
    let note: ComicNote
    let onOpenItem: (ComicNote) -> LibraryItem?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.isGeneral ? "note.text" : "book.closed")
                .font(.body)
                .foregroundStyle(CGTheme.subtext0)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.displayTitle)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(CGTheme.text)
                        .lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(CGTheme.accent)
                    }
                }

                Text(note.preview)
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let itemTitle = note.itemTitle, !note.isGeneral {
                        Text(itemTitle)
                            .font(.caption2)
                            .foregroundStyle(CGTheme.subtext1)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(CGTheme.subtext0.opacity(0.6))
                    }
                    if let pageLabel = note.pageLabel {
                        Text(pageLabel)
                            .font(.caption2)
                            .foregroundStyle(CGTheme.accent)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(CGTheme.subtext0.opacity(0.6))
                    }
                    Text(note.dateModified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0.opacity(0.8))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(CGTheme.surface0.opacity(isHovering ? 0.65 : 0.35))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Editor

/// Edits one note. Used from the Notes route and from a comic's context menu.
struct NoteEditorSheet: View {
    @Bindable var note: ComicNote

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.isGeneral ? "Note" : "Issue Note")
                        .font(.headline)
                        .foregroundStyle(CGTheme.text)
                    if let itemTitle = note.itemTitle, !note.isGeneral {
                        HStack(spacing: 6) {
                            Text(itemTitle)
                                .font(.caption)
                                .foregroundStyle(CGTheme.subtext0)
                                .lineLimit(1)
                            if let pageLabel = note.pageLabel {
                                Text(pageLabel)
                                    .font(.caption)
                                    .foregroundStyle(CGTheme.accent)
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    note.isPinned.toggle()
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(note.isPinned ? CGTheme.accent : CGTheme.subtext0)
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? "Unpin" : "Pin to top")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().overlay(CGTheme.surface0)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(CGTheme.text)

                TextEditor(text: $note.body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CGTheme.surface0.opacity(0.45))
                    )
            }
            .padding(20)

            Divider().overlay(CGTheme.surface0)

            HStack {
                Button(role: .destructive) {
                    context.delete(note)
                    try? context.save()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(CGTheme.red)

                Spacer()

                Button("Done") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 480)
        .background(CGTheme.base)
        .onDisappear { save(dismissAfter: false) }
    }

    /// An empty note is thrown away rather than left cluttering the list.
    private func save(dismissAfter: Bool = true) {
        if note.isEmpty {
            context.delete(note)
        } else {
            note.touch()
        }
        try? context.save()
        if dismissAfter { dismiss() }
    }
}

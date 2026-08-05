import SwiftUI
import SwiftData

/// Small colored pill shown on covers and in list rows.
struct LabelChip: View {
    let label: ComicLabel
    var compact: Bool = false

    var body: some View {
        if compact {
            Circle()
                .fill(label.color)
                .frame(width: 7, height: 7)
        } else {
            Text(label.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CGTheme.crust)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(label.color, in: Capsule())
                .lineLimit(1)
        }
    }
}

/// Context-menu section for attaching labels.
struct LabelPickerMenu: View {
    let items: [LibraryItem]
    let labels: [ComicLabel]
    var onManage: () -> Void
    var onChange: () -> Void

    private var ordered: [ComicLabel] {
        labels.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// "On" only when every selected item carries it.
    private func isApplied(_ label: ComicLabel) -> Bool {
        !items.isEmpty && items.allSatisfy { $0.hasLabel(label.id) }
    }

    var body: some View {
        Menu("Labels") {
            if ordered.isEmpty {
                Text("No labels yet")
            }
            ForEach(ordered) { label in
                Button {
                    let applied = isApplied(label)
                    for item in items {
                        if applied { item.removeLabel(label.id) } else { item.addLabel(label.id) }
                    }
                    onChange()
                } label: {
                    if isApplied(label) {
                        Label(label.name, systemImage: "checkmark")
                    } else {
                        Text(label.name)
                    }
                }
            }
            Divider()
            Button("Manage Labels…") { onManage() }
        }
    }
}

/// Create, rename, recolor, favorite, and delete labels.
struct LabelManager: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ComicLabel.sortIndex) private var labels: [ComicLabel]
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue

    @State private var newName = ""
    @State private var newColor: LabelColor = .mauve

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Labels").font(.headline).foregroundStyle(CGTheme.text)

            HStack(spacing: 8) {
                TextField("New label", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }

                Menu {
                    ForEach(LabelColor.allCases) { color in
                        Button(color.label) { newColor = color }
                    }
                } label: {
                    Circle().fill(newColor.color).frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 44)

                Button("Add") { add() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if labels.isEmpty {
                Text("No labels yet. Add one above, then attach it from any comic's right-click menu.")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(labels) { label in row(label) }
                    }
                }
                .frame(height: 260)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(CGTheme.base)
    }

    private func row(_ label: ComicLabel) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(LabelColor.allCases) { color in
                    Button(color.label) {
                        label.colorName = color.rawValue
                        try? context.save()
                    }
                }
            } label: {
                Circle().fill(label.color).frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)

            TextField("Name", text: Binding(
                get: { label.name },
                set: { label.name = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .onSubmit { try? context.save() }

            Button {
                label.isFavorite.toggle()
                try? context.save()
            } label: {
                Image(systemName: label.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(label.isFavorite ? CGTheme.peach : CGTheme.subtext0)
            }
            .buttonStyle(.plain)
            .help("Favorite labels sort first and get their own sidebar row")

            Button(role: .destructive) { remove(label) } label: {
                Image(systemName: "trash").foregroundStyle(CGTheme.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6).fill(CGTheme.surface0.opacity(0.4))
        }
    }

    private func add() {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        context.insert(ComicLabel(name: clean, colorName: newColor.rawValue, sortIndex: labels.count))
        try? context.save()
        newName = ""
    }

    /// Deleting a label detaches it from every item first.
    private func remove(_ label: ComicLabel) {
        let id = label.id
        let items = ((try? context.fetch(FetchDescriptor<LibraryItem>())) ?? [])
            .filter { $0.hasLabel(id) }
        for item in items { item.removeLabel(id) }
        context.delete(label)
        try? context.save()
    }
}

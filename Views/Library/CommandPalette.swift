import SwiftUI

/// Cmd-K overlay: type a few letters, hit Return, go there.
///
/// This is also the honest answer to keyboard grid navigation. Moving a
/// selection box around a 1,400-item grid was never going to beat typing three
/// letters, and it doesn't fight the responder chain the way `.focusable()`
/// does inside a NavigationSplitView.
struct CommandPalette: View {
    struct Entry: Identifiable {
        enum Kind {
            case series(String)
            case issue(LibraryItem)
            case action
        }

        let id = UUID()
        let kind: Kind
        let title: String
        let subtitle: String?
        let symbol: String
        let perform: () -> Void
    }

    let entries: [Entry]
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            // Actions first when there's nothing typed — they're the short list.
            return Array(entries.filter { if case .action = $0.kind { return true } else { return false } }.prefix(12))
        }
        return Array(
            entries
                .compactMap { entry -> (Entry, Int)? in
                    guard let score = score(entry, query: trimmed) else { return nil }
                    return (entry, score)
                }
                .sorted { $0.1 < $1.1 }
                .prefix(30)
                .map(\.0)
        )
    }

    /// Lower is better: prefix beats word-start beats plain contains.
    private func score(_ entry: Entry, query: String) -> Int? {
        let title = entry.title.lowercased()
        if title.hasPrefix(query) { return 0 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        if title.contains(query) { return 2 }
        if let subtitle = entry.subtitle?.lowercased(), subtitle.contains(query) { return 3 }
        return nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.black.opacity(0.35))
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                field
                Divider().overlay(CGTheme.surface1)
                results
            }
            .frame(width: 560)
            .background(CGTheme.mantle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CGTheme.surface1, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .padding(.top, 120)
        }
        .onAppear {
            query = ""
            highlighted = 0
            fieldFocused = true
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .background {
            // Arrow keys and Return, without touching the responder chain.
            Group {
                Button("") { move(1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { move(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { run() }.keyboardShortcut(.return, modifiers: [])
                Button("") { isPresented = false }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CGTheme.subtext0)
            TextField("Jump to a series, issue, or action…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(CGTheme.text)
                .focused($fieldFocused)
                .onSubmit { run() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if matches.isEmpty {
                        Text(query.isEmpty ? "Start typing" : "No matches")
                            .font(.callout)
                            .foregroundStyle(CGTheme.subtext0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                        row(entry, isHighlighted: index == highlighted)
                            .id(index)
                            .onTapGesture {
                                highlighted = index
                                run()
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
            .onChange(of: highlighted) { _, new in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .frame(width: 18)
                .foregroundStyle(isHighlighted ? CGTheme.accent : CGTheme.subtext0)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.callout)
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHighlighted ? CGTheme.surface0.opacity(0.9) : .clear)
        )
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), matches.count - 1)
    }

    private func run() {
        guard matches.indices.contains(highlighted) else { return }
        let entry = matches[highlighted]
        isPresented = false
        entry.perform()
    }
}

import SwiftUI

/// Browse the library by who made it and what's in it.
///
/// All of this comes out of ComicInfo, which the scanner already reads. Before
/// this it was parsed and thrown away — the only place any of it surfaced was
/// the metadata editor.
struct CreditsIndexView: View {
    let items: [LibraryItem]
    var onSelect: (Facet, String) -> Void = { _, _ in }

    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @State private var facet: Facet = .creator
    @State private var search = ""
    @State private var roleFilter: String = "All roles"

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    enum Facet: String, CaseIterable, Identifiable {
        case creator = "Creators"
        case character = "Characters"
        case storyArc = "Story Arcs"
        case publisher = "Publishers"
        case genre = "Genres"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .creator: return "person.2"
            case .character: return "figure.stand"
            case .storyArc: return "books.vertical"
            case .publisher: return "building.2"
            case .genre: return "theatermasks"
            }
        }
    }

    typealias Entry = CreditsIndexEntry

    /// Roles present in the library, for the Creators filter.
    private var availableRoles: [String] {
        var seen = Set<String>()
        for item in items {
            for credit in item.credits { seen.insert(credit.role) }
        }
        return ["All roles"] + LibraryItem.creditRoles.filter { seen.contains($0) }
    }

    private var entries: [Entry] {
        var counts: [String: Int] = [:]
        var roles: [String: Set<String>] = [:]

        for item in items {
            switch facet {
            case .creator:
                for credit in item.credits {
                    guard roleFilter == "All roles" || credit.role == roleFilter else { continue }
                    for name in credit.names {
                        counts[name, default: 0] += 1
                        roles[name, default: []].insert(credit.role)
                    }
                }
            case .character:
                for name in item.characters + item.teams { counts[name, default: 0] += 1 }
            case .storyArc:
                if let arc = item.storyArcName { counts[arc, default: 0] += 1 }
            case .publisher:
                if let publisher = item.publisherName { counts[publisher, default: 0] += 1 }
            case .genre:
                for name in item.genres { counts[name, default: 0] += 1 }
            }
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return counts
            .filter { query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) }
            .map { name, count in
                let detail: String? = facet == .creator
                    ? roles[name]?
                        .sorted { a, b in
                            let ia = LibraryItem.creditRoles.firstIndex(of: a) ?? .max
                            let ib = LibraryItem.creditRoles.firstIndex(of: b) ?? .max
                            return ia < ib
                        }
                        .map(LibraryItem.roleLabel)
                        .joined(separator: ", ")
                    : nil
                return Entry(name: name, count: count, detail: detail)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var indexedCount: Int {
        items.filter(\.hasCredits).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if entries.isEmpty {
                GhostEmptyState(
                    title: search.isEmpty ? "Nothing indexed yet" : "Nothing matches",
                    message: search.isEmpty
                        ? "This comes from ComicInfo.xml inside your comics. Files without it won't appear here — the metadata editor can add it."
                        : "Try a different search."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry, accent: accent)
                                .onTapGesture { onSelect(facet, entry.name) }
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
                    Text("Index")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(CGTheme.text)
                    Text("\(indexedCount) of \(items.count) comics carry ComicInfo metadata")
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Picker("", selection: $facet) {
                    ForEach(Facet.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if facet == .creator, availableRoles.count > 1 {
                    Picker("", selection: $roleFilter) {
                        ForEach(availableRoles, id: \.self) {
                            Text(LibraryItem.roleLabel($0)).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CGTheme.subtext0)
                TextField("Search \(facet.rawValue.lowercased())", text: $search)
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
}

/// One row in the index.
struct CreditsIndexEntry: Identifiable {
    let name: String
    let count: Int
    let detail: String?
    var id: String { name }
}

private struct EntryRow: View {
    let entry: CreditsIndexEntry
    let accent: Color

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.callout)
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(1)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("\(entry.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isHovering ? accent : CGTheme.subtext0)
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

import SwiftUI

/// Library-wide reading stats: totals, pages read, ratings, per-series completion.
struct StatsView: View {
    let items: [LibraryItem]
    @AppStorage(CGGlass.key) private var glassEnabled: Bool = true

    private var completed: Int { items.filter { $0.status == .completed }.count }
    private var inProgress: Int { items.filter { $0.status == .inProgress }.count }
    private var favorites: Int { items.filter(\.isFavorite).count }
    private var queued: Int { items.filter(\.isQueued).count }

    private var ratedItems: [LibraryItem] { items.filter { $0.rating > 0 } }

    private var averageRating: Double? {
        guard !ratedItems.isEmpty else { return nil }
        return Double(ratedItems.reduce(0) { $0 + $1.rating }) / Double(ratedItems.count)
    }

    private var pagesRead: Int {
        items.reduce(0) { total, item in
            switch item.status {
            case .completed: return total + item.pageCount
            case .inProgress: return total + (item.progress.map { $0.currentPage + 1 } ?? 0)
            default: return total
            }
        }
    }

    private var seriesBreakdown: [Series] {
        Dictionary(grouping: items, by: \.seriesKey)
            .map { Series(name: $0.key, items: $0.value) }
            .sorted { $0.items.count > $1.items.count }
    }

    private var ratingCounts: [(stars: Int, count: Int)] {
        (1...5).reversed().map { stars in
            (stars, items.filter { $0.rating == stars }.count)
        }
    }

    private let cardColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            LazyVGrid(columns: cardColumns, spacing: 16) {
                statCard("Issues", "\(items.count)", icon: "books.vertical", color: CGTheme.lavender)
                statCard("Read", "\(completed)", icon: "checkmark.seal", color: CGTheme.green)
                statCard("In Progress", "\(inProgress)", icon: "book", color: CGTheme.sky)
                statCard("Pages Read", "\(pagesRead)", icon: "doc.text", color: CGTheme.mauve)
                statCard("Favorites", "\(favorites)", icon: "heart", color: CGTheme.pink)
                statCard("In Queue", "\(queued)", icon: "text.badge.plus", color: CGTheme.sapphire)
                statCard("Series", "\(seriesBreakdown.count)", icon: "square.stack", color: CGTheme.peach)
                if let averageRating {
                    statCard("Avg Rating", String(format: "%.1f", averageRating),
                             icon: "star", color: CGTheme.peach)
                }
            }

            if !ratedItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ratings")
                        .font(.headline)
                        .foregroundStyle(CGTheme.subtext1)

                    ForEach(ratingCounts, id: \.stars) { entry in
                        HStack(spacing: 10) {
                            StarDisplay(value: Double(entry.stars))
                                .frame(width: 80, alignment: .leading)
                            ProgressView(
                                value: Double(entry.count),
                                total: Double(max(ratedItems.count, 1))
                            )
                            .tint(CGTheme.peach)
                            Text("\(entry.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(CGTheme.subtext0)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CGTheme.surface0.opacity(glassEnabled ? 0.45 : 0.8))
                }
            }

            if !seriesBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Series completion")
                        .font(.headline)
                        .foregroundStyle(CGTheme.subtext1)

                    ForEach(seriesBreakdown.prefix(12)) { series in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(series.name)
                                    .font(.callout)
                                    .foregroundStyle(CGTheme.text)
                                    .lineLimit(1)
                                if let average = series.averageRating {
                                    StarDisplay(value: average, size: 9)
                                }
                                Spacer()
                                Text("\(series.readCount) / \(series.items.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(CGTheme.subtext0)
                            }
                            ProgressView(
                                value: Double(series.readCount),
                                total: Double(max(series.items.count, 1))
                            )
                            .tint(series.readCount == series.items.count ? CGTheme.green : CGTheme.sky)
                        }
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(CGTheme.surface0.opacity(glassEnabled ? 0.45 : 0.8))
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func statCard(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CGTheme.text)
            Text(label)
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(CGTheme.surface0.opacity(glassEnabled ? 0.45 : 0.8))
        }
    }
}

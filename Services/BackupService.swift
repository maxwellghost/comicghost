import Foundation
import SwiftData

/// Exports and restores everything the app knows that the files don't:
/// reading progress, ratings, favorites, labels, bookmarks, collections,
/// and manual metadata edits.
///
/// Items are matched on file path, so a backup restores cleanly onto a
/// re-imported library as long as the files live in the same place.
@MainActor
enum BackupService {

    // MARK: - Payload

    struct Payload: Codable {
        var version: Int = 1
        var exportedAt: Date = .now
        var items: [ItemRecord] = []
        var labels: [LabelRecord] = []
        var collections: [CollectionRecord] = []
    }

    struct ItemRecord: Codable {
        var filePath: String
        var title: String
        var seriesName: String?
        var issueNumber: String?
        var masterSeries: String?
        var isSpecial: Bool
        var isFavorite: Bool
        var isMetadataLocked: Bool
        var rating: Int
        var readingListOrder: Int?
        var labelNames: [String]
        var currentPage: Int?
        var isFinished: Bool?
        var lastReadDate: Date?
        var bookmarks: [BookmarkRecord]
    }

    struct BookmarkRecord: Codable {
        var page: Int
        var label: String
        var dateCreated: Date
    }

    struct LabelRecord: Codable {
        var name: String
        var colorName: String
        var isFavorite: Bool
        var sortIndex: Int
    }

    struct CollectionRecord: Codable {
        var name: String
        var icon: String
        var matchAll: Bool
        var rulesJSON: String
        var sortIndex: Int
    }

    // MARK: - Export

    static func makePayload(context: ModelContext) -> Payload {
        var payload = Payload()

        let labels = (try? context.fetch(FetchDescriptor<ComicLabel>())) ?? []
        payload.labels = labels.map {
            LabelRecord(
                name: $0.name, colorName: $0.colorName,
                isFavorite: $0.isFavorite, sortIndex: $0.sortIndex
            )
        }
        // Labels are referenced by name so they survive id changes.
        let labelNameByID = Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0.name) })

        let collections = (try? context.fetch(FetchDescriptor<SmartCollection>())) ?? []
        payload.collections = collections.map {
            CollectionRecord(
                name: $0.name, icon: $0.icon, matchAll: $0.matchAll,
                rulesJSON: String(data: $0.rulesData, encoding: .utf8) ?? "[]",
                sortIndex: $0.sortIndex
            )
        }

        let allBookmarks = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        let bookmarksByItem = Dictionary(grouping: allBookmarks, by: \.itemID)

        let items = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        payload.items = items.map { item in
            ItemRecord(
                filePath: item.filePath,
                title: item.title,
                seriesName: item.seriesName,
                issueNumber: item.issueNumber,
                masterSeries: item.masterSeries,
                isSpecial: item.isSpecial,
                isFavorite: item.isFavorite,
                isMetadataLocked: item.isMetadataLocked,
                rating: item.rating,
                readingListOrder: item.readingListOrder,
                labelNames: item.labelIDs.compactMap { labelNameByID[$0] },
                currentPage: item.progress?.currentPage,
                isFinished: item.progress?.isFinished,
                lastReadDate: item.progress?.lastReadDate,
                bookmarks: (bookmarksByItem[item.id] ?? []).map {
                    BookmarkRecord(page: $0.page, label: $0.label, dateCreated: $0.dateCreated)
                }
            )
        }

        return payload
    }

    static func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: data)
    }

    // MARK: - Restore

    struct RestoreResult {
        var matched = 0
        var missing = 0
        var labelsCreated = 0
        var collectionsCreated = 0
    }

    /// Applies a payload onto the current library, matching on file path.
    /// Never creates library items — restore after a rescan.
    @discardableResult
    static func restore(_ payload: Payload, context: ModelContext) -> RestoreResult {
        var result = RestoreResult()

        // Labels first, so items can reference them.
        var labels = (try? context.fetch(FetchDescriptor<ComicLabel>())) ?? []
        var labelByName = Dictionary(uniqueKeysWithValues: labels.map { ($0.name, $0) })

        for record in payload.labels where labelByName[record.name] == nil {
            let label = ComicLabel(
                name: record.name, colorName: record.colorName,
                isFavorite: record.isFavorite, sortIndex: record.sortIndex
            )
            context.insert(label)
            labels.append(label)
            labelByName[record.name] = label
            result.labelsCreated += 1
        }

        let existingCollections = Set(
            ((try? context.fetch(FetchDescriptor<SmartCollection>())) ?? []).map(\.name)
        )
        for record in payload.collections where !existingCollections.contains(record.name) {
            let collection = SmartCollection(
                name: record.name, icon: record.icon,
                matchAll: record.matchAll, sortIndex: record.sortIndex
            )
            collection.rulesData = Data(record.rulesJSON.utf8)
            context.insert(collection)
            result.collectionsCreated += 1
        }

        let items = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        let itemsByPath = Dictionary(items.map { ($0.filePath, $0) }, uniquingKeysWith: { a, _ in a })

        let existingBookmarks = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        var bookmarkKeys = Set(existingBookmarks.map { "\($0.itemID)#\($0.page)" })

        for record in payload.items {
            guard let item = itemsByPath[record.filePath] else {
                result.missing += 1
                continue
            }
            result.matched += 1

            item.title = record.title
            item.seriesName = record.seriesName
            item.issueNumber = record.issueNumber
            item.masterSeries = record.masterSeries
            item.isSpecial = record.isSpecial
            item.isFavorite = record.isFavorite
            item.isMetadataLocked = record.isMetadataLocked
            item.rating = record.rating
            item.readingListOrder = record.readingListOrder
            item.labelIDs = record.labelNames.compactMap { labelByName[$0]?.id }

            if let page = record.currentPage {
                if item.progress == nil {
                    let progress = ReadingProgress(item: item)
                    context.insert(progress)
                    item.progress = progress
                }
                item.progress?.currentPage = page
                item.progress?.isFinished = record.isFinished ?? false
                item.progress?.lastReadDate = record.lastReadDate ?? .now
                item.isNew = false
            }

            for bookmark in record.bookmarks {
                let key = "\(item.id)#\(bookmark.page)"
                guard !bookmarkKeys.contains(key) else { continue }
                let restored = Bookmark(itemID: item.id, page: bookmark.page, label: bookmark.label)
                restored.dateCreated = bookmark.dateCreated
                context.insert(restored)
                bookmarkKeys.insert(key)
            }
        }

        try? context.save()
        return result
    }

    // MARK: - Files

    static func suggestedFilename() -> String {
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        return "ComicGhost-Backup-\(stamp).json"
    }
}

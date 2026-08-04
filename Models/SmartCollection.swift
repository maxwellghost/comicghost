import Foundation
import SwiftData

/// A saved filter. Rules are stored as encoded JSON so the model stays simple.
@Model
final class SmartCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var matchAll: Bool          // true = all rules must match, false = any
    var rulesData: Data
    var sortIndex: Int
    var dateCreated: Date

    init(name: String, icon: String = "line.3.horizontal.decrease.circle", matchAll: Bool = true, rules: [SmartRule] = [], sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.matchAll = matchAll
        self.rulesData = (try? JSONEncoder().encode(rules)) ?? Data()
        self.sortIndex = sortIndex
        self.dateCreated = .now
    }

    var rules: [SmartRule] {
        get { (try? JSONDecoder().decode([SmartRule].self, from: rulesData)) ?? [] }
        set { rulesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Applies the rule set to a list of items.
    func matches(_ items: [LibraryItem]) -> [LibraryItem] {
        let ruleSet = rules
        guard !ruleSet.isEmpty else { return items }
        return items.filter { item in
            matchAll
                ? ruleSet.allSatisfy { $0.matches(item) }
                : ruleSet.contains { $0.matches(item) }
        }
    }
}

// MARK: - Rules

struct SmartRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var field: Field
    var comparison: Comparison
    var value: String

    enum Field: String, Codable, CaseIterable, Identifiable {
        case series, title, status, rating, favorite, special, queued, pageCount, dateAdded

        var id: String { rawValue }

        var label: String {
            switch self {
            case .series: return "Series"
            case .title: return "Title"
            case .status: return "Status"
            case .rating: return "Rating"
            case .favorite: return "Favorite"
            case .special: return "Special"
            case .queued: return "In reading list"
            case .pageCount: return "Page count"
            case .dateAdded: return "Date added"
            }
        }

        var kind: Kind {
            switch self {
            case .series, .title: return .text
            case .status: return .status
            case .rating, .pageCount: return .number
            case .favorite, .special, .queued: return .boolean
            case .dateAdded: return .days
            }
        }

        enum Kind { case text, status, number, boolean, days }
    }

    enum Comparison: String, Codable, CaseIterable, Identifiable {
        case contains, notContains, equals, notEquals
        case greaterThan, lessThan

        var id: String { rawValue }

        var label: String {
            switch self {
            case .contains: return "contains"
            case .notContains: return "doesn't contain"
            case .equals: return "is"
            case .notEquals: return "is not"
            case .greaterThan: return "is more than"
            case .lessThan: return "is less than"
            }
        }

        static func options(for kind: Field.Kind) -> [Comparison] {
            switch kind {
            case .text: return [.contains, .notContains, .equals, .notEquals]
            case .status, .boolean: return [.equals, .notEquals]
            case .number, .days: return [.equals, .greaterThan, .lessThan]
            }
        }
    }

    static let statusOptions = ["New", "Unread", "In Progress", "Completed"]

    func matches(_ item: LibraryItem) -> Bool {
        switch field {
        case .series:
            return textMatch(item.seriesKey)
        case .title:
            return textMatch(item.title)
        case .status:
            let name = statusName(item.status)
            return comparison == .notEquals ? name != value : name == value
        case .rating:
            return numberMatch(Double(item.rating))
        case .pageCount:
            return numberMatch(Double(item.pageCount))
        case .favorite:
            return boolMatch(item.isFavorite)
        case .special:
            return boolMatch(item.isSpecial)
        case .queued:
            return boolMatch(item.isQueued)
        case .dateAdded:
            guard let days = Double(value) else { return true }
            let age = Date.now.timeIntervalSince(item.dateAdded) / 86400
            switch comparison {
            case .lessThan: return age < days
            case .greaterThan: return age > days
            default: return Int(age) == Int(days)
            }
        }
    }

    private func statusName(_ status: LibraryItem.Status) -> String {
        switch status {
        case .new: return "New"
        case .unread: return "Unread"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }

    private func textMatch(_ subject: String) -> Bool {
        switch comparison {
        case .contains: return subject.localizedCaseInsensitiveContains(value)
        case .notContains: return !subject.localizedCaseInsensitiveContains(value)
        case .equals: return subject.compare(value, options: .caseInsensitive) == .orderedSame
        case .notEquals: return subject.compare(value, options: .caseInsensitive) != .orderedSame
        default: return true
        }
    }

    private func numberMatch(_ subject: Double) -> Bool {
        guard let target = Double(value) else { return true }
        switch comparison {
        case .greaterThan: return subject > target
        case .lessThan: return subject < target
        case .notEquals: return subject != target
        default: return subject == target
        }
    }

    private func boolMatch(_ subject: Bool) -> Bool {
        let target = (value as NSString).boolValue
        return comparison == .notEquals ? subject != target : subject == target
    }
}

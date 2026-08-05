import Foundation
import SwiftData
import SwiftUI

/// A user-defined label. Items can carry any number of them.
/// Separate from series and status — for things like "Essential",
/// "Crossover", "Re-read", "Lend to Dave".
@Model
final class ComicLabel {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorName: String
    /// Favorite labels sort first in menus and get their own sidebar row.
    var isFavorite: Bool
    var sortIndex: Int
    var dateCreated: Date

    init(name: String, colorName: String = "mauve", isFavorite: Bool = false, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorName = colorName
        self.isFavorite = isFavorite
        self.sortIndex = sortIndex
        self.dateCreated = .now
    }

    var color: Color {
        LabelColor(rawValue: colorName)?.color ?? CGTheme.mauve
    }
}

/// Fixed palette so labels stay on-theme.
enum LabelColor: String, CaseIterable, Identifiable {
    case mauve, lavender, pink, red, peach, green, teal, sky, sapphire

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .mauve: return CGTheme.mauve
        case .lavender: return CGTheme.lavender
        case .pink: return CGTheme.pink
        case .red: return CGTheme.red
        case .peach: return CGTheme.peach
        case .green: return CGTheme.green
        case .teal: return CGTheme.teal
        case .sky: return CGTheme.sky
        case .sapphire: return CGTheme.sapphire
        }
    }
}

import Foundation
import SwiftData

/// A file the user removed from the library but kept on disk.
/// Scans skip these, so removal sticks without deleting anything.
@Model
final class IgnoredFile {
    @Attribute(.unique) var path: String
    var title: String
    var seriesName: String?
    var dateIgnored: Date

    init(path: String, title: String, seriesName: String? = nil) {
        self.path = path
        self.title = title
        self.seriesName = seriesName
        self.dateIgnored = .now
    }

    var filename: String { (path as NSString).lastPathComponent }
}

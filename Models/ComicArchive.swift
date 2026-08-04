import Foundation

/// Transient, in-memory representation of an opened CBR/CBZ file.
/// Not persisted — `LibraryItem` is the durable record.
struct ComicArchive {
    let sourceURL: URL
    let format: Format
    let pages: [ComicPage]

    enum Format: String {
        case cbz, cbr

        init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "cbz": self = .cbz
            case "cbr": self = .cbr
            default: return nil
            }
        }
    }

    var pageCount: Int { pages.count }
}

/// A single page: a reference to an extracted image on disk plus its position.
struct ComicPage: Identifiable {
    let id = UUID()
    let index: Int          // 0-based reading order
    let imageURL: URL       // extracted image in the temp/cache directory
}

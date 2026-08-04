import Foundation

/// Transient, in-memory representation of an opened comic file.
/// Not persisted — `LibraryItem` is the durable record.
struct ComicArchive {
    let sourceURL: URL
    let format: Format
    let pages: [ComicPage]

    enum Format: String, CaseIterable {
        case cbz, cbr, cb7
        case zip, rar, sevenZip, tar
        case pdf

        /// Every extension the library will pick up.
        static let allExtensions: Set<String> = [
            "cbz", "cbr", "cb7",
            "zip", "rar", "7z",
            "tar", "tar.gz", "tgz",
            "pdf",
        ]

        init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "cbz": self = .cbz
            case "cbr": self = .cbr
            case "cb7": self = .cb7
            case "zip": self = .zip
            case "rar": self = .rar
            case "7z":  self = .sevenZip
            case "tar", "tgz": self = .tar
            case "pdf": self = .pdf
            default: return nil
            }
        }

        /// Which extraction backend handles this format.
        var backend: Backend {
            switch self {
            case .cbz, .zip: return .zipFoundation
            case .cbr, .rar: return .unrar
            case .cb7, .sevenZip, .tar: return .bsdtar
            case .pdf: return .pdfKit
            }
        }

        enum Backend { case zipFoundation, unrar, bsdtar, pdfKit }
    }

    var pageCount: Int { pages.count }
}

/// A single page: a reference to an image on disk plus its position.
struct ComicPage: Identifiable {
    let id = UUID()
    let index: Int          // 0-based reading order
    let imageURL: URL       // extracted or rendered image
}

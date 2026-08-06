import Foundation

/// Transient, in-memory representation of an opened comic file.
/// Sendable so extraction can happen off the main actor.
nonisolated struct ComicArchive: Sendable {
    let sourceURL: URL
    let format: Format
    let pages: [ComicPage]

    enum Format: String, CaseIterable, Sendable {
        case cbz, cbr, cb7
        case zip, rar, sevenZip, tar
        case pdf
        /// A plain folder of loose images, read in place.
        case folder

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

        /// Resolves any URL, including folders of loose images.
        ///
        /// `init(fileExtension:)` can't see folders, so anything that walks the
        /// disk should come through here instead.
        static func detect(_ url: URL) -> Format? {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return nil
            }
            if isDirectory.boolValue {
                return ArchiveSupport.qualifiesAsLooseComic(url) ? .folder : nil
            }
            return Format(fileExtension: url.pathExtension)
        }

        var backend: Backend {
            switch self {
            case .cbz, .zip: return .zipFoundation
            case .cbr, .rar: return .unrar
            case .cb7, .sevenZip, .tar: return .bsdtar
            case .pdf: return .pdfKit
            case .folder: return .loose
            }
        }

        enum Backend: Sendable { case zipFoundation, unrar, bsdtar, pdfKit, loose }
    }

    var pageCount: Int { pages.count }
}

/// A single page: a reference to an image on disk plus its position.
nonisolated struct ComicPage: Identifiable, Sendable {
    let id = UUID()
    let index: Int          // 0-based reading order
    let imageURL: URL       // extracted or rendered image
}

import Foundation

/// One `<Page>` entry inside the `<Pages>` block of ComicInfo.xml.
/// Attributes are kept as a raw dictionary so nothing is lost on rewrite —
/// ImageSize, ImageWidth, ImageHeight, Key, DoublePage and any vendor-specific
/// attributes survive even though the editor only exposes a few of them.
nonisolated struct ComicInfoPage: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var attributes: [String: String] = [:]

    init(attributes: [String: String] = [:]) {
        self.attributes = attributes
    }

    /// Zero-based page index this entry describes.
    var image: Int {
        get { Int(attributes["Image"] ?? "") ?? 0 }
        set { attributes["Image"] = String(newValue) }
    }

    /// Chapter / issue marker. This is what collection and omnibus scans use to
    /// mark where one issue ends and the next begins.
    var bookmark: String {
        get { attributes["Bookmark"] ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { attributes.removeValue(forKey: "Bookmark") }
            else { attributes["Bookmark"] = trimmed }
        }
    }

    /// FrontCover, Story, Advertisement, Editorial, etc.
    var type: String {
        get { attributes["Type"] ?? "" }
        set {
            if newValue.isEmpty { attributes.removeValue(forKey: "Type") }
            else { attributes["Type"] = newValue }
        }
    }

    var isEmpty: Bool {
        attributes.filter { $0.key != "Image" }.isEmpty
    }
}

/// A parsed ComicInfo.xml document.
///
/// Storage is a flat `[String: String]` rather than forty named properties.
/// Two reasons: the editor can bind to any field generically, and fields this
/// app has never heard of are preserved automatically instead of being silently
/// dropped the first time you save.
nonisolated struct ComicInfo: Equatable, Sendable {

    /// Standard ComicInfo v2.0 elements, in canonical schema order.
    /// Serialization emits these first, then any unrecognised fields.
    enum Key: String, CaseIterable, Sendable {
        case title = "Title"
        case series = "Series"
        case number = "Number"
        case count = "Count"
        case volume = "Volume"
        case alternateSeries = "AlternateSeries"
        case alternateNumber = "AlternateNumber"
        case alternateCount = "AlternateCount"
        case summary = "Summary"
        case notes = "Notes"
        case year = "Year"
        case month = "Month"
        case day = "Day"
        case writer = "Writer"
        case penciller = "Penciller"
        case inker = "Inker"
        case colorist = "Colorist"
        case letterer = "Letterer"
        case coverArtist = "CoverArtist"
        case editor = "Editor"
        case translator = "Translator"
        case publisher = "Publisher"
        case imprint = "Imprint"
        case genre = "Genre"
        case tags = "Tags"
        case web = "Web"
        case pageCount = "PageCount"
        case languageISO = "LanguageISO"
        case format = "Format"
        case blackAndWhite = "BlackAndWhite"
        case manga = "Manga"
        case characters = "Characters"
        case teams = "Teams"
        case locations = "Locations"
        case scanInformation = "ScanInformation"
        case storyArc = "StoryArc"
        case storyArcNumber = "StoryArcNumber"
        case seriesGroup = "SeriesGroup"
        case ageRating = "AgeRating"
        case communityRating = "CommunityRating"
        case mainCharacterOrTeam = "MainCharacterOrTeam"
        case review = "Review"
        case gtin = "GTIN"

        var label: String {
            switch self {
            case .languageISO: return "Language (ISO)"
            case .gtin: return "GTIN"
            case .blackAndWhite: return "Black and White"
            case .alternateSeries: return "Alternate Series"
            case .alternateNumber: return "Alternate Number"
            case .alternateCount: return "Alternate Count"
            case .coverArtist: return "Cover Artist"
            case .pageCount: return "Page Count"
            case .scanInformation: return "Scan Information"
            case .storyArc: return "Story Arc"
            case .storyArcNumber: return "Story Arc Number"
            case .seriesGroup: return "Series Group"
            case .ageRating: return "Age Rating"
            case .communityRating: return "Community Rating"
            case .mainCharacterOrTeam: return "Main Character or Team"
            default:
                // Insert a space before each capital: "AlternateSeries" -> "Alternate Series"
                var out = ""
                for ch in rawValue {
                    if ch.isUppercase && !out.isEmpty { out.append(" ") }
                    out.append(ch)
                }
                return out
            }
        }
    }

    /// Element name -> text content. Includes unknown elements.
    var fields: [String: String] = [:]

    /// The `<Pages>` block, preserved in document order.
    var pages: [ComicInfoPage] = []

    /// True when the source archive had no ComicInfo.xml at all.
    var wasMissing: Bool = false

    init() {}

    subscript(key: Key) -> String {
        get { fields[key.rawValue] ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { fields.removeValue(forKey: key.rawValue) }
            else { fields[key.rawValue] = trimmed }
        }
    }

    /// Fields present in the file that aren't part of the standard schema.
    var unknownKeys: [String] {
        let known = Set(Key.allCases.map(\.rawValue))
        return fields.keys.filter { !known.contains($0) }.sorted()
    }

    /// Pages carrying a Bookmark attribute, i.e. chapter / issue boundaries.
    var chapters: [ComicInfoPage] {
        pages.filter { !$0.bookmark.isEmpty }.sorted { $0.image < $1.image }
    }

    var isEmpty: Bool { fields.isEmpty && pages.isEmpty }

    // MARK: - Parsing

    static func parse(_ data: Data) -> ComicInfo {
        let parser = ComicInfoXMLParser()
        return parser.parse(data)
    }

    // MARK: - Serialization

    func xmlData() -> Data {
        var out = #"<?xml version="1.0" encoding="utf-8"?>"# + "\n"
        out += #"<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">"# + "\n"

        for key in Key.allCases {
            let value = self[key]
            guard !value.isEmpty else { continue }
            out += "  <\(key.rawValue)>\(Self.escape(value))</\(key.rawValue)>\n"
        }

        for key in unknownKeys {
            let value = fields[key] ?? ""
            guard !value.isEmpty, Self.isValidElementName(key) else { continue }
            out += "  <\(key)>\(Self.escape(value))</\(key)>\n"
        }

        let usable = pages.filter { !$0.attributes.isEmpty }
        if !usable.isEmpty {
            out += "  <Pages>\n"
            for page in usable.sorted(by: { $0.image < $1.image }) {
                var parts: [String] = []
                // Image first, then everything else alphabetically for stable output.
                if let image = page.attributes["Image"] {
                    parts.append("Image=\"\(Self.escape(image))\"")
                }
                for name in page.attributes.keys.sorted() where name != "Image" {
                    let value = page.attributes[name] ?? ""
                    parts.append("\(name)=\"\(Self.escape(value))\"")
                }
                out += "    <Page \(parts.joined(separator: " ")) />\n"
            }
            out += "  </Pages>\n"
        }

        out += "</ComicInfo>\n"
        return Data(out.utf8)
    }

    private static func escape(_ value: String) -> String {
        var s = value
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        s = s.replacingOccurrences(of: "'", with: "&apos;")
        return s
    }

    private static func isValidElementName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        guard first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
    }
}

// MARK: - XMLParser delegate

nonisolated final class ComicInfoXMLParser: NSObject, XMLParserDelegate {
    private var result = ComicInfo()
    private var currentText = ""
    private var inPages = false

    func parse(_ data: Data) -> ComicInfo {
        result = ComicInfo()
        currentText = ""
        inPages = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        _ = parser.parse()
        return result
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "Pages" {
            inPages = true
            return
        }
        if elementName == "Page" {
            if inPages { result.pages.append(ComicInfoPage(attributes: attributeDict)) }
            return
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { currentText += s }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "Pages":
            inPages = false
        case "Page", "ComicInfo":
            break
        default:
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.fields[elementName] = trimmed }
        }
        currentText = ""
    }
}

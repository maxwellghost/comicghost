import Foundation
import ZIPFoundation

/// Series/issue metadata for grouping and display.
/// Precedence: embedded ComicInfo.xml → filename parsing → containing folder name.
nonisolated enum MetadataParser {

    struct ParsedMetadata {
        var title: String           // display title, e.g. "Uncanny X-Men #34"
        var seriesName: String?     // e.g. "Uncanny X-Men"
        var issueNumber: String?    // e.g. "34", "Annual 1", "0.5"
        var year: Int?
    }

    /// Words that mark an issue as a special rather than part of the numbered run.
    private static let specialKeywords = [
        "annual", "special", "one-shot", "one shot", "oneshot", "giant-size",
        "giant size", "holiday", "spectacular", "yearbook", "handbook",
        "prologue", "epilogue", "omnibus", "tpb", "preview",
    ]

    /// True when the parsed issue number or title reads as a special/annual.
    static func looksSpecial(issueNumber: String?, title: String) -> Bool {
        let haystack = ((issueNumber ?? "") + " " + title).lowercased()
        return specialKeywords.contains { haystack.contains($0) }
    }

    // MARK: - Entry point

    /// Best available metadata for an archive.
    /// - Parameter folderHint: name of the containing folder, used as a series
    ///   fallback when the filename alone doesn't reveal one.
    static func metadata(for archiveURL: URL, folderHint: String? = nil) -> ParsedMetadata {
        if let info = parseComicInfo(in: archiveURL), info.seriesName != nil {
            return info
        }

        var parsed = parse(filename: archiveURL.lastPathComponent)

        // Folder name wins when the filename gave us nothing usable — e.g.
        // "Uncanny X-Men/001.cbr" or "Superman/Superman 12.cbr".
        if let folderHint {
            let cleanedFolder = cleanSeriesName(folderHint)
            if !cleanedFolder.isEmpty {
                let filenameSeriesIsWeak = parsed.seriesName == nil
                    || parsed.seriesName?.count ?? 0 < 3
                    || isMostlyDigits(parsed.seriesName ?? "")

                if filenameSeriesIsWeak {
                    parsed.seriesName = cleanedFolder
                    if let issue = parsed.issueNumber {
                        parsed.title = issue.contains(" ")
                            ? "\(cleanedFolder) \(issue)"
                            : "\(cleanedFolder) #\(issue)"
                    }
                }
            }
        }

        return parsed
    }

    /// Strips issue ranges and years off a folder name:
    /// "Uncanny X-Men 001 - 544" → "Uncanny X-Men"
    /// "Superman (2018-2021)"    → "Superman"
    static func cleanSeriesName(_ raw: String) -> String {
        var working = raw

        // Bracketed groups: (2018-2021), [Digital], etc.
        working = replacing(working, pattern: #"[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: " ")

        // Trailing issue/volume ranges: "001 - 544", "#1-544", "v1 - v10", "1 to 50"
        working = replacing(
            working,
            pattern: #"(?i)[\s\-–—]+v?\.?#?\s*\d{1,5}\s*(?:-|–|—|to|thru|through)\s*v?\.?#?\s*\d{1,5}\s*$"#,
            with: " "
        )

        // Trailing bare number: "Superman 001"
        working = replacing(working, pattern: #"[\s\-–—]+#?\d{1,5}\s*$"#, with: " ")

        working = working.replacingOccurrences(of: "_", with: " ")
        working = replacing(working, pattern: #"\s+"#, with: " ")

        return working.trimmingCharacters(in: CharacterSet(charactersIn: " -–—.:"))
    }

    private static func isMostlyDigits(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber).count
        return digits > 0 && digits >= text.count / 2
    }

    // MARK: - Filename parsing

    private static let junkTokens: [String] = [
        "getcomics.info", "getcomics", "digital", "digital-empire", "empire",
        "zone-empire", "dcp", "minutemen", "scanlation", "webrip", "c2c",
        "the last kryptonian-dcp", "phillip-dcp", "bean-dcp", "ripperduck",
        "novus-hd", "hd-webrip", "repack", "scan", "wolfy", "yoyo",
    ]

    static func parse(filename: String) -> ParsedMetadata {
        var working = (filename as NSString).deletingPathExtension

        // 1. Pull the year out of any (1999) / [1999] group before stripping.
        var year: Int?
        if let match = firstMatch(in: working, pattern: #"[\(\[](\d{4})[\)\]]"#, group: 1),
           let value = Int(match), value >= 1930, value <= 2100 {
            year = value
        }

        // 2. Strip every bracketed/parenthesized group.
        working = replacing(working, pattern: #"[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: " ")

        // 3. Strip unbracketed junk tokens.
        for token in junkTokens {
            working = replacing(
                working,
                pattern: #"(?i)(^|[\s\-_\.])"# + NSRegularExpression.escapedPattern(for: token) + #"($|[\s\-_\.])"#,
                with: " "
            )
        }

        // 4. Normalize separators.
        working = working.replacingOccurrences(of: "_", with: " ")
        working = replacing(working, pattern: #"(?<=\D)\.(?=\D)"#, with: " ")
        working = replacing(working, pattern: #"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 5. Extract the issue number from the tail.
        var seriesName: String? = nil
        var issueNumber: String? = nil

        // Trailing [a-z]? catches variant-cover suffixes: "170b", "251b" —
        // common for newsstand/direct-market reprints of the same issue.
        let issuePatterns: [(pattern: String, label: String?)] = [
            (#"^(.*?)[\s\-]+(?:annual)[\s#]*(\d{1,4}[a-zA-Z]?)\s*$"#, "Annual"),
            (#"^(.*?)[\s\-]+v(?:ol)?\.?\s*(\d{1,3}[a-zA-Z]?)\s*$"#, "Vol."),
            (#"^(.*?)[\s\-]+#\s*(\d{1,5}(?:\.\d+)?[a-zA-Z]?)\s*$"#, nil),
            (#"^(.*?)[\s\-]+(\d{1,5}(?:\.\d+)?[a-zA-Z]?)\s*$"#, nil),
            (#"^#?\s*(\d{1,5}(?:\.\d+)?[a-zA-Z]?)\s*$"#, nil),   // bare "001b.cbr"
        ]

        for entry in issuePatterns {
            // The bare-number pattern has only one capture group.
            if entry.pattern.hasPrefix("^#?") {
                if let only = matchGroups(in: working, pattern: entry.pattern, count: 1) {
                    issueNumber = stripLeadingZeros(only[0])
                    break
                }
                continue
            }

            guard let groups = matchGroups(in: working, pattern: entry.pattern, count: 2) else { continue }
            let name = groups[0].trimmingCharacters(in: CharacterSet(charactersIn: " -–—.:"))
            let number = groups[1]
            guard !name.isEmpty else { continue }

            seriesName = name
            if let label = entry.label {
                issueNumber = "\(label) \(stripLeadingZeros(number))"
            } else {
                issueNumber = stripLeadingZeros(number)
            }
            break
        }

        // 6. Build the display title.
        let displayTitle: String
        if let seriesName, let issueNumber {
            displayTitle = issueNumber.contains(" ")
                ? "\(seriesName) \(issueNumber)"
                : "\(seriesName) #\(issueNumber)"
        } else if let issueNumber {
            displayTitle = "#\(issueNumber)"
        } else if !working.isEmpty {
            displayTitle = working
        } else {
            displayTitle = (filename as NSString).deletingPathExtension
        }

        return ParsedMetadata(
            title: displayTitle,
            seriesName: seriesName ?? (working.isEmpty ? nil : working),
            issueNumber: issueNumber,
            year: year
        )
    }

    // MARK: - ComicInfo.xml

    static func parseComicInfo(in archiveURL: URL) -> ParsedMetadata? {
        guard let xml = readComicInfoXML(from: archiveURL) else { return nil }

        let series = tagValue("Series", in: xml)
        let number = tagValue("Number", in: xml)
        let issueTitle = tagValue("Title", in: xml)
        let year = tagValue("Year", in: xml).flatMap(Int.init)

        guard series != nil || number != nil else { return nil }

        var display = series ?? issueTitle ?? "Untitled"
        if let number {
            display += " #\(stripLeadingZeros(number))"
        }
        if let issueTitle, !issueTitle.isEmpty, issueTitle != series {
            display += " – \(issueTitle)"
        }

        return ParsedMetadata(
            title: display,
            seriesName: series,
            issueNumber: number.map(stripLeadingZeros),
            year: year
        )
    }

    private static func readComicInfoXML(from archiveURL: URL) -> String? {
        guard let format = ComicArchive.Format(fileExtension: archiveURL.pathExtension) else { return nil }

        switch format {
        case .cbz:
            guard let archive = try? Archive(url: archiveURL, accessMode: .read) else { return nil }
            for entry in archive where entry.type == .file {
                let name = (entry.path as NSString).lastPathComponent.lowercased()
                guard name == "comicinfo.xml" else { continue }
                var data = Data()
                _ = try? archive.extract(entry) { chunk in data.append(chunk) }
                return String(data: data, encoding: .utf8)
            }
            return nil

        case .cbr:
            guard let unrar = Bundle.main.url(forResource: "unrar", withExtension: nil) else { return nil }
            let process = Process()
            process.executableURL = unrar
            process.arguments = ["p", "-inul", archiveURL.path, "ComicInfo.xml"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    private static func tagValue(_ tag: String, in xml: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let value = firstMatch(in: xml, pattern: pattern, group: 1) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Regex helpers

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let groupRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[groupRange])
    }

    private static func matchGroups(in text: String, pattern: String, count: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for index in 1...count {
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[groupRange]))
        }
        return groups
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    /// Strips leading zeros from the numeric portion while preserving any
    /// trailing variant letter: "0170b" -> "170b", "007" -> "7".
    private static func stripLeadingZeros(_ number: String) -> String {
        guard number.contains(".") == false else { return number }
        let suffix = number.last?.isLetter == true ? String(number.last!) : ""
        let digits = suffix.isEmpty ? number : String(number.dropLast())
        let stripped = digits.drop { $0 == "0" }
        let core = stripped.isEmpty ? "0" : String(stripped)
        return core + suffix
    }
}

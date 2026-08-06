import SwiftUI
import SwiftData

/// Views and edits the metadata stored inside the comic file itself.
///
/// This is deliberately a view of the *file*, not of the library row. The
/// library row holds Comic Ghost's parsed guesses; this shows what the archive
/// actually contains, and writes changes back to disk.
struct MetadataEditorSheet: View {
    let item: LibraryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allItems: [LibraryItem]

    /// Renaming a series from one issue would otherwise split the run in two,
    /// so the change is scoped explicitly.
    enum SeriesScope: String, CaseIterable, Identifiable {
        case wholeRun
        case thisIssueOnly
        var id: String { rawValue }
    }

    @State private var info = ComicInfo()
    @State private var originalSeries = ""
    @State private var seriesScope: SeriesScope = .wholeRun
    @State private var kind: WritableKind = .unsupported
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var convertToCBZ = false
    @State private var errorMessage: String?
    @State private var showAdvanced = false
    @State private var showChapters = false

    private var fileURL: URL { URL(fileURLWithPath: item.filePath) }

    /// Fields are locked until the file is actually writable.
    private var isEditable: Bool {
        switch kind {
        case .zip, .pdf, .folder: return true
        case .rar, .sevenZip, .tar: return convertToCBZ
        case .unsupported: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CGTheme.surface0)

            if isLoading {
                loadingState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let strip = stripMessage {
                            formatStrip(strip)
                        }
                        identitySection
                        publicationSection
                        creatorsSection
                        classificationSection
                        advancedSection
                        chaptersSection
                        if !info.unknownKeys.isEmpty {
                            unknownFieldsNote
                        }
                    }
                    .padding(20)
                }
            }

            Divider().overlay(CGTheme.surface0)
            footer
        }
        .frame(width: 620, height: 680)
        .background(CGTheme.base)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
            }
            Spacer()
            Text(kind.displayName)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(CGTheme.surface0)
                )
                .foregroundStyle(CGTheme.subtext0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var subtitle: String {
        if isLoading { return "Reading metadata…" }
        if info.wasMissing { return "No ComicInfo.xml in this file — saving will create one." }
        let count = info.fields.count
        return "\(count) field\(count == 1 ? "" : "s") in ComicInfo.xml"
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Reading metadata from the archive…")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Format strip

    private var stripMessage: (title: String, detail: String, showsToggle: Bool)? {
        switch kind {
        case .zip:
            return nil
        case .folder:
            return ("Folder of loose images",
                    "ComicInfo.xml is written straight into the folder alongside the pages. Nothing is repacked.",
                    false)
        case .pdf:
            return ("PDF supports a limited set of fields",
                    "Only Title, Writer, Summary and Tags are written back. Everything else is shown for reference and won't be saved.",
                    false)
        case .rar, .sevenZip, .tar:
            return ("\(kind.displayName) files can't be written to",
                    "Comic Ghost can read this format but not modify it. Converting rebuilds the file as a CBZ with your metadata — page order and folder structure are preserved, and the original moves to the Trash.",
                    true)
        case .unsupported:
            return ("This file type isn't supported",
                    "Comic Ghost can't read or write metadata for this format.",
                    false)
        }
    }

    private func formatStrip(_ strip: (title: String, detail: String, showsToggle: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(CGTheme.accent)
                Text(strip.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(CGTheme.text)
            }
            Text(strip.detail)
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
                .fixedSize(horizontal: false, vertical: true)

            if strip.showsToggle {
                Toggle(isOn: $convertToCBZ) {
                    Text("Convert to CBZ on save")
                        .font(.callout)
                        .foregroundStyle(CGTheme.text)
                }
                .toggleStyle(.switch)
                .tint(CGTheme.accent)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CGTheme.surface0.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CGTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Sections

    private var identitySection: some View {
        section("Identity") {
            field(.series)
            if seriesChanged { seriesScopeControl }
            HStack(spacing: 12) {
                field(.number)
                field(.count)
                field(.volume)
            }
            field(.title)
        }
    }

    /// The rest of the run, grouped the same way the library grid groups it.
    /// Keyed off seriesKey rather than the ComicInfo value, because the file's
    /// metadata and the library row don't always agree.
    private var runSiblings: [LibraryItem] {
        let key = item.seriesKey
        return allItems.filter {
            $0.persistentModelID != item.persistentModelID && $0.seriesKey == key
        }
    }

    private var seriesChanged: Bool {
        !originalSeries.isEmpty
            && !info[.series].isEmpty
            && info[.series] != originalSeries
    }

    private var seriesScopeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Series name changed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CGTheme.text)

            Picker("", selection: $seriesScope) {
                Text("All \(runSiblings.count + 1) issues in \(item.seriesKey)")
                    .tag(SeriesScope.wholeRun)
                Text("This issue only")
                    .tag(SeriesScope.thisIssueOnly)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(seriesScope == .wholeRun
                 ? "The other \(runSiblings.count) issues are renamed in your library. Their files aren't modified — only this one is written to disk."
                 : "Only this issue is renamed. It will appear as a separate series in the grid.")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CGTheme.surface0.opacity(0.45))
        )
    }

    private var publicationSection: some View {
        section("Publication") {
            HStack(spacing: 12) {
                field(.year)
                field(.month)
                field(.day)
            }
            HStack(spacing: 12) {
                field(.publisher)
                field(.imprint)
            }
        }
    }

    private var creatorsSection: some View {
        section("Creators") {
            HStack(spacing: 12) {
                field(.writer)
                field(.penciller)
            }
            HStack(spacing: 12) {
                field(.inker)
                field(.colorist)
            }
            HStack(spacing: 12) {
                field(.letterer)
                field(.coverArtist)
            }
            HStack(spacing: 12) {
                field(.editor)
                field(.translator)
            }
        }
    }

    private var classificationSection: some View {
        section("Classification") {
            HStack(spacing: 12) {
                field(.genre)
                field(.ageRating)
            }
            field(.tags)
            HStack(spacing: 12) {
                field(.format)
                field(.languageISO)
            }
            HStack(spacing: 12) {
                field(.manga)
                field(.blackAndWhite)
            }
            field(.pageCount)
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 12) {
                multilineField(.summary, height: 80)
                multilineField(.notes, height: 60)
                HStack(spacing: 12) {
                    field(.storyArc)
                    field(.storyArcNumber)
                }
                HStack(spacing: 12) {
                    field(.seriesGroup)
                    field(.mainCharacterOrTeam)
                }
                HStack(spacing: 12) {
                    field(.alternateSeries)
                    field(.alternateNumber)
                    field(.alternateCount)
                }
                field(.characters)
                field(.teams)
                field(.locations)
                HStack(spacing: 12) {
                    field(.web)
                    field(.gtin)
                }
                HStack(spacing: 12) {
                    field(.scanInformation)
                    field(.communityRating)
                }
                multilineField(.review, height: 60)
            }
            .padding(.top, 10)
        } label: {
            Text("More fields")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CGTheme.text)
        }
        .tint(CGTheme.accent)
    }

    // MARK: Chapters

    private var chapterIndices: [Int] {
        info.pages.indices
            .filter { !info.pages[$0].bookmark.isEmpty }
            .sorted { info.pages[$0].image < info.pages[$1].image }
    }

    private var chaptersSection: some View {
        DisclosureGroup(isExpanded: $showChapters) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Chapter markers tell the reader where one issue ends and the next begins inside a collected volume. Files without them are treated as a single issue.")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)

                if chapterIndices.isEmpty {
                    Text("No chapter markers in this file.")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                        .padding(.vertical, 4)
                } else {
                    ForEach(chapterIndices, id: \.self) { index in
                        HStack(spacing: 10) {
                            TextField("Page", value: pageBinding(index), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                            TextField("Chapter name", text: bookmarkBinding(index))
                                .textFieldStyle(.roundedBorder)
                            Button {
                                clearChapter(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(CGTheme.subtext0)
                        }
                        .disabled(!isEditable)
                    }
                }

                Button {
                    addChapter()
                } label: {
                    Label("Add Chapter Marker", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(CGTheme.accent)
                .disabled(!isEditable)
                .padding(.top, 2)
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 6) {
                Text("Chapters")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CGTheme.text)
                if !chapterIndices.isEmpty {
                    Text("\(chapterIndices.count)")
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
        }
        .tint(CGTheme.accent)
    }

    private func pageBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { info.pages.indices.contains(index) ? info.pages[index].image : 0 },
            set: { if info.pages.indices.contains(index) { info.pages[index].image = max(0, $0) } }
        )
    }

    private func bookmarkBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { info.pages.indices.contains(index) ? info.pages[index].bookmark : "" },
            set: { if info.pages.indices.contains(index) { info.pages[index].bookmark = $0 } }
        )
    }

    private func addChapter() {
        let nextPage = (info.pages.map(\.image).max() ?? -1) + 1
        info.pages.append(ComicInfoPage(attributes: [
            "Image": String(nextPage),
            "Bookmark": "New chapter"
        ]))
        showChapters = true
    }

    /// Clears the marker but keeps the page entry if it carries other data,
    /// so ImageSize and friends aren't lost.
    private func clearChapter(at index: Int) {
        guard info.pages.indices.contains(index) else { return }
        info.pages[index].bookmark = ""
        if info.pages[index].isEmpty {
            info.pages.remove(at: index)
        }
    }

    private var unknownFieldsNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .foregroundStyle(CGTheme.subtext0)
            Text("This file also contains \(info.unknownKeys.count) non-standard field\(info.unknownKeys.count == 1 ? "" : "s") (\(info.unknownKeys.joined(separator: ", "))). They aren't editable here but are preserved when you save.")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Field builders

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CGTheme.text)
            content()
        }
    }

    private func binding(_ key: ComicInfo.Key) -> Binding<String> {
        Binding(get: { info[key] }, set: { info[key] = $0 })
    }

    private func field(_ key: ComicInfo.Key) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.label)
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
            TextField("", text: binding(key))
                .textFieldStyle(.roundedBorder)
                .disabled(!isEditable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func multilineField(_ key: ComicInfo.Key, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.label)
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
            TextEditor(text: binding(key))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CGTheme.surface0.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(CGTheme.surface0, lineWidth: 1)
                )
                .disabled(!isEditable)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(CGTheme.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(saveTitle) {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isEditable || isSaving || isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .center) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var saveTitle: String {
        if isSaving { return "Saving…" }
        if kind.isConvertible && convertToCBZ { return "Convert and Save" }
        return "Save"
    }

    // MARK: - Load

    private func load() async {
        let url = fileURL
        let detected = WritableKind.of(url)

        let loaded: ComicInfo? = await Task.detached(priority: .userInitiated) {
            try? MetadataWriter.read(from: url)
        }.value

        var result = loaded ?? {
            var empty = ComicInfo()
            empty.wasMissing = true
            return empty
        }()

        // Seed from what the library already knows, so a file with no
        // ComicInfo.xml doesn't open completely blank.
        if result.wasMissing {
            if result[.series].isEmpty, let series = item.seriesName, !series.isEmpty {
                result[.series] = series
            }
            if result[.number].isEmpty, let number = item.issueNumber, !number.isEmpty {
                result[.number] = number
            }
            if result[.title].isEmpty {
                result[.title] = item.title
            }
            if result[.pageCount].isEmpty, item.pageCount > 0 {
                result[.pageCount] = String(item.pageCount)
            }
        }

        kind = detected
        info = result
        originalSeries = result[.series]
        isLoading = false
    }

    // MARK: - Save

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let url = fileURL
        let payload = info
        let shouldConvert = convertToCBZ

        let outcome: Result<MetadataWriteResult, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let result = try MetadataWriter.write(payload, to: url, convertToCBZ: shouldConvert)
                return .success(result)
            } catch {
                return .failure(error)
            }
        }.value

        switch outcome {
        case .failure(let error):
            errorMessage = error.localizedDescription

        case .success(let result):
            apply(result)
            dismiss()
        }
    }

    /// Pushes the saved values onto the library row so the grid matches the file.
    private func apply(_ result: MetadataWriteResult) {
        if result.didConvert {
            item.filePath = result.fileURL.path
        }

        let series = info[.series]
        if !series.isEmpty {
            item.seriesName = series
            if seriesChanged, seriesScope == .wholeRun {
                // Library rows only. Rewriting 500 archives to change one field
                // is not something to trigger from a single Save button.
                for sibling in runSiblings {
                    sibling.seriesName = series
                    sibling.isMetadataLocked = true
                }
            }
        }

        let number = info[.number]
        if !number.isEmpty { item.issueNumber = number }

        let title = info[.title]
        if !title.isEmpty { item.title = title }

        // Keep the index in step with what was just written to the file.
        item.creditsRaw = LibraryItem.creditRoles
            .compactMap { role -> String? in
                guard let key = ComicInfo.Key(rawValue: role) else { return nil }
                let value = info[key]
                return value.isEmpty ? nil : "\(role)\t\(value)"
            }
            .joined(separator: "\n")
        item.charactersRaw = LibraryItem.encodeList(LibraryItem.splitNames(info[.characters]))
        item.teamsRaw = LibraryItem.encodeList(LibraryItem.splitNames(info[.teams]))
        item.genresRaw = LibraryItem.encodeList(LibraryItem.splitNames(info[.genre]))
        item.storyArcName = info[.storyArc].isEmpty ? nil : info[.storyArc]
        item.publisherName = info[.publisher].isEmpty ? nil : info[.publisher]
        item.seriesGroupName = info[.seriesGroup].isEmpty ? nil : info[.seriesGroup]
        item.chapters = info.chapters.map {
            LibraryItem.Chapter(startPage: $0.image, title: $0.bookmark)
        }

        // A hand-edited file shouldn't get clobbered by the next rescan.
        item.isMetadataLocked = true

        try? context.save()
    }
}

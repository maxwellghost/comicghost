import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Reports about the library: gaps, duplicates, storage, integrity, export.
struct LibraryToolsView: View {
    let items: [LibraryItem]
    var onOpen: (LibraryItem) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @AppStorage(CGGlass.key) private var glassEnabled: Bool = true
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @Query(sort: \IgnoredFile.dateIgnored, order: .reverse) private var ignored: [IgnoredFile]
    @State private var analysis = LibraryAnalysis.shared
    @State private var converter = BatchConverter.shared
    @State private var exportMessage: String?
    /// Which sections are open, one flag each, remembered between launches.
    @AppStorage("toolsOpenGaps") private var openGaps = true
    @AppStorage("toolsOpenDuplicates") private var openDuplicates = true
    @AppStorage("toolsOpenIgnored") private var openIgnored = false
    @AppStorage("toolsOpenStorage") private var openStorage = false
    @AppStorage("toolsOpenIntegrity") private var openIntegrity = false
    @AppStorage("toolsOpenCovers") private var openCovers = false
    @AppStorage("toolsOpenConvert") private var openConvert = false
    @AppStorage("toolsOpenExport") private var openExport = false

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    private var gaps: [LibraryAnalysis.Gap] { analysis.gaps(in: items) }
    private var duplicates: [LibraryAnalysis.DuplicateGroup] { analysis.duplicates(in: items) }

    /// Entries whose file is no longer where it was. Restoring these does
    /// nothing, so they'd sit in the list forever.
    private var missingIgnored: [IgnoredFile] {
        ignored.filter { !FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if analysis.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    Text(analysis.scanLabel)
                        .font(.callout)
                        .foregroundStyle(CGTheme.text)
                    ProgressView(value: analysis.scanProgress).tint(accent)
                }
                .padding(14)
                .background { card }
            }

            gapsSection
            duplicatesSection
            ignoredSection
            storageSection
            integritySection
            coversSection
            convertSection
            exportSection
        }
        .padding()
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// A section that collapses to its header. `badge` is the one number worth
    /// seeing without opening it.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        _ subtitle: String,
        systemImage: String,
        isOpen: Binding<Bool>,
        badge: String? = nil,
        badgeColor: Color = CGTheme.subtext0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isOpen.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CGTheme.subtext0)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                    Image(systemName: systemImage).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.headline).foregroundStyle(CGTheme.text)
                        Text(subtitle).font(.caption).foregroundStyle(CGTheme.subtext0)
                    }
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(badgeColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue { content() }
        }
    }

    private var convertSection: some View {
        let candidates = converter.candidates(in: items)

        return section("Convert to CBZ",
                       "CBR and 7z open by launching a helper tool every time. CBZ reads in-process.",
                       systemImage: "arrow.triangle.2.circlepath",
                       isOpen: $openConvert,
                       badge: candidates.isEmpty ? nil : "\(candidates.count)",
                       badgeColor: CGTheme.peach) {
            VStack(alignment: .leading, spacing: 12) {
                if converter.isRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(converter.processed) of \(converter.total)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(CGTheme.text)
                            Spacer()
                            Button("Stop") { converter.cancel() }
                                .buttonStyle(.plain)
                                .foregroundStyle(CGTheme.red)
                        }
                        ProgressView(value: converter.progressFraction).tint(accent)
                        Text(converter.currentName.isEmpty
                             ? converter.stage
                             : "\(converter.stage) · \(converter.currentName)")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else if candidates.isEmpty {
                    Text("Everything is already CBZ or PDF.")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(candidates.count) file\(candidates.count == 1 ? "" : "s") can be converted.")
                            .font(.callout)
                            .foregroundStyle(CGTheme.text)
                        Text("Each original moves to the Trash once its replacement is verified. Page order and folder structure are preserved, and existing ComicInfo.xml is carried across. This is slow — expect roughly a second per issue, more for large files.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Convert \(candidates.count) to CBZ") {
                            converter.run(items, context: context)
                        }
                    }
                }

                if !converter.isRunning,
                   converter.lastSummary != nil || !converter.failures.isEmpty {
                    Divider()

                    HStack {
                        if let summary = converter.lastSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(CGTheme.subtext0)
                        }
                        Spacer()
                        Button("Clear Results") { converter.clearResults() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }

                    if !converter.failures.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(converter.failures) { failure in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(failure.name)
                                        .font(.caption)
                                        .foregroundStyle(CGTheme.text)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(failure.reason)
                                        .font(.caption2)
                                        .foregroundStyle(CGTheme.red)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { card }
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(CGTheme.surface0.opacity(glassEnabled ? 0.45 : 0.8))
    }

    // MARK: - Gaps

    private var gapsSection: some View {
        section("Missing issues", "Gaps in the numbered run of each series",
                systemImage: "square.dashed",
                isOpen: $openGaps,
                badge: gaps.isEmpty ? nil : "\(gaps.count) series",
                badgeColor: CGTheme.peach) {
            VStack(alignment: .leading, spacing: 10) {
                if gaps.isEmpty {
                    Text("No gaps found. Every series runs continuously between its lowest and highest issue.")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { card }
                } else {
                    ForEach(gaps) { gap in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(gap.series)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(CGTheme.text)
                                Spacer()
                                Text("\(gap.missingCount) missing")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(CGTheme.peach)
                            }
                            Text(gap.summary)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(CGTheme.subtext1)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { card }
                    }
                }
            }
        }
    }

    // MARK: - Duplicates

    private var duplicatesSection: some View {
        section("Duplicates", "Same issue present more than once",
                systemImage: "doc.on.doc",
                isOpen: $openDuplicates,
                badge: duplicates.isEmpty ? nil : "\(duplicates.count)",
                badgeColor: CGTheme.peach) {
            VStack(alignment: .leading, spacing: 10) {
                if duplicates.isEmpty {
                    Text("No duplicates found.")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { card }
                } else {
                    ForEach(duplicates) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.series) #\(group.issue)")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(CGTheme.text)

                            ForEach(group.items) { item in
                                HStack(spacing: 8) {
                                    Text((item.filePath as NSString).lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(CGTheme.subtext1)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Open") { onOpen(item) }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                    Button("Trash") {
                                        removeFromLibrary(item, context: context)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .foregroundStyle(CGTheme.red)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { card }
                    }
                }
            }
        }
    }

    // MARK: - Ignored files

    private var ignoredSection: some View {
        section("Removed from library",
                "Files still on disk that scans skip",
                systemImage: "eye.slash",
                isOpen: $openIgnored,
                badge: ignored.isEmpty ? nil : "\(ignored.count)") {
            VStack(alignment: .leading, spacing: 10) {
                if ignored.isEmpty {
                    Text("Nothing removed. Removing an issue from the library without trashing it lists it here, so you can put it back later.")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { card }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(ignored.count) file\(ignored.count == 1 ? "" : "s") skipped")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(CGTheme.text)
                            Spacer()
                            if !missingIgnored.isEmpty {
                                Button("Forget \(missingIgnored.count) Missing") {
                                    for entry in missingIgnored { context.delete(entry) }
                                    try? context.save()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            Button("Restore All") {
                                for entry in ignored { context.delete(entry) }
                                try? context.save()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }

                        ForEach(ignored) { entry in
                            let exists = FileManager.default.fileExists(atPath: entry.path)
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.callout)
                                        .foregroundStyle(CGTheme.text)
                                        .lineLimit(1)
                                    Text(exists ? entry.filename : "No longer on disk")
                                        .font(.caption)
                                        .foregroundStyle(exists ? CGTheme.subtext0 : CGTheme.peach)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if exists {
                                    Button("Reveal") {
                                        NSWorkspace.shared.activateFileViewerSelecting(
                                            [URL(fileURLWithPath: entry.path)]
                                        )
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                                // A gone file can't be restored, so the button
                                // says what it actually does instead.
                                Button(exists ? "Restore" : "Forget") {
                                    context.delete(entry)
                                    try? context.save()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(exists ? accent : CGTheme.subtext1)
                            }
                        }

                        Text("Restored files reappear after the next rescan.")
                            .font(.caption2)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { card }
                }
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        section("Storage", "Which series take the most disk space",
                systemImage: "internaldrive",
                isOpen: $openStorage,
                badge: analysis.didRunSizes
                    ? ByteCountFormatter.string(fromByteCount: analysis.totalBytes, countStyle: .file)
                    : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(analysis.didRunSizes ? "Refresh" : "Measure") {
                        Task { await analysis.computeSizes(for: items) }
                    }
                    .disabled(analysis.isScanning)
                    Spacer()
                }

                if analysis.didRunSizes {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total: \(ByteCountFormatter.string(fromByteCount: analysis.totalBytes, countStyle: .file))")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(CGTheme.text)

                        ForEach(analysis.sizes.prefix(15)) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(entry.series)
                                        .font(.callout)
                                        .foregroundStyle(CGTheme.text)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(entry.count) · \(entry.formatted)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(CGTheme.subtext0)
                                }
                                ProgressView(
                                    value: Double(entry.bytes),
                                    total: Double(max(analysis.totalBytes, 1))
                                )
                                .tint(accent)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { card }
                }
            }
        }
    }

    // MARK: - Integrity

    private var integritySection: some View {
        section("File integrity", "Finds corrupt, empty, or missing archives",
                systemImage: "checkmark.shield",
                isOpen: $openIntegrity,
                badge: analysis.didRunIntegrity && !analysis.integrityIssues.isEmpty
                    ? "\(analysis.integrityIssues.count)" : nil,
                badgeColor: CGTheme.red) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(analysis.didRunIntegrity ? "Re-check" : "Check Files") {
                        Task { await analysis.checkIntegrity(for: items) }
                    }
                    .disabled(analysis.isScanning)
                    Spacer()
                }

                if analysis.didRunIntegrity {
                    if analysis.integrityIssues.isEmpty {
                        Text("All \(items.count) files opened cleanly.")
                            .font(.callout)
                            .foregroundStyle(CGTheme.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background { card }
                    } else {
                        ForEach(analysis.integrityIssues) { issue in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.item.title)
                                        .font(.callout)
                                        .foregroundStyle(CGTheme.text)
                                        .lineLimit(1)
                                    Text(issue.reason)
                                        .font(.caption)
                                        .foregroundStyle(CGTheme.red)
                                }
                                Spacer()
                                Button("Reveal") {
                                    NSWorkspace.shared.activateFileViewerSelecting(
                                        [URL(fileURLWithPath: issue.item.filePath)]
                                    )
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background { card }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Covers

    private var coversSection: some View {
        section("Covers", "Rebuild thumbnails a cache clean-up removed",
                systemImage: "photo.on.rectangle",
                isOpen: $openCovers) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Rebuild Missing Covers") {
                        Task { await analysis.rebuildMissingCovers(for: items, context: context) }
                    }
                    .disabled(analysis.isScanning)
                    Spacer()
                }

                if let summary = analysis.coverSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext1)
                }

                Text("Thumbnails live in the system cache, which macOS and cleaning tools empty freely. A rescan will not bring them back — it skips files already in the library. This opens every comic whose thumbnail is gone and rebuilds just that one cover, so on a large collection it takes a while. Covers that are already cached are left alone.")
                    .font(.caption2)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { card }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        section("Export library", "A list of everything, for spreadsheets or scripts",
                systemImage: "square.and.arrow.up",
                isOpen: $openExport) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Export CSV…") { exportCSV() }
                    Button("Export JSON…") { exportJSON() }
                    Spacer()
                }
                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext1)
                }
                Text("This is a catalogue, not a backup — use Settings › Backup to save reading progress.")
                    .font(.caption2)
                    .foregroundStyle(CGTheme.subtext0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { card }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ComicGhost-Library.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LibraryAnalysis.csv(for: items).write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Exported \(items.count) issues."
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ComicGhost-Library.json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LibraryAnalysis.json(for: items).write(to: url)
            exportMessage = "Exported \(items.count) issues."
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

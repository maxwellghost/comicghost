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
    @State private var exportMessage: String?

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    private var gaps: [LibraryAnalysis.Gap] { analysis.gaps(in: items) }
    private var duplicates: [LibraryAnalysis.DuplicateGroup] { analysis.duplicates(in: items) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
            exportSection
        }
        .padding()
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(CGTheme.surface0.opacity(glassEnabled ? 0.45 : 0.8))
    }

    private func header(_ title: String, _ subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(CGTheme.text)
                Text(subtitle).font(.caption).foregroundStyle(CGTheme.subtext0)
            }
            Spacer()
        }
    }

    // MARK: - Gaps

    private var gapsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Missing issues", "Gaps in the numbered run of each series",
                   systemImage: "square.dashed")

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

    // MARK: - Duplicates

    private var duplicatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Duplicates", "Same issue present more than once",
                   systemImage: "doc.on.doc")

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

    // MARK: - Ignored files

    private var ignoredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Removed from library",
                   "Files still on disk that scans skip",
                   systemImage: "eye.slash")

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
                        Button("Restore All") {
                            for entry in ignored { context.delete(entry) }
                            try? context.save()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    ForEach(ignored) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.callout)
                                    .foregroundStyle(CGTheme.text)
                                    .lineLimit(1)
                                Text(entry.filename)
                                    .font(.caption)
                                    .foregroundStyle(CGTheme.subtext0)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: entry.path)]
                                )
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            Button("Restore") {
                                context.delete(entry)
                                try? context.save()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(accent)
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

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header("Storage", "Which series take the most disk space",
                       systemImage: "internaldrive")
                Button(analysis.didRunSizes ? "Refresh" : "Measure") {
                    Task { await analysis.computeSizes(for: items) }
                }
                .disabled(analysis.isScanning)
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

    // MARK: - Integrity

    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header("File integrity", "Finds corrupt, empty, or missing archives",
                       systemImage: "checkmark.shield")
                Button(analysis.didRunIntegrity ? "Re-check" : "Check Files") {
                    Task { await analysis.checkIntegrity(for: items) }
                }
                .disabled(analysis.isScanning)
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

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Export library", "A list of everything, for spreadsheets or scripts",
                   systemImage: "square.and.arrow.up")

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

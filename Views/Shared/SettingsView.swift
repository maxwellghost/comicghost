import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ComicLibrary.sortIndex) private var libraries: [ComicLibrary]

    @AppStorage(CGGlass.key) private var glassEnabled: Bool = true
    @AppStorage("restoreWindowState") private var restoreState: Bool = true
    @AppStorage("autoHideChrome") private var autoHideChrome: Bool = true
    @AppStorage("alwaysShowEdges") private var alwaysShowEdges: Bool = false
    @AppStorage("hideReaderControls") private var hideReaderControls: Bool = false
    @AppStorage("showPageCountWhenHidden") private var showPageCountWhenHidden: Bool = true
    @AppStorage("preventSleepWhileReading") private var preventSleep: Bool = true
    @AppStorage(SpotlightIndex.enabledKey) private var spotlightEnabled: Bool = true
    @AppStorage("showEndOfIssueCard") private var showEndCard: Bool = true
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @AppStorage(CGThemeCatalog.key) private var themeID: String = "mocha"

    @State private var renaming: ComicLibrary?
    @State private var newName = ""
    @State private var backupMessage: String?
    @State private var libraryMessage: String?
    @State private var expandedThemeFamilies: Set<String> = []
    /// The whole theme list folds away — the label shows what's active, which
    /// is the only part worth seeing once you've picked one.
    @State private var showThemes = false

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    /// Read through the stored id rather than the catalog's own lookup, so the
    /// collapsed label redraws the moment a theme is picked.
    private var activeTheme: CGThemeDefinition {
        CGThemeCatalog.all.first { $0.id == themeID } ?? CGThemeCatalog.current
    }

    var body: some View {
        Form {
            Section("Libraries") {
                if libraries.isEmpty {
                    Text("No libraries yet.")
                        .foregroundStyle(CGTheme.subtext0)
                }

                ForEach(libraries) { library in
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.name)
                                .foregroundStyle(CGTheme.text)
                            Text(library.path)
                                .font(.caption)
                                .foregroundStyle(CGTheme.subtext0)
                                .truncationMode(.middle)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Rename") {
                            newName = library.name
                            renaming = library
                        }
                        Button("Remove", role: .destructive) {
                            remove(library)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button("Add Library…") { addLibrary() }

                if let libraryMessage {
                    Text(libraryMessage)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }

            Section("Theme") {
                DisclosureGroup(isExpanded: $showThemes) {
                    VStack(alignment: .leading, spacing: 6) {
                        // The active theme's family opens by default; the rest stay
                        // folded so 21 themes don't fill the window.
                        ForEach(CGThemeCatalog.families, id: \.self) { family in
                            themeFamilyRow(family)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text(activeTheme.name)
                            .foregroundStyle(CGTheme.text)
                        Text(activeTheme.family)
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .tint(accent)
            }

            Section("Appearance") {
                Toggle(isOn: $glassEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glass effect")
                        Text("Frosted translucency in the sidebar and around comic pages.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color")
                    HStack(spacing: 10) {
                        ForEach(CGAccent.allCases) { option in
                            Button {
                                accentRaw = option.rawValue
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                accentRaw == option.rawValue ? CGTheme.text : .clear,
                                                lineWidth: 2
                                            )
                                            .padding(-3)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(option.label)
                        }
                    }
                }
            }

            Section("Reader") {
                Toggle(isOn: $autoHideChrome) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-hide reader controls")
                        Text("Fade the page counter and buttons while you read.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                Toggle(isOn: $hideReaderControls) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide reader controls")
                        Text("Keep the page counter and buttons off the page entirely. Toggle with H while reading.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                Toggle(isOn: $showPageCountWhenHidden) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show page count when controls are hidden")
                        Text("Keeps a dimmed page counter on screen once the rest of the chrome goes away. Off means a completely bare page.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
                .disabled(!hideReaderControls && !autoHideChrome)

                Toggle(isOn: $alwaysShowEdges) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always show page-turn arrows")
                        Text("Keep the left and right chevrons faintly visible instead of only on hover.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                Toggle(isOn: $showEndCard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("End-of-issue card")
                        Text("Show series progress and the next issue when you reach the end of one.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
            }

            Section("System") {
                Toggle(isOn: $restoreState) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember where I was")
                        Text("Reopen to the section and series you were last browsing.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                Toggle(isOn: $spotlightEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Index library in Spotlight")
                        Text("Find comics from system search. Turning this off clears the index.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
                .onChange(of: spotlightEnabled) { _, enabled in
                    if !enabled { Task { await SpotlightIndex.clear() } }
                }

                Toggle(isOn: $preventSleep) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep the display awake while reading")
                        Text("Stops the screen dimming mid-page.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
            }
            Section("Backup") {
                Text("Reading progress, ratings, favorites, labels, bookmarks, and collections live only in this app — not in your comic files. Export keeps a copy.")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Export Backup…") { exportBackup() }
                    Button("Restore from Backup…") { importBackup() }
                    Spacer()
                }

                if let backupMessage {
                    Text(backupMessage)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 660, height: 620)
        .background(CGTheme.base)
        .sheet(item: $renaming) { library in
            renameSheet(library)
        }
        .onAppear {
            LibraryIngest.shared.migrateLegacyFolderIfNeeded(context: context)
        }
    }

    private func renameSheet(_ library: ComicLibrary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Library").font(.headline).foregroundStyle(CGTheme.text)
            TextField("Name", text: $newName).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    let clean = newName.trimmingCharacters(in: .whitespaces)
                    if !clean.isEmpty {
                        library.name = clean
                        try? context.save()
                    }
                    renaming = nil
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(CGTheme.base)
    }

    private func isFamilyExpanded(_ family: String) -> Bool {
        expandedThemeFamilies.contains(family) || currentFamily == family
    }

    private var currentFamily: String {
        CGThemeCatalog.all.first { $0.id == themeID }?.family ?? ""
    }

    private func themeFamilyRow(_ family: String) -> some View {
        let themes = CGThemeCatalog.themes(in: family)
        let expanded = isFamilyExpanded(family)
        let isCurrent = currentFamily == family

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if expandedThemeFamilies.contains(family) {
                        expandedThemeFamilies.remove(family)
                    } else {
                        expandedThemeFamilies.insert(family)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CGTheme.subtext0)
                        .rotationEffect(.degrees(expanded ? 90 : 0))

                    Text(family)
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? CGTheme.text : CGTheme.subtext1)

                    // Colour preview so a folded family still reads at a glance.
                    HStack(spacing: 3) {
                        ForEach(themes) { theme in
                            Circle()
                                .fill(Color(hex: theme.mauve))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.leading, 2)

                    Spacer()

                    if isCurrent {
                        Text(CGThemeCatalog.all.first { $0.id == themeID }?.name ?? "")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(themes) { theme in
                        themeSwatch(theme)
                    }
                }
                .padding(.leading, 18)
                .padding(.bottom, 4)
            }
        }
    }

    /// Preview card: surfaces on the left, accents as dots on the right.
    private func themeSwatch(_ theme: CGThemeDefinition) -> some View {
        let isSelected = themeID == theme.id

        return Button {
            themeID = theme.id
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: theme.base))
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(hex: theme.surface1), lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color(hex: theme.mauve))
                            .frame(width: 12, height: 12)
                            .padding(3)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.name)
                        .font(.callout)
                        .foregroundStyle(CGTheme.text)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        ForEach([theme.red, theme.peach, theme.green, theme.sky, theme.lavender], id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 6, height: 6)
                        }
                        Text(theme.isDark ? "Dark" : "Light")
                            .font(.system(size: 9))
                            .foregroundStyle(CGTheme.subtext0)
                            .padding(.leading, 2)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(CGTheme.surface0.opacity(isSelected ? 0.8 : 0.35))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? accent : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// Presents a file panel as its own window.
    ///
    /// Two things this avoids. `runModal()` is unreliable from inside the
    /// Settings scene — the panel can be torn down in the frame it appears,
    /// which reads as a flicker and silently returns .cancel. And attaching a
    /// sheet to a guessed host window can land it on the main library window
    /// behind Settings, where the panel is genuinely open but invisible.
    ///
    /// `begin` needs no host at all, and the floating level keeps it in front.
    private func presentPanel(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .floating
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = BackupService.suggestedFilename()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"

        presentPanel(panel) { url in
            guard let url else { return }
            do {
                let payload = BackupService.makePayload(context: context)
                try BackupService.encode(payload).write(to: url)
                backupMessage = "Exported \(payload.items.count) issues, \(payload.labels.count) labels, and \(payload.collections.count) collections."
            } catch {
                backupMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Restore"

        presentPanel(panel) { url in
            guard let url else { return }
            do {
                let payload = try BackupService.decode(Data(contentsOf: url))
                let result = BackupService.restore(payload, context: context)
                var parts = ["Restored \(result.matched) issues"]
                if result.missing > 0 { parts.append("\(result.missing) not found in this library") }
                if result.labelsCreated > 0 { parts.append("\(result.labelsCreated) labels added") }
                if result.collectionsCreated > 0 { parts.append("\(result.collectionsCreated) collections added") }
                backupMessage = parts.joined(separator: " · ")
            } catch {
                backupMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }

    private func addLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Library"

        presentPanel(panel) { url in
            guard let url else { return }

            // Adding the same folder twice would double every issue in it.
            let existing = libraries.first {
                $0.path == url.path
                    || URL(fileURLWithPath: $0.path).standardizedFileURL == url.standardizedFileURL
            }
            if let existing {
                libraryMessage = "\(existing.name) is already a library."
                return
            }

            // The bookmark has to be made while the panel's grant is live.
            guard let bookmark = LibraryFolder.bookmark(for: url) else {
                libraryMessage = "Couldn't get permission to read that folder."
                return
            }

            let library = ComicLibrary(
                name: url.lastPathComponent,
                path: url.path,
                bookmark: bookmark,
                sortIndex: libraries.count
            )
            context.insert(library)
            try? context.save()

            libraryMessage = "Scanning \(library.name)…"
            Task {
                await LibraryIngest.shared.sync(library: library, context: context)
                libraryMessage = "Added \(library.name)."
                try? await Task.sleep(for: .seconds(3))
                libraryMessage = nil
            }
        }
    }

    /// Removing a library drops its items from the app. Files are untouched.
    private func remove(_ library: ComicLibrary) {
        let items = ((try? context.fetch(FetchDescriptor<LibraryItem>())) ?? [])
            .filter { $0.libraryID == library.id }
        for item in items {
            if let progress = item.progress { context.delete(progress) }
            context.delete(item)
        }
        context.delete(library)
        try? context.save()
    }
}

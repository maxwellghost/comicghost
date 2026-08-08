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
    @AppStorage("hiddenLibraryIDs") private var hiddenLibraryIDsRaw: String = ""
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @AppStorage(CGThemeCatalog.key) private var themeID: String = "mocha"

    @State private var renaming: ComicLibrary?
    @State private var newName = ""
    @State private var backupMessage: String?
    @State private var libraryMessage: String?
    @State private var removalProgress: Double?
    @AppStorage(UpdateChecker.enabledKey) private var checkForUpdates: Bool = false
    @AppStorage(ArchiveSupport.cacheLimitKey) private var pageCacheLimit: Int = ArchiveSupport.defaultCacheLimit
    @State private var cacheBytes: Int64 = 0
    private let updates = UpdateChecker.shared
    @State private var expandedThemeFamilies: Set<String> = []
    /// The whole theme list folds away — the label shows what's active, which
    /// is the only part worth seeing once you've picked one.
    @State private var showThemes = false

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    private var hiddenLibraryIDs: Set<UUID> {
        Set(hiddenLibraryIDsRaw.split(separator: "\n").compactMap { UUID(uuidString: String($0)) })
    }

    /// Hiding is a view preference, so nothing is written to the library itself
    /// and nothing about the folder or its comics changes.
    private func setHidden(_ hidden: Bool, for library: ComicLibrary) {
        var ids = hiddenLibraryIDs
        if hidden { ids.insert(library.id) } else { ids.remove(library.id) }
        hiddenLibraryIDsRaw = ids.map(\.uuidString).sorted().joined(separator: "\n")
    }

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
                    let isHidden = hiddenLibraryIDs.contains(library.id)
                    HStack(spacing: 10) {
                        Image(systemName: isHidden ? "eye.slash" : "folder")
                            .foregroundStyle(isHidden ? CGTheme.subtext0 : accent)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(library.name)
                                    .foregroundStyle(CGTheme.text)
                                if isHidden {
                                    Text("HIDDEN")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(CGTheme.crust)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(CGTheme.subtext0, in: Capsule())
                                }
                            }
                            Text(library.path)
                                .font(.caption)
                                .foregroundStyle(CGTheme.subtext0)
                                .truncationMode(.middle)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(isHidden ? "Show" : "Hide") {
                            setHidden(!isHidden, for: library)
                        }
                        Button("Rename") {
                            newName = library.name
                            renaming = library
                        }
                        Button("Remove", role: .destructive) {
                            remove(library)
                        }
                    }
                    .opacity(isHidden ? 0.55 : 1)
                    .padding(.vertical, 2)
                    .disabled(removalProgress != nil)
                }

                Button("Add Library…") { addLibrary() }
                    .disabled(removalProgress != nil)

                if let removalProgress {
                    ProgressView(value: removalProgress)
                        .progressViewStyle(.linear)
                        .tint(accent)
                }

                Text("Hiding a library leaves everything in place — the folder, the files, and all your reading progress, ratings, and labels. It just stops appearing anywhere in the app until you show it again.")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)

                if let libraryMessage {
                    Text(libraryMessage)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }

            Section("Updates") {
                Toggle(isOn: $checkForUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for new versions")
                        Text("Asks GitHub once a day whether a newer release exists, and shows a badge in the title bar if one does. This is the only time Comic Ghost uses the network. Nothing about your library is sent, and nothing downloads or installs on its own.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
                .onChange(of: checkForUpdates) { _, isOn in
                    // Turning it on should answer the question immediately
                    // rather than waiting for tomorrow's launch.
                    if isOn {
                        Task { await updates.check() }
                    } else {
                        updates.forget()
                    }
                }

                HStack {
                    Text("Version \(updates.currentVersion)")
                        .foregroundStyle(CGTheme.subtext0)
                    Spacer()
                    if updates.isChecking {
                        Text("Checking…")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    } else if let latest = updates.availableVersion {
                        Button("Get \(latest)") {
                            NSWorkspace.shared.open(updates.releasesPage)
                        }
                    } else {
                        Button("Check Now") {
                            Task { await updates.check() }
                        }
                    }
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

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Keep unpacked pages", selection: $pageCacheLimit) {
                        Text("Don't keep any").tag(0)
                        Text("Up to 2 GB").tag(2_000_000_000)
                        Text("Up to 5 GB").tag(5_000_000_000)
                        Text("Up to 10 GB").tag(10_000_000_000)
                        Text("Up to 20 GB").tag(20_000_000_000)
                    }
                    Text("Opening a comic unpacks it to a temporary folder. Keeping those pages makes reopening instant instead of unpacking again, which takes 10-20 seconds on a large omnibus. The comic you have open is never removed; past that, the least recently read go first.")
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(cacheUsageLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CGTheme.subtext1)
                        Spacer()
                        Button("Clear Now") { clearPageCache() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                .onChange(of: pageCacheLimit) { _, _ in
                    Task.detached(priority: .utility) { ArchiveSupport.enforceCacheLimit() }
                }
                .task { refreshCacheUsage() }
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

            // Adding a folder means wanting what is in it. Comics removed from
            // an earlier library are remembered by path so rescans keep skipping
            // them, which would otherwise make a freshly added folder come up
            // short or empty with nothing on screen explaining why. Choosing the
            // folder is explicit enough to override that; ordinary rescans still
            // honour the ignore list.
            let restored = forgetIgnoredFiles(under: url)

            let library = ComicLibrary(
                name: url.lastPathComponent,
                path: url.path,
                bookmark: bookmark,
                sortIndex: libraries.count
            )
            context.insert(library)
            try? context.save()

            let name = library.name
            libraryMessage = "Scanning \(name)…"
            Task {
                await LibraryIngest.shared.sync(library: library, context: context)
                if restored > 0 {
                    let noun = restored == 1 ? "comic" : "comics"
                    libraryMessage = "Added \(name), including \(restored) previously removed \(noun)."
                } else {
                    libraryMessage = "Added \(name)."
                }
                try? await Task.sleep(for: .seconds(3))
                libraryMessage = nil
            }
        }
    }

    /// Drops ignore records for anything inside `folder`. Comics removed from
    /// the library are remembered by path, with no reference to the library they
    /// came from, so those records outlive the library itself and would keep a
    /// re-added folder from loading. Returns how many were forgotten.
    @MainActor
    private func forgetIgnoredFiles(under folder: URL) -> Int {
        let root = folder.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"

        let ignored = ((try? context.fetch(FetchDescriptor<IgnoredFile>())) ?? [])
        let inside = ignored.filter {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path.hasPrefix(prefix)
        }
        for entry in inside {
            context.delete(entry)
        }
        return inside.count
    }

    /// Removing a library drops its items from the app. Files are untouched.
    private func remove(_ library: ComicLibrary) {
        guard removalProgress == nil else { return }

        // Capture what's needed before anything is deleted. Reading a property
        // off `library` after context.delete invalidates the object, and SwiftUI
        // will happily render this row once more before the query catches up.
        let targetID = library.id
        let name = library.name

        setHidden(false, for: library)
        removalProgress = 0
        libraryMessage = "Removing \(name)…"

        Task { @MainActor in
            // Hand the run loop one turn so the progress row paints before the
            // store work takes the actor back.
            await Task.yield()

            let orphanedIDs = deleteFromStore(libraryID: targetID)
            await purgeThumbnails(orphanedIDs)

            removalProgress = nil
            libraryMessage = "Removed \(name)."
            try? await Task.sleep(for: .seconds(3))
            libraryMessage = nil
        }
    }

    /// The whole store side in one go, deliberately without a suspension point.
    /// Yielding partway would let SwiftUI render a LibraryItem that has been
    /// deleted but not yet saved, and reading an invalidated model is fatal.
    /// Returns the ids whose cached thumbnails are now orphaned.
    @MainActor
    private func deleteFromStore(libraryID targetID: UUID) -> [UUID] {
        // Filter in the query, not in Swift. Fetching the whole table and
        // discarding most of it materialises the entire library to delete part
        // of it, which is fine at a hundred comics and ruinous at a hundred
        // thousand.
        let doomed = ((try? context.fetch(
            FetchDescriptor<LibraryItem>(
                predicate: #Predicate { $0.libraryID == targetID }
            )
        )) ?? [])
        let doomedIDs = doomed.map(\.id)
        let doomedSet = Set(doomedIDs)

        // Bookmarks point at comics by id with no relationship behind them, so
        // nothing removes them automatically. Matching against the doomed set
        // in Swift beats a predicate here — an IN clause holding every deleted
        // id would be worse than scanning what is normally a small table.
        let bookmarks = ((try? context.fetch(FetchDescriptor<Bookmark>())) ?? [])
        for bookmark in bookmarks where doomedSet.contains(bookmark.itemID) {
            context.delete(bookmark)
        }

        // Reading progress cascades off LibraryItem, so saving snapshots every
        // progress row the deletes drag in. A row that was never read is still
        // a fault — SwiftData calls that backing a future and traps on it
        // rather than snapshotting it, which is what crashed every removal
        // before. Touching the relationship loads it. Only the doomed items'
        // rows are needed, so this stays proportional to what is being removed.
        for item in doomed {
            _ = item.progress?.currentPage
            context.delete(item)
        }

        var descriptor = FetchDescriptor<ComicLibrary>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        if let library = (try? context.fetch(descriptor))?.first {
            context.delete(library)
        }
        try? context.save()

        return doomedIDs
    }

    private var cacheUsageLabel: String {
        cacheBytes == 0
            ? "Nothing unpacked right now"
            : "\(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)) unpacked"
    }

    private func refreshCacheUsage() {
        Task.detached(priority: .utility) {
            let bytes = ArchiveSupport.directorySize(of: ArchiveSupport.workingRoot)
            await MainActor.run { cacheBytes = bytes }
        }
    }

    /// Clearing while a comic is open would delete the pages it is displaying,
    /// so this drops everything the reader is not currently using.
    private func clearPageCache() {
        Task.detached(priority: .utility) {
            ArchiveSupport.evictAll()
            let bytes = ArchiveSupport.directorySize(of: ArchiveSupport.workingRoot)
            await MainActor.run { cacheBytes = bytes }
        }
    }

    /// Thumbnail files are plain filesystem work with no model involved, so this
    /// runs off the main actor. Awaiting each batch lets the window redraw, which
    /// is what actually keeps the bar moving. Runs after the save, so a failed
    /// save leaves the thumbnails intact.
    @MainActor
    private func purgeThumbnails(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let batchSize = 100
        var done = 0

        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let batch = Array(ids[start..<min(start + batchSize, ids.count)])
            await Task.detached(priority: .utility) {
                for id in batch {
                    try? FileManager.default.removeItem(
                        at: ThumbnailGenerator.cachedPath(for: id)
                    )
                }
            }.value
            done += batch.count
            removalProgress = Double(done) / Double(ids.count)
        }
    }
}

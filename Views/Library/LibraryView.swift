import SwiftUI
import SwiftData

enum LibraryFilter: String, CaseIterable, Identifiable {
    case library = "Library"
    case new = "New"
    case inProgress = "In Progress"
    case readingList = "Reading List"
    case favorites = "Favorites"
    case completed = "Completed"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .library: return "books.vertical"
        case .new: return "sparkles"
        case .inProgress: return "book"
        case .readingList: return "text.badge.plus"
        case .favorites: return "heart"
        case .completed: return "checkmark.seal"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "Title"
    case dateAdded = "Date Added"
    case recentlyRead = "Recently Read"
    case unreadFirst = "Unread First"
    case rating = "Rating"

    var id: String { rawValue }
}

enum CoverSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var minWidth: CGFloat {
        switch self {
        case .small: return 110
        case .medium: return 160
        case .large: return 220
        }
    }

    var maxWidth: CGFloat { minWidth + 50 }

    var coverHeight: CGFloat {
        switch self {
        case .small: return 150
        case .medium: return 210
        case .large: return 290
        }
    }
}

/// What the detail pane is currently showing.
enum LibraryRoute: Hashable {
    case filter(LibraryFilter)
    case series(String)
    case collection(UUID)
    case label(UUID)
    case stats
    case tools
    case notes
    case bookmarks
    case imports
    case index
    /// Everything credited to one person, character, arc, publisher or genre.
    case facet(String, String)
}

struct GlassBackdrop: View {
    let imagePath: String?
    var tint: Color
    var blur: CGFloat = 80
    var artOpacity: Double = 0.35

    var body: some View {
        GeometryReader { geo in
            ZStack {
                tint
                if let imagePath, let image = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: blur, opaque: true)
                        .opacity(artOpacity)
                        .clipped()
                }
                Rectangle().fill(.ultraThinMaterial)
                tint.opacity(0.4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    private let updates = UpdateChecker.shared
    @Query(sort: \LibraryItem.dateAdded, order: .reverse) private var allItems: [LibraryItem]
    /// Libraries hidden from view, stored as ids one per line. Kept as a
    /// preference rather than a field on the library so nothing about the
    /// stored data changes — hiding is a view state, not a property of the
    /// folder.
    @AppStorage("hiddenLibraryIDs") private var hiddenLibraryIDsRaw: String = ""
    @Query(sort: \SmartCollection.sortIndex) private var collections: [SmartCollection]
    @Query(sort: \ComicLibrary.sortIndex) private var libraries: [ComicLibrary]
    @Query(sort: \ComicLabel.sortIndex) private var allLabels: [ComicLabel]
    @Query(sort: \ComicLabel.sortIndex) private var labels: [ComicLabel]

    @AppStorage(CGGlass.key) private var glassEnabled: Bool = true
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    /// Read so a theme change re-renders this view tree.
    @AppStorage(CGThemeCatalog.key) private var themeID: String = "mocha"
    @AppStorage("librarySort") private var sortRaw: String = LibrarySort.title.rawValue
    @AppStorage("coverSize") private var coverSizeRaw: String = CoverSize.medium.rawValue
    @AppStorage("useListView") private var useListView: Bool = false
    @AppStorage("restoreWindowState") private var restoreState: Bool = true
    @AppStorage("lastRoute") private var lastRouteRaw: String = ""
    @AppStorage("seriesExpanded") private var seriesExpanded: Bool = true
    /// Which franchise and series nodes are open, newline-separated so the tree
    /// survives relaunch without a model of its own.
    @AppStorage("expandedTreeNodes") private var expandedNodesRaw: String = ""
    @AppStorage("shelfRecentExpanded") private var recentExpanded: Bool = true
    @AppStorage("shelfContinueExpanded") private var continueExpanded: Bool = true

    @State private var route: LibraryRoute = .filter(.library)
    @State private var openedItem: LibraryItem?
    @State private var searchQuery = ""
    @State private var ingest = LibraryIngest.shared
    @State private var renameTarget: Series?
    @State private var mergeSource: Series?
    @State private var editingCollection: SmartCollection?
    @State private var creatingCollection = false
    @State private var didRestore = false
    @State private var collapsedSections: Set<String> = []
    @State private var selectedLibraryID: UUID?
    @State private var scanTarget: ComicLibrary?
    @State private var showLabelManager = false
    @State private var keyboardSelection: UUID?
    /// Multi-selection. Issues and series never render in the same collection,
    /// so only one of these is ever non-empty.
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectedSeriesNames: Set<String> = []
    /// Where a Shift-click range starts from.
    @State private var itemAnchor: UUID?
    @State private var seriesAnchor: String?
    /// Explicit selection mode: a plain click picks instead of opening.
    @State private var selectionMode = false
    @State private var showBulkTrashConfirm = false
    /// Insights sits below the longest scroll in the sidebar, so it folds.
    @AppStorage("sidebarShowInsights") private var showInsights: Bool = true
    @State private var openAtEnd = false
    @State private var pendingBookmarkPage: Int?
    @State private var showPalette = false
    @State private var fieldEdit: SeriesFieldEdit?
    @State private var renameNodeKind: TreeNode.Kind?
    @State private var renameNodeOld: String?
    @State private var groupRenameDraft = ""
    @AppStorage("groupByPublisher") private var groupByPublisher: Bool = true
    @State private var keyMonitor: Any?
    @State private var openRequests = OpenRequests.shared
    @State private var isDropTargeted = false
    @State private var dropMessage: String?

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .title }
    private var coverSize: CoverSize { CoverSize(rawValue: coverSizeRaw) ?? .medium }

    // MARK: - Hidden libraries

    private var hiddenLibraryIDs: Set<UUID> {
        Set(hiddenLibraryIDsRaw.split(separator: "\n").compactMap { UUID(uuidString: String($0)) })
    }

    /// Libraries you can actually see, in sidebar order.
    private var visibleLibraries: [ComicLibrary] {
        let hidden = hiddenLibraryIDs
        return libraries.filter { !hidden.contains($0.id) }
    }

    /// Everything except comics belonging to a hidden library.
    ///
    /// The whole view reads from this rather than the raw query, so hiding a
    /// library empties it out of the grid, the sidebar tree, every count,
    /// search, stats, tools, the dock badge, and Spotlight in one move.
    private var items: [LibraryItem] {
        let hidden = hiddenLibraryIDs
        guard !hidden.isEmpty else { return allItems }
        return allItems.filter { item in
            guard let id = item.libraryID else { return true }
            return !hidden.contains(id)
        }
    }

    private var activeFilter: LibraryFilter {
        if case .filter(let f) = route { return f }
        return .library
    }

    var body: some View {
        ZStack {
            if let openedItem {
                ReaderView(
                    item: openedItem,
                    onClose: {
                        pendingBookmarkPage = nil
                        withAnimation(.easeInOut(duration: 0.3)) { self.openedItem = nil }
                    },
                    onOpenNext: { next in
                        openAtEnd = false
                        pendingBookmarkPage = nil
                        withAnimation(.easeInOut(duration: 0.3)) { self.openedItem = next }
                    },
                    onOpenPrevious: { previous in
                        openAtEnd = true
                        pendingBookmarkPage = nil
                        withAnimation(.easeInOut(duration: 0.3)) { self.openedItem = previous }
                    },
                    startAtEnd: openAtEnd,
                    startAtPage: pendingBookmarkPage
                )
                .id(openedItem.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                browser.transition(.opacity)
            }
        }
        .background(CGTheme.base)
        .overlay {
            if showPalette {
                CommandPalette(entries: paletteEntries, isPresented: $showPalette)
                    .transition(.opacity)
            }
        }
        .background {
            Button("") { showPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        }
        .sheet(item: $fieldEdit) { edit in
            SeriesGroupSheet(
                field: edit.field,
                seriesName: edit.displayName,
                issueCount: edit.items.count,
                existingGroups: edit.field == .publisher
                    ? existingPublishers
                    : existingSeriesGroups,
                currentGroup: edit.current,
                scopeDescription: edit.scopeDescription,
                onApply: { value in
                    applyFieldEdit(edit, value: value)
                    fieldEdit = nil
                },
                onCancel: { fieldEdit = nil }
            )
        }
        .sheet(isPresented: Binding(
            get: { renameNodeOld != nil },
            set: { if !$0 { renameNodeOld = nil } }
        )) {
            VStack(alignment: .leading, spacing: 16) {
                Text(renameNodeKind == .publisher ? "Rename Publisher" : "Rename Series Group")
                    .font(.headline)
                    .foregroundStyle(CGTheme.text)
                TextField("Name", text: $groupRenameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitGroupRename() }
                Text("Applies to every issue currently under it. Your files aren't modified.")
                    .font(.caption2)
                    .foregroundStyle(CGTheme.subtext0)
                HStack {
                    Spacer()
                    Button("Cancel") { renameNodeOld = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Rename") { commitGroupRename() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(CGTheme.base)
        }
        .onAppear {
            restoreIfEnabled()
            startKeyMonitor()
        }
        .onDisappear { stopKeyMonitor() }
        .onChange(of: items.count) { _, _ in refreshSystemIntegration() }
        .onChange(of: openRequests.pendingPaths) { _, _ in consumePendingOpens() }
        .onChange(of: openRequests.pendingItemID) { _, _ in consumePendingItem() }
        .task { refreshSystemIntegration() }
        .onChange(of: route) { _, newValue in persist(newValue) }
        .task {
            ingest.migrateLegacyFolderIfNeeded(context: context)
            await ingest.syncAll(context: context)
        }
        .sheet(item: $renameTarget) { series in
            SeriesRenameSheet(series: series) { newName in applyRename(series, to: newName) }
        }
        .sheet(item: $mergeSource) { series in
            SeriesMergeSheet(
                source: series,
                candidates: allSeries.map(\.name).filter { $0 != series.name }
            ) { target in applyRename(series, to: target) }
        }
        .sheet(item: $scanTarget) { library in
            FolderScanSheet(library: library) { folder in
                Task { await ingest.sync(library: library, subfolder: folder, context: context) }
            }
        }
        .sheet(isPresented: $showLabelManager) {
            LabelManager()
        }
        .sheet(isPresented: $creatingCollection) {
            SmartCollectionEditor(existing: nil, previewItems: items)
        }
        .sheet(item: $editingCollection) { collection in
            SmartCollectionEditor(existing: collection, previewItems: items)
        }
    }

    // MARK: - Route persistence

    private func persist(_ route: LibraryRoute) {
        switch route {
        case .filter(let f): lastRouteRaw = "filter:\(f.rawValue)"
        case .series(let name): lastRouteRaw = "series:\(name)"
        case .collection(let id): lastRouteRaw = "collection:\(id.uuidString)"
        case .label(let id): lastRouteRaw = "label:\(id.uuidString)"
        case .stats: lastRouteRaw = "stats"
        case .tools: lastRouteRaw = "tools"
        case .notes: lastRouteRaw = "notes"
        case .bookmarks: lastRouteRaw = "bookmarks"
        case .imports: lastRouteRaw = "imports"
        case .index: lastRouteRaw = "index"
        case .facet(let kind, let value): lastRouteRaw = "facet:\(kind)|\(value)"
        }
    }

    private func restoreIfEnabled() {
        guard restoreState, !didRestore else { return }
        didRestore = true
        let parts = lastRouteRaw.split(separator: ":", maxSplits: 1).map(String.init)
        let bare: Set<String> = ["stats", "tools", "notes", "bookmarks", "imports", "index"]
        guard parts.count == 2 || bare.contains(lastRouteRaw) else { return }
        if lastRouteRaw == "stats" { route = .stats; return }
        if lastRouteRaw == "tools" { route = .tools; return }
        if lastRouteRaw == "notes" { route = .notes; return }
        if lastRouteRaw == "bookmarks" { route = .bookmarks; return }
        if lastRouteRaw == "imports" { route = .imports; return }
        if lastRouteRaw == "index" { route = .index; return }
        switch parts[0] {
        case "filter":
            if let f = LibraryFilter(rawValue: parts[1]) { route = .filter(f) }
        case "series":
            route = .series(parts[1])
        case "collection":
            if let id = UUID(uuidString: parts[1]) { route = .collection(id) }
        case "facet":
            let pieces = parts[1].split(separator: "|", maxSplits: 1).map(String.init)
            if pieces.count == 2 { route = .facet(pieces[0], pieces[1]) }
        case "label":
            if let id = UUID(uuidString: parts[1]) { route = .label(id) }
        default: break
        }
    }

    private func applyRename(_ series: Series, to newName: String) {
        SeriesActions.move(series.items, from: series.name, to: newName)
        if case .series(let current) = route, current == series.name {
            route = .series(newName.trimmingCharacters(in: .whitespaces))
        }
        try? context.save()
    }

    // MARK: - Command palette

    /// Series, issues, and the handful of actions worth reaching by keyboard.
    private var paletteEntries: [CommandPalette.Entry] {
        var entries: [CommandPalette.Entry] = []

        entries.append(contentsOf: [
            CommandPalette.Entry(kind: .action, title: "Scan All Libraries",
                                 subtitle: "Look for new comics", symbol: "arrow.clockwise") {
                Task { await ingest.syncAll(context: context) }
            },
            CommandPalette.Entry(kind: .action, title: "Recent Import",
                                 subtitle: "Review the last batch", symbol: "tray.and.arrow.down") {
                route = .imports
            },
            CommandPalette.Entry(kind: .action, title: "Bookmarks",
                                 subtitle: nil, symbol: "bookmark") { route = .bookmarks },
            CommandPalette.Entry(kind: .action, title: "Notes",
                                 subtitle: nil, symbol: "note.text") { route = .notes },
            CommandPalette.Entry(kind: .action, title: "Index",
                                 subtitle: "Creators, characters, arcs", symbol: "person.2") {
                route = .index
            },
            CommandPalette.Entry(kind: .action, title: "Stats",
                                 subtitle: nil, symbol: "chart.bar") { route = .stats },
            CommandPalette.Entry(kind: .action, title: "Library Tools",
                                 subtitle: "Gaps, duplicates, integrity", symbol: "wrench.and.screwdriver") {
                route = .tools
            },
            CommandPalette.Entry(kind: .action, title: "Reading List",
                                 subtitle: nil, symbol: "text.badge.plus") {
                route = .filter(.readingList)
            },
            CommandPalette.Entry(kind: .action, title: "Random Unread",
                                 subtitle: "Open something at random", symbol: "shuffle") {
                openRandomUnread()
            },
        ])

        for series in allSeries {
            let unreadSuffix = series.nextUnread.map { " · next: \($0.title)" } ?? ""
            entries.append(
                CommandPalette.Entry(
                    kind: .series(series.name),
                    title: series.name,
                    subtitle: "\(series.items.count) issues" + unreadSuffix,
                    symbol: "square.stack"
                ) { route = .series(series.name) }
            )

            if let next = series.nextUnread {
                entries.append(
                    CommandPalette.Entry(
                        kind: .issue(next),
                        title: "Continue \(series.name)",
                        subtitle: next.title,
                        symbol: "play.fill"
                    ) {
                        openAtEnd = false
                        pendingBookmarkPage = nil
                        withAnimation(.easeInOut(duration: 0.3)) { openedItem = next }
                    }
                )
            }
        }

        for item in items {
            entries.append(
                CommandPalette.Entry(
                    kind: .issue(item),
                    title: item.title,
                    subtitle: item.seriesKey,
                    symbol: "book"
                ) {
                    openAtEnd = false
                    pendingBookmarkPage = nil
                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
                }
            )
        }

        return entries
    }

    // MARK: - macOS integration

    private var dropOverlay: some View {
        ZStack {
            CGTheme.crust.opacity(0.55)
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 40))
                    .foregroundStyle(accent)
                Text("Drop comics to add them")
                    .font(.headline)
                    .foregroundStyle(CGTheme.text)
                if let library = activeLibrary {
                    Text("They'll be copied into \(library.name)")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                } else {
                    Text("Add a library in Settings first")
                        .font(.callout)
                        .foregroundStyle(CGTheme.red)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func handleDrop(_ urls: [URL]) {
        let comics = urls.filter { ComicArchive.Format(fileExtension: $0.pathExtension) != nil }
        guard !comics.isEmpty else {
            flashDropMessage("Those aren't comic files.")
            return
        }

        let result = DropImport.handle(
            paths: comics.map(\.path),
            into: activeLibrary,
            context: context
        )

        if let first = result.opened.first, result.copied == 0 {
            openAtEnd = false
            withAnimation(.easeInOut(duration: 0.3)) { openedItem = first }
            return
        }

        var parts: [String] = []
        if result.copied > 0 { parts.append("Added \(result.copied)") }
        if !result.opened.isEmpty { parts.append("\(result.opened.count) already in library") }
        if result.skipped > 0 { parts.append("\(result.skipped) skipped") }
        flashDropMessage(parts.joined(separator: " · "))

        if result.copied > 0, let library = activeLibrary {
            Task { await ingest.sync(library: library, context: context) }
        }
    }

    private func flashDropMessage(_ text: String) {
        withAnimation { dropMessage = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { dropMessage = nil }
        }
    }

    /// Opens files handed over by Finder, "Open With", or Spotlight.
    private func consumePendingOpens() {
        let paths = openRequests.pendingPaths
        guard !paths.isEmpty else { return }
        openRequests.pendingPaths = []

        let byPath = Dictionary(items.map { ($0.filePath, $0) }, uniquingKeysWith: { a, _ in a })
        var target = paths.compactMap { byPath[$0] }.first

        // Not in any watched folder — register it so it can still be read.
        if target == nil, let first = paths.first {
            target = DropImport.adopt(path: first, context: context)
        }

        guard let target else { return }
        openAtEnd = false
        withAnimation(.easeInOut(duration: 0.3)) { openedItem = target }
    }

    private func consumePendingItem() {
        guard let id = openRequests.pendingItemID else { return }
        openRequests.pendingItemID = nil
        guard let item = items.first(where: { $0.id == id }) else { return }
        openAtEnd = false
        withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
    }

    private func refreshSystemIntegration() {
        DockBadge.update(newCount: items.filter { $0.status == .new }.count)
        let snapshot = items
        Task { await SpotlightIndex.index(snapshot) }
    }

    private func openRandomUnread() {
        var candidates = items.filter { $0.status == .new || $0.status == .unread }
        if candidates.isEmpty { candidates = items.filter { $0.status != .completed } }
        if candidates.isEmpty { candidates = items }
        guard let pick = candidates.randomElement() else { return }
        withAnimation(.easeInOut(duration: 0.3)) { openedItem = pick }
    }

    // MARK: - Browser

    private var browser: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack(alignment: .bottom) {
                ScrollView { content }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // An inset rather than an overlay, so the bar never sits on
                    // top of a sticky section header.
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if hasSelection || selectionMode { selectionBar }
                    }

                if ingest.isImporting { importBanner }
            }
            .background {
                if glassEnabled {
                    GlassBackdrop(imagePath: backdropPath, tint: CGTheme.base, blur: 90, artOpacity: 0.3)
                } else {
                    CGTheme.base
                }
            }
            .navigationTitle(detailTitle)
            .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search comics")
            .toolbar { toolbarContent }
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted { dropOverlay }
            }
            .animation(.easeOut(duration: 0.18), value: hasSelection)
            .animation(.easeOut(duration: 0.18), value: selectionMode)
            // Escape only exists while there's something to dismiss, so it
            // can't swallow the key from the search field the rest of the time.
            .background {
                if hasSelection || selectionMode {
                    Button("") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            clearSelection()
                            selectionMode = false
                        }
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                }
            }
            .onChange(of: route) { _, _ in clearSelection() }
            .onChange(of: searchQuery) { _, _ in clearSelection() }
            // Hiding the library you were browsing would otherwise leave you
            // staring at an empty grid with no way to tell why.
            .onChange(of: hiddenLibraryIDsRaw) { _, _ in
                if let id = selectedLibraryID, hiddenLibraryIDs.contains(id) {
                    selectedLibraryID = nil
                }
                clearSelection()
            }
            .confirmationDialog(
                "Move \(selectedItems.count) \(selectedItems.count == 1 ? "file" : "files") to the Trash?",
                isPresented: $showBulkTrashConfirm,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    removeFromLibrary(selectedItems, context: context)
                    clearSelection()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The files leave your library and go to the Trash, where you can still recover them. This is the one bulk action Cmd+Z won't undo.")
            }
            .overlay(alignment: .bottom) {
                if let dropMessage {
                    Text(dropMessage)
                        .font(.callout)
                        .foregroundStyle(CGTheme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle, cornerRadius: 10)
                        .softGlow(accent, radius: 8)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if searchQuery.isEmpty, backDestination != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if let dest = backDestination { route = dest }
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            if case .collection(let id) = route,
               let collection = collections.first(where: { $0.id == id }) {
                Button {
                    editingCollection = collection
                } label: {
                    Label("Edit collection", systemImage: "slider.horizontal.3")
                }
            }

            if activeFilter == .readingList, !readingQueue.isEmpty, isFilterRoute {
                Menu {
                    Button("Remove Finished") {
                        ReadingListActions.pruneCompleted(items)
                        try? context.save()
                    }
                    Button("Clear Reading List", role: .destructive) {
                        ReadingListActions.clear(items)
                        try? context.save()
                    }
                } label: {
                    Label("Reading list", systemImage: "ellipsis.circle")
                }
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    selectionMode.toggle()
                    if !selectionMode { clearSelection() }
                }
            } label: {
                Label(selectionMode ? "Done selecting" : "Select",
                      systemImage: selectionMode ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .help(selectionMode
                  ? "Leave selection mode"
                  : "Click covers to select them (or Cmd-click any time)")

            Button { openRandomUnread() } label: {
                Label("Read something", systemImage: "shuffle")
            }
            .help("Open a random unread issue")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    // A dot on the cog, the way an unread count sits on an app
                    // icon. Points at where the detail lives without spending a
                    // toolbar slot or explaining itself in the title bar.
                    .overlay(alignment: .topTrailing) {
                        if updates.availableVersion != nil {
                            Circle()
                                .fill(CGTheme.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -2)
                        }
                    }
            }
            .help(
                updates.availableVersion.map { "Version \($0) is available. Settings (⌘,)" }
                    ?? "Settings (⌘,)"
            )

            // View, cover size and sort are all "how the grid looks", so they
            // share one menu instead of three toolbar slots.
            Menu {
                Picker("Layout", selection: $useListView) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(false)
                    Label("List", systemImage: "list.bullet").tag(true)
                }
                .pickerStyle(.inline)

                if !useListView {
                    Picker("Cover size", selection: $coverSizeRaw) {
                        ForEach(CoverSize.allCases) { size in
                            Text(size.label).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Picker("Sort by", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("View", systemImage: useListView ? "list.bullet" : "square.grid.2x2")
            }
            .help("Layout, cover size and sort order")

            Menu {
                Button("Rescan All Libraries") {
                    Task { await ingest.syncAll(context: context) }
                }
                if let library = activeLibrary {
                    Button("Rescan \(library.name)") {
                        Task { await ingest.sync(library: library, context: context) }
                    }
                    Button("Scan One Folder…") { scanTarget = library }
                }
                Divider()
                Button("Refresh Titles & Series") {
                    ingest.refreshMetadata(context: context, library: activeLibrary)
                }
                if case .series(let name) = route {
                    Button("Refresh Titles in \(name)") {
                        refreshCurrentSeries(name)
                    }
                }
            } label: {
                Label("Library actions", systemImage: "arrow.clockwise")
            } primaryAction: {
                Task { await ingest.syncAll(context: context) }
            }
        }
    }

    /// Where the toolbar back button goes from the current route.
    private var backDestination: LibraryRoute? {
        switch route {
        case .series:
            return .filter(activeFilter)
        default:
            return nil
        }
    }

    private var activeLibrary: ComicLibrary? {
        if let selectedLibraryID {
            return libraries.first { $0.id == selectedLibraryID }
        }
        return libraries.count == 1 ? libraries.first : nil
    }

    /// Re-parses just the files belonging to one series.
    private func refreshCurrentSeries(_ name: String) {
        let members = scopedItems.filter { $0.seriesKey == name }
        guard let sample = members.first,
              let libraryID = sample.libraryID,
              let library = libraries.first(where: { $0.id == libraryID }) else { return }
        // Narrow to the common parent folder of those files.
        let folder = URL(fileURLWithPath: sample.filePath).deletingLastPathComponent()
        ingest.refreshMetadata(context: context, library: library, subfolder: folder)
    }

    private var isFilterRoute: Bool {
        if case .filter = route { return true }
        return false
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !searchQuery.isEmpty {
            if searchResults.isEmpty {
                GhostEmptyState(
                    title: "No results for “\(searchQuery)”",
                    message: "Try a different title or series name.",
                    accent: accent
                )
            } else {
                issueCollection(for: searchResults)
            }
        } else {
            switch route {
            case .stats:
                StatsView(items: scopedItems)

            case .tools:
                LibraryToolsView(items: scopedItems) { item in
                    openAtEnd = false
                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
                }

            case .notes:
                NotesView(items: items) { item in
                    openAtEnd = false
                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
                }

            case .bookmarks:
                BookmarksView(items: items) { item, page in
                    openAtEnd = false
                    pendingBookmarkPage = page
                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
                }

            case .imports:
                ImportReviewView(items: items) { item in
                    openAtEnd = false
                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
                }

            case .index:
                CreditsIndexView(items: scopedItems) { facet, value in
                    route = .facet(facet.rawValue, value)
                }

            case .facet(let kind, let value):
                let matched = sortItems(facetItems(kind: kind, value: value))
                if matched.isEmpty {
                    GhostEmptyState(
                        title: "Nothing here",
                        message: "No comics are credited to \(value).",
                        accent: accent
                    )
                } else {
                    issueCollection(for: matched)
                }

            case .collection(let id):
                if let collection = collections.first(where: { $0.id == id }) {
                    let matched = sortItems(collection.matches(items))
                    if matched.isEmpty {
                        GhostEmptyState(
                            title: "Nothing matches",
                            message: "No issues fit “\(collection.name)” right now. Edit the rules from the toolbar.",
                            accent: accent
                        )
                    } else {
                        issueCollection(for: matched)
                    }
                } else {
                    GhostEmptyState(title: "Collection not found", message: "", accent: accent)
                }

            case .label(let id):
                let labelItems = sortItems(scopedItems.filter { $0.hasLabel(id) })
                if labelItems.isEmpty {
                    GhostEmptyState(
                        title: "Nothing labelled yet",
                        message: "Right-click any comic and use the Labels menu to attach this one.",
                        accent: accent
                    )
                } else {
                    issueCollection(for: labelItems)
                }

            case .series(let name):
                if let series = allSeries.first(where: { $0.name == name }) {
                    seriesDetail(series)
                } else {
                    GhostEmptyState(title: "Series not found", message: "", accent: accent)
                }

            case .filter(let f):
                filterContent(f)
            }
        }
    }

    @ViewBuilder
    private func filterContent(_ f: LibraryFilter) -> some View {
        if f == .readingList {
            readingListContent
        } else if topLevelGroups.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if f == .library, !continueReading.isEmpty { continueShelf }
                if f == .library, !recentlyAdded.isEmpty { recentlyAddedShelf }
                seriesGrid(topLevelGroups)
            }
        }
    }

    @ViewBuilder
    private func seriesDetail(_ series: Series) -> some View {
        let mainKey = "\(series.name)#main"
        let specialKey = "\(series.name)#specials"

        LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
            if !series.mainRun.isEmpty {
                Section {
                    if !collapsedSections.contains(mainKey) {
                        issueCollection(for: sortItems(series.mainRun))
                    }
                } header: {
                    sectionHeader(series.name, count: series.mainRun.count,
                                  symbol: "books.vertical", key: mainKey)
                }
            }
            if !series.specials.isEmpty {
                Section {
                    if !collapsedSections.contains(specialKey) {
                        issueCollection(for: sortItems(series.specials))
                    }
                } header: {
                    sectionHeader("Specials", count: series.specials.count,
                                  symbol: "star.square", tint: CGTheme.peach, key: specialKey)
                }
            }
        }
    }

    private func toggleSection(_ key: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            if collapsedSections.contains(key) {
                collapsedSections.remove(key)
            } else {
                collapsedSections.insert(key)
            }
        }
    }

    private func sectionHeader(
        _ title: String, count: Int, symbol: String,
        tint: Color = CGTheme.subtext1, key: String
    ) -> some View {
        let isCollapsed = collapsedSections.contains(key)

        return Button {
            toggleSection(key)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CGTheme.subtext0)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.headline).foregroundStyle(CGTheme.subtext1).lineLimit(1)
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(CGTheme.subtext0)
                Spacer()
                if isCollapsed {
                    Text("Show")
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background {
                if glassEnabled {
                    Rectangle().fill(.ultraThinMaterial)
                } else {
                    Rectangle().fill(CGTheme.base)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reading list

    private var readingQueue: [LibraryItem] {
        items.filter(\.isQueued)
            .sorted { ($0.readingListOrder ?? 0) < ($1.readingListOrder ?? 0) }
    }

    @ViewBuilder
    private var readingListContent: some View {
        if readingQueue.isEmpty {
            GhostEmptyState(
                title: "Reading list is empty",
                message: "Right-click any comic or series and choose “Add to Reading List” to queue it up.",
                accent: accent
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                    .padding(.horizontal)

                List {
                    ForEach(readingQueue) { item in
                        queueRow(item).listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        ReadingListActions.reorder(readingQueue, from: source, to: destination)
                        try? context.save()
                    }
                    .onDelete { offsets in
                        for index in offsets { ReadingListActions.remove(readingQueue[index]) }
                        try? context.save()
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 500)
            }
            .padding(.top, 10)
        }
    }

    private func queueRow(_ item: LibraryItem) -> some View {
        HStack(spacing: 12) {
            Group {
                if let path = item.coverThumbnailPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(CGTheme.surface0)
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.callout).foregroundStyle(CGTheme.text).lineLimit(1)
                Text(item.seriesKey).font(.caption).foregroundStyle(CGTheme.subtext0).lineLimit(1)
                if item.status == .completed {
                    Text("Finished").font(.caption2).foregroundStyle(CGTheme.green)
                } else if item.status == .inProgress, let progress = item.progress {
                    Text("Page \(progress.currentPage + 1) of \(item.pageCount)")
                        .font(.caption2).foregroundStyle(CGTheme.sky)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
            } label: {
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(accent)
            }
            .buttonStyle(.plain)

            Button {
                ReadingListActions.remove(item)
                try? context.save()
            } label: {
                Image(systemName: "xmark.circle").foregroundStyle(CGTheme.subtext0)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var detailTitle: String {
        if !searchQuery.isEmpty { return "Search" }
        switch route {
        case .stats: return "Stats"
        case .tools: return "Library Tools"
        case .notes: return "Notes"
        case .bookmarks: return "Bookmarks"
        case .imports: return "Recent Import"
        case .index: return "Index"
        case .facet(_, let value): return value
        case .label(let id): return labels.first { $0.id == id }?.name ?? "Label"
        case .series(let name): return name
        case .collection(let id):
            return collections.first(where: { $0.id == id })?.name ?? "Collection"
        case .filter(let f): return f == .library ? "Comic Ghost" : f.rawValue
        }
    }

    private var backdropPath: String? {
        if case .series(let name) = route,
           let series = allSeries.first(where: { $0.name == name }) {
            return series.coverPath
        }
        return filteredItems.first?.coverThumbnailPath ?? items.first?.coverThumbnailPath
    }

    // MARK: - Continue reading

    private var continueReading: [LibraryItem] {
        items.filter { $0.status == .inProgress }
            .sorted {
                ($0.progress?.lastReadDate ?? .distantPast) > ($1.progress?.lastReadDate ?? .distantPast)
            }
            .prefix(10).map { $0 }
    }

    /// Newest imports, so a fresh batch is one click from the top.
    private var recentlyAdded: [LibraryItem] {
        let cutoff = Date.now.addingTimeInterval(-60 * 60 * 24 * 30)
        return scopedItems
            .filter { $0.dateAdded > cutoff }
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(12)
            .map { $0 }
    }

    private var recentlyAddedShelf: some View {
        shelf(
            title: "Recently added",
            count: recentlyAdded.count,
            isExpanded: $recentExpanded,
            items: recentlyAdded
        )
    }

    private var continueShelf: some View {
        shelf(
            title: "Continue reading",
            count: continueReading.count,
            isExpanded: $continueExpanded,
            items: continueReading
        )
    }

    /// Horizontal cover shelf with a collapsible header.
    private func shelf(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        items shelfItems: [LibraryItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CGTheme.subtext0)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(CGTheme.subtext1)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                    Spacer()
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(shelfItems) { item in continueCell(item) }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.top, 10)
    }

    private func continueCell(_ item: LibraryItem) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let path = item.coverThumbnailPath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        SkeletonBox(cornerRadius: 6)
                    }
                }
                .frame(width: 110, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(CGTheme.surface0, lineWidth: 1)
                }

                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(CGTheme.text)
                    .lineLimit(2)
                    .frame(width: 110, alignment: .leading)

                if let progress = item.progress {
                    ProgressView(
                        value: Double(progress.currentPage + 1),
                        total: Double(max(item.pageCount, 1))
                    )
                    .tint(CGTheme.sky)
                    .frame(width: 110)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var importBanner: some View {
        VStack(spacing: 6) {
            HStack {
                ProgressView().controlSize(.small)
                Text(ingest.scopeLabel.isEmpty
                     ? "Importing \(ingest.processed) of \(ingest.total)"
                     : "\(ingest.scopeLabel): \(ingest.processed) of \(ingest.total)")
                    .font(.callout).foregroundStyle(CGTheme.text)
                Spacer()
            }
            ProgressView(value: ingest.progress).tint(accent)
            Text(ingest.currentFileName)
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: 420)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle, cornerRadius: 12)
        .softGlow(accent, radius: 8)
        .padding(.bottom, 20)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if visibleLibraries.count > 1 {
                    sidebarLabel("Libraries")
                    libraryRow(nil, name: "All Libraries", count: items.count)
                    ForEach(visibleLibraries) { library in
                        libraryRow(
                            library.id,
                            name: library.name,
                            count: items.filter { $0.libraryID == library.id }.count
                        )
                    }
                    Spacer().frame(height: 10)
                }

                sidebarLabel("Library")
                ForEach(LibraryFilter.allCases) { f in filterRow(f) }

                if !collections.isEmpty {
                    HStack {
                        sidebarLabel("Collections")
                        Spacer()
                        Button { creatingCollection = true } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                                .foregroundStyle(CGTheme.subtext0)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                    }
                    .padding(.top, 10)

                    ForEach(collections) { collection in
                        collectionRow(collection)
                    }
                } else {
                    sidebarLabel("Collections").padding(.top, 10)
                    Button { creatingCollection = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle").frame(width: 18)
                            Text("New collection")
                            Spacer()
                        }
                        .font(.body)
                        .foregroundStyle(CGTheme.subtext0)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                labelsSection

                seriesSection

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showInsights.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        sidebarLabel("Insights")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CGTheme.subtext0)
                            .rotationEffect(.degrees(showInsights ? 90 : 0))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                if showInsights {
                    statsRow
                    toolsRow
                    notesRow
                    bookmarksRow
                    importsRow
                    indexRow
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 220)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle)
    }

    /// Favorite labels get their own rows; the rest live behind Manage.
    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sidebarLabel("Labels")
                Spacer()
                Button { showLabelManager = true } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }

            if allLabels.isEmpty {
                Button { showLabelManager = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "tag").frame(width: 18)
                        Text("New label")
                        Spacer()
                    }
                    .font(.body)
                    .foregroundStyle(CGTheme.subtext0)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(sortedLabels) { label in
                    labelRow(label)
                }
            }
        }
        .padding(.top, 10)
    }

    private var sortedLabels: [ComicLabel] {
        allLabels.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func labelRow(_ label: ComicLabel) -> some View {
        let isSelected: Bool = {
            if case .label(let id) = route { return id == label.id }
            return false
        }()
        let count = scopedItems.filter { $0.hasLabel(label.id) }.count

        return Button {
            route = .label(label.id)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(label.color)
                    .frame(width: 10, height: 10)
                    .frame(width: 18)
                if label.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(CGTheme.peach)
                }
                Text(label.name).lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(label.isFavorite ? "Unfavorite Label" : "Favorite Label") {
                label.isFavorite.toggle()
                try? context.save()
            }
            Button("Manage Labels…") { showLabelManager = true }
        }
    }

    /// Collapsible list of every series, for direct navigation.
    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { seriesExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: seriesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("SERIES")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(allSeries.count)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0.opacity(0.6))
                    Spacer()
                }
                .foregroundStyle(CGTheme.subtext0.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Toggle("Group by Publisher", isOn: $groupByPublisher)
            }

            if seriesExpanded {
                ForEach(visibleTreeRows) { row in
                    treeRowView(row)
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Series groups and publishers

    /// What a Set Series Group / Set Publisher sheet is currently editing.
    /// Carries the items directly so it works for one series or a whole node.
    struct SeriesFieldEdit: Identifiable {
        let id = UUID()
        let field: SeriesGroupSheet.Field
        let displayName: String
        let items: [LibraryItem]
        let current: String?
        /// Set when the target is a hand-picked selection rather than a series.
        var scopeDescription: String? = nil
    }

    private var existingPublishers: [String] {
        Set(items.compactMap(\.publisherName))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The single agreed value across a set of issues, or nil when they differ.
    private func agreedValue(_ values: [String?]) -> String? {
        let set = Set(values.compactMap { $0 })
        return set.count == 1 ? set.first : nil
    }

    private func applyFieldEdit(_ edit: SeriesFieldEdit, value: String?) {
        for item in edit.items {
            switch edit.field {
            case .seriesGroup: item.seriesGroupName = value
            case .publisher: item.publisherName = value
            }
        }
        try? context.save()

        if let value, edit.field == .seriesGroup {
            expandPath(toGroupNamed: value)
        }
    }


    private var existingSeriesGroups: [String] {
        Set(items.compactMap(\.seriesGroupName))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The group a series belongs to, when its issues agree on one.
    private func currentGroup(of series: Series) -> String? {
        let groups = Set(series.items.compactMap(\.seriesGroupName))
        return groups.count == 1 ? groups.first : nil
    }

    /// Expands a franchise and every node above it.
    ///
    /// Ids are full paths now, so the node can't be guessed by name — it has to
    /// be found in the freshly rebuilt tree.
    private func expandPath(toGroupNamed name: String) {
        var set = expandedNodes

        func walk(_ nodes: [TreeNode], ancestors: [String]) {
            for node in nodes {
                if node.kind == .group, node.name == name {
                    for ancestor in ancestors { set.insert(ancestor) }
                    set.insert(node.id)
                }
                walk(node.children, ancestors: ancestors + [node.id])
            }
        }

        walk(seriesTree, ancestors: [])
        expandedNodesRaw = set.sorted().joined(separator: "\n")
    }

    private func renameSeriesGroup(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        for item in items where item.seriesGroupName == old {
            item.seriesGroupName = trimmed
        }
        try? context.save()
    }

    private func commitGroupRename() {
        let trimmed = groupRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let old = renameNodeOld, !trimmed.isEmpty, trimmed != old {
            switch renameNodeKind {
            case .publisher:
                for item in items where item.publisherName == old {
                    item.publisherName = trimmed
                }
                try? context.save()
            default:
                renameSeriesGroup(old, to: trimmed)
            }
        }
        renameNodeOld = nil
        renameNodeKind = nil
    }

    private func ungroupAll(_ group: String) {
        for item in items where item.seriesGroupName == group {
            item.seriesGroupName = nil
        }
        try? context.save()
    }

    @ViewBuilder
    private func seriesContextMenu(_ series: Series) -> some View {
        if let next = series.nextUnread {
            Button {
                openAtEnd = false
                pendingBookmarkPage = nil
                withAnimation(.easeInOut(duration: 0.3)) { openedItem = next }
            } label: {
                Label("Continue: \(next.title)", systemImage: "play.fill")
            }
            Divider()
        }

        Button {
            fieldEdit = SeriesFieldEdit(
                field: .seriesGroup,
                displayName: series.name,
                items: series.items,
                current: currentGroup(of: series)
            )
        } label: {
            Label(currentGroup(of: series) == nil ? "Set Series Group…" : "Change Series Group…",
                  systemImage: "square.stack")
        }

        Button {
            fieldEdit = SeriesFieldEdit(
                field: .publisher,
                displayName: series.name,
                items: series.items,
                current: agreedValue(series.items.map(\.publisherName))
            )
        } label: {
            Label("Set Publisher…", systemImage: "building.2")
        }

        Button { renameTarget = series } label: {
            Label("Rename Series…", systemImage: "pencil")
        }

        Divider()

        Button {
            for item in series.items { StatusActions.markRead(item, context: context) }
            try? context.save()
        } label: {
            Label("Mark All as Read", systemImage: "checkmark.circle")
        }

        Button {
            for item in series.items { StatusActions.markUnread(item, context: context) }
            try? context.save()
        } label: {
            Label("Mark All as Unread", systemImage: "circle")
        }
    }

    // MARK: - Tree expansion

    /// Expanded node ids, persisted so the tree survives relaunch.
    /// Ids are full paths, so the same series under a different parent is a
    /// distinct node with its own state.
    private var expandedNodes: Set<String> {
        Set(expandedNodesRaw.split(separator: "\n").map(String.init))
    }

    private func isExpanded(_ id: String) -> Bool {
        expandedNodes.contains(id)
    }

    private func toggleExpanded(_ id: String) {
        var set = expandedNodes
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        expandedNodesRaw = set.sorted().joined(separator: "\n")
    }

    // MARK: - Series tree

    /// One node in the sidebar tree: publisher, franchise, or series.
    ///
    /// Flattened into rows before rendering rather than built recursively —
    /// a recursive ViewBuilder can't type-check itself, and a flat ForEach
    /// keeps a 1,400-issue library from rebuilding nested stacks.
    struct TreeNode: Identifiable {
        enum Kind: String { case publisher, group, series }

        let kind: Kind
        let name: String
        let children: [TreeNode]
        /// Set only when kind == .series.
        let series: Series?
        /// Unique across kinds — "Marvel" the publisher and "Marvel" the
        /// franchise must not share an id or ForEach renders one twice.
        let id: String

        var issues: [LibraryItem] {
            if let series { return series.items }
            return children.flatMap(\.issues)
        }

        var unreadCount: Int {
            issues.filter { $0.status != .completed }.count
        }

        var symbol: String? {
            switch kind {
            case .publisher: return "building.2"
            case .group: return "square.stack"
            case .series: return nil
            }
        }
    }

    private enum TreeRow: Identifiable {
        case node(LibraryView.TreeNode, Int)
        case issue(LibraryItem, Int)

        var id: String {
            switch self {
            case .node(let node, _): return node.id
            case .issue(let item, let depth): return "issue:\(depth):\(item.id.uuidString)"
            }
        }
    }

    /// Builds the franchise + series levels for one set of series.
    private func groupLevel(_ list: [Series], pathPrefix: String) -> [TreeNode] {
        var grouped: [String: [Series]] = [:]
        var ungrouped: [Series] = []

        for series in list {
            // A series joins a franchise only if its issues agree on one.
            let groups = Set(series.items.compactMap(\.seriesGroupName))
            if groups.count == 1, let group = groups.first {
                grouped[group, default: []].append(series)
            } else {
                ungrouped.append(series)
            }
        }

        func seriesNode(_ series: Series, prefix: String) -> TreeNode {
            TreeNode(kind: .series, name: series.name, children: [],
                     series: series, id: prefix + "series:" + series.name)
        }

        // A franchise is usually named after its flagship series; absorb it so
        // "Dragon Ball" doesn't sit beside a "Dragon Ball" group holding only Z.
        var loose: [TreeNode] = []
        for series in ungrouped {
            if grouped[series.name] != nil {
                grouped[series.name]?.append(series)
            } else {
                loose.append(seriesNode(series, prefix: pathPrefix))
            }
        }

        var franchises: [TreeNode] = []
        for (name, children) in grouped {
            let sorted = children.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            // A group holding only its own namesake adds a level for nothing.
            if sorted.count == 1, let only = sorted.first, only.name == name {
                loose.append(seriesNode(only, prefix: pathPrefix))
                continue
            }
            let groupPath = pathPrefix + "group:" + name + "/"
            franchises.append(
                TreeNode(
                    kind: .group,
                    name: name,
                    children: sorted.map { seriesNode($0, prefix: groupPath) },
                    series: nil,
                    id: pathPrefix + "group:" + name
                )
            )
        }

        return (franchises + loose)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Top of the tree. Publishers when enabled and known, franchises and
    /// series otherwise.
    private var seriesTree: [TreeNode] {
        guard groupByPublisher else { return groupLevel(allSeries, pathPrefix: "") }

        var byPublisher: [String: [Series]] = [:]
        var unknown: [Series] = []

        for series in allSeries {
            let publishers = Set(series.items.compactMap(\.publisherName))
            if publishers.count == 1, let publisher = publishers.first {
                byPublisher[publisher, default: []].append(series)
            } else {
                unknown.append(series)
            }
        }

        let publishers = byPublisher.map { name, list -> TreeNode in
            let prefix = "publisher:" + name + "/"
            return TreeNode(
                kind: .publisher,
                name: name,
                children: groupLevel(list, pathPrefix: prefix),
                series: nil,
                id: "publisher:" + name
            )
        }

        // Series with no publisher sit at the top rather than under a bucket
        // called "Unknown" — the library shouldn't invent a label.
        return (publishers + groupLevel(unknown, pathPrefix: ""))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The tree as a flat list of visible rows, honouring what's expanded.
    private var visibleTreeRows: [TreeRow] {
        var rows: [TreeRow] = []

        func walk(_ nodes: [TreeNode], depth: Int) {
            for node in nodes {
                rows.append(.node(node, depth))
                guard isExpanded(node.id) else { continue }
                if let series = node.series {
                    for item in sortItems(series.items) {
                        rows.append(.issue(item, depth + 1))
                    }
                } else {
                    walk(node.children, depth: depth + 1)
                }
            }
        }

        walk(seriesTree, depth: 0)
        return rows
    }

    private func indent(for depth: Int) -> CGFloat {
        12 + CGFloat(depth) * 13
    }

    @ViewBuilder
    private func treeRowView(_ row: TreeRow) -> some View {
        switch row {
        case .issue(let item, let depth):
            issueRow(item, indent: indent(for: depth) + 10)

        case .node(let node, let depth):
            if let series = node.series {
                seriesRow(series, nodeID: node.id, indent: indent(for: depth))
                    .contextMenu { seriesContextMenu(series) }
            } else {
                disclosureRow(
                    title: node.name,
                    count: node.unreadCount,
                    indent: indent(for: depth),
                    isOpen: isExpanded(node.id),
                    isSelected: false,
                    symbol: node.symbol,
                    onToggle: {
                        withAnimation(.easeOut(duration: 0.16)) { toggleExpanded(node.id) }
                    }
                )
                .contextMenu { nodeContextMenu(node) }
            }
        }
    }

    @ViewBuilder
    private func nodeContextMenu(_ node: TreeNode) -> some View {
        Button {
            renameNodeKind = node.kind
            renameNodeOld = node.name
            groupRenameDraft = node.name
        } label: {
            Label(node.kind == .publisher ? "Rename Publisher…" : "Rename Group…",
                  systemImage: "pencil")
        }

        if node.kind == .group {
            Button {
                fieldEdit = SeriesFieldEdit(
                    field: .publisher,
                    displayName: node.name,
                    items: node.issues,
                    current: agreedValue(node.issues.map(\.publisherName))
                )
            } label: {
                Label("Set Publisher…", systemImage: "building.2")
            }
        }

        Divider()

        Button {
            for item in node.issues { StatusActions.markRead(item, context: context) }
            try? context.save()
        } label: {
            Label("Mark All as Read", systemImage: "checkmark.circle")
        }

        Button {
            for item in node.issues { StatusActions.markUnread(item, context: context) }
            try? context.save()
        } label: {
            Label("Mark All as Unread", systemImage: "circle")
        }

        if node.kind == .group {
            Divider()
            Button(role: .destructive) {
                ungroupAll(node.name)
            } label: {
                Label("Ungroup \(node.children.count) Series", systemImage: "rectangle.split.3x1")
            }
        }
    }

    /// Chevron plus label. Tapping the chevron opens; tapping the label runs
    /// `onSelect` when there is one, so expanding never costs you a navigation.
    private func disclosureRow(
        title: String,
        count: Int,
        indent: CGFloat,
        isOpen: Bool,
        isSelected: Bool,
        symbol: String? = nil,
        onToggle: @escaping () -> Void,
        onSelect: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CGTheme.subtext0.opacity(0.8))
                    .frame(width: 12, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if let onSelect { onSelect() } else { onToggle() }
            } label: {
                HStack(spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 10))
                            .foregroundStyle(CGTheme.subtext0.opacity(0.8))
                    }
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
        .padding(.leading, indent)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
        }
    }

    private func issueRow(_ item: LibraryItem, indent: CGFloat) -> some View {
        Button {
            openAtEnd = false
            pendingBookmarkPage = nil
            withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(item.status == .completed ? CGTheme.subtext0.opacity(0.35) : accent)
                    .frame(width: 5, height: 5)
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .font(.caption)
            .foregroundStyle(CGTheme.subtext0)
            .padding(.leading, indent)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func seriesRow(_ series: Series, nodeID: String, indent: CGFloat) -> some View {
        let isSelected: Bool = {
            if case .series(let name) = route { return name == series.name }
            return false
        }()
        let unread = series.items.filter { $0.status != .completed }.count

        return disclosureRow(
            title: series.name,
            count: unread,
            indent: indent,
            isOpen: isExpanded(nodeID),
            isSelected: isSelected,
            onToggle: {
                withAnimation(.easeOut(duration: 0.16)) { toggleExpanded(nodeID) }
            },
            onSelect: { route = .series(series.name) }
        )
    }

    private func collectionRow(_ collection: SmartCollection) -> some View {
        let isSelected: Bool = {
            if case .collection(let id) = route { return id == collection.id }
            return false
        }()
        let count = collection.matches(items).count

        return Button {
            route = .collection(collection.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: collection.icon)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text(collection.name).lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit…") { editingCollection = collection }
            Button("Delete", role: .destructive) {
                context.delete(collection)
                try? context.save()
            }
        }
    }

    private func libraryRow(_ id: UUID?, name: String, count: Int) -> some View {
        let isSelected = selectedLibraryID == id
        return Button {
            selectedLibraryID = id
            route = .filter(.library)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: id == nil ? "square.stack.3d.up" : "folder")
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text(name).lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let id, let library = libraries.first(where: { $0.id == id }) {
                Button("Rescan This Library") {
                    Task { await ingest.sync(library: library, context: context) }
                }
                Button("Refresh Titles in This Library") {
                    ingest.refreshMetadata(context: context, library: library)
                }
                Divider()
                Button("Scan One Folder…") { scanTarget = library }
            }
        }
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CGTheme.subtext0.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
    }

    private func filterRow(_ f: LibraryFilter) -> some View {
        let isSelected: Bool = {
            if case .filter(let current) = route { return current == f }
            return false
        }()
        let count = count(for: f)

        return Button {
            route = .filter(f)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: f.icon)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text(f.rawValue)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var statsRow: some View {
        let isSelected = route == .stats
        return Button {
            route = .stats
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar")
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text("Stats")
                Spacer()
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func insightsRow(_ title: String,
                             symbol: String,
                             target: LibraryRoute) -> some View {
        let isSelected = route == target
        return Button {
            route = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text(title)
                Spacer()
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var indexRow: some View {
        insightsRow("Index", symbol: "person.2", target: .index)
    }

    /// Items matching one index entry.
    private func facetItems(kind: String, value: String) -> [LibraryItem] {
        let facet = CreditsIndexView.Facet(rawValue: kind)
        return scopedItems.filter { item in
            switch facet {
            case .creator:
                return item.creators.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            case .character:
                return (item.characters + item.teams)
                    .contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            case .storyArc:
                return item.storyArcName?.caseInsensitiveCompare(value) == .orderedSame
            case .publisher:
                return item.publisherName?.caseInsensitiveCompare(value) == .orderedSame
            case .genre:
                return item.genres.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            case nil:
                return false
            }
        }
    }

    private var bookmarksRow: some View {
        insightsRow("Bookmarks", symbol: "bookmark", target: .bookmarks)
    }

    private var importsRow: some View {
        insightsRow("Recent Import", symbol: "tray.and.arrow.down", target: .imports)
    }

    private var notesRow: some View {
        let isSelected = route == .notes
        return Button {
            route = .notes
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text("Notes")
                Spacer()
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var toolsRow: some View {
        let isSelected = route == .tools
        return Button {
            route = .tools
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : CGTheme.subtext1)
                Text("Library Tools")
                Spacer()
            }
            .font(.body)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func count(for f: LibraryFilter) -> Int {
        switch f {
        case .library: return 0
        case .new: return items.filter { $0.status == .new }.count
        case .inProgress: return items.filter { $0.status == .inProgress }.count
        case .readingList: return items.filter(\.isQueued).count
        case .favorites: return items.filter(\.isFavorite).count
        case .completed: return items.filter { $0.status == .completed }.count
        }
    }

    /// Items in the active library (or all libraries when none is selected).
    private var scopedItems: [LibraryItem] {
        guard let selectedLibraryID else { return items }
        return items.filter { $0.libraryID == selectedLibraryID }
    }

    private var filteredItems: [LibraryItem] {
        let items = scopedItems
        switch activeFilter {
        case .library: return items
        case .new: return items.filter { $0.status == .new }
        case .inProgress: return items.filter { $0.status == .inProgress }
        case .readingList: return items.filter(\.isQueued)
        case .favorites: return items.filter(\.isFavorite)
        case .completed: return items.filter { $0.status == .completed }
        }
    }

    private var searchResults: [LibraryItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return sortItems(items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.seriesKey.localizedCaseInsensitiveContains(query)
        })
    }

    /// Series scoped to the active sidebar filter (used by the grid).
    private var seriesList: [Series] {
        Dictionary(grouping: filteredItems, by: \.seriesKey)
            .map { Series(name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every series in the active library (used by the sidebar list).
    private var allSeries: [Series] {
        Dictionary(grouping: scopedItems, by: \.seriesKey)
            .map { Series(name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Top-level groups in the grid — one tile per series.
    private var topLevelGroups: [Series] {
        Dictionary(grouping: filteredItems, by: \.seriesKey)
            .map { Series(name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func sortItems(_ list: [LibraryItem]) -> [LibraryItem] {
        switch sort {
        case .title:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            return list.sorted { $0.dateAdded > $1.dateAdded }
        case .recentlyRead:
            return list.sorted {
                ($0.progress?.lastReadDate ?? .distantPast) > ($1.progress?.lastReadDate ?? .distantPast)
            }
        case .unreadFirst:
            return list.sorted {
                let a = statusRank($0), b = statusRank($1)
                if a != b { return a < b }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .rating:
            return list.sorted {
                if $0.rating != $1.rating { return $0.rating > $1.rating }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    private func statusRank(_ item: LibraryItem) -> Int {
        switch item.status {
        case .new, .unread: return 0
        case .inProgress: return 1
        case .completed: return 2
        }
    }

    // MARK: - Multi-selection
    //
    // Cmd-click toggles, Shift-click extends from the last pick, and a plain
    // click still opens — unless Select mode is on, in which case a plain click
    // picks instead. Issue cells and series cards never render in the same
    // collection, so a selection is only ever one kind at a time.

    private enum ClickIntent { case open, toggle, range }

    private func clickIntent() -> ClickIntent {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .toggle }
        if flags.contains(.shift) { return .range }
        return selectionMode ? .toggle : .open
    }

    private var hasSelection: Bool {
        !selectedItemIDs.isEmpty || !selectedSeriesNames.isEmpty
    }

    /// Whichever selection is active, resolved to the issues it covers.
    /// A series selection is simply every issue in those series.
    private var selectedItems: [LibraryItem] {
        if !selectedSeriesNames.isEmpty {
            return items.filter { selectedSeriesNames.contains($0.seriesKey) }
        }
        return items.filter { selectedItemIDs.contains($0.id) }
    }

    private func clearSelection() {
        selectedItemIDs.removeAll()
        selectedSeriesNames.removeAll()
        itemAnchor = nil
        seriesAnchor = nil
    }

    private func handleIssueTap(_ item: LibraryItem, in list: [LibraryItem]) {
        switch clickIntent() {
        case .open:
            clearSelection()
            keyboardSelection = item.id
            openAtEnd = false
            withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }

        case .toggle:
            selectedSeriesNames.removeAll()
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
            itemAnchor = item.id
            keyboardSelection = item.id

        case .range:
            selectedSeriesNames.removeAll()
            let anchorID = itemAnchor ?? keyboardSelection ?? item.id
            if let start = list.firstIndex(where: { $0.id == anchorID }),
               let end = list.firstIndex(where: { $0.id == item.id }) {
                for index in min(start, end)...max(start, end) {
                    selectedItemIDs.insert(list[index].id)
                }
            } else {
                selectedItemIDs.insert(item.id)
            }
            keyboardSelection = item.id
        }
    }

    private func handleSeriesTap(_ series: Series, in list: [Series]) {
        switch clickIntent() {
        case .open:
            clearSelection()
            withAnimation(.easeInOut(duration: 0.22)) { route = .series(series.name) }

        case .toggle:
            selectedItemIDs.removeAll()
            if selectedSeriesNames.contains(series.name) {
                selectedSeriesNames.remove(series.name)
            } else {
                selectedSeriesNames.insert(series.name)
            }
            seriesAnchor = series.name

        case .range:
            selectedItemIDs.removeAll()
            let anchorName = seriesAnchor ?? series.name
            if let start = list.firstIndex(where: { $0.name == anchorName }),
               let end = list.firstIndex(where: { $0.name == series.name }) {
                for index in min(start, end)...max(start, end) {
                    selectedSeriesNames.insert(list[index].name)
                }
            } else {
                selectedSeriesNames.insert(series.name)
            }
        }
    }

    private func selectAllVisible() {
        if !selectedSeriesNames.isEmpty
            || (!navigableSeries.isEmpty && selectedItemIDs.isEmpty) {
            selectedItemIDs.removeAll()
            selectedSeriesNames = Set(navigableSeries.map(\.name))
        } else {
            selectedSeriesNames.removeAll()
            selectedItemIDs = Set(navigableItems.map(\.id))
        }
    }

    /// Corner badge that makes membership readable at a glance, and makes
    /// Select mode discoverable by showing empty circles before you click.
    /// List rows use the row fill instead — a badge there covers the cover.
    @ViewBuilder
    private func selectionBadge(isSelected: Bool) -> some View {
        if isSelected || selectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? accent : CGTheme.subtext0)
                .background(Circle().fill(CGTheme.base).padding(2))
                .padding(6)
                .transition(.opacity)
        }
    }

    private var selectionScopeDescription: String {
        let count = selectedItems.count
        if !selectedSeriesNames.isEmpty {
            let seriesCount = selectedSeriesNames.count
            return "Applies to \(count) \(count == 1 ? "issue" : "issues") across \(seriesCount) selected \(seriesCount == 1 ? "series" : "series")."
        }
        return "Applies to the \(count) selected \(count == 1 ? "issue" : "issues")."
    }

    private var selectionSummary: String {
        if !selectedSeriesNames.isEmpty {
            let seriesCount = selectedSeriesNames.count
            return "\(seriesCount) \(seriesCount == 1 ? "series" : "series") · \(selectedItems.count) issues"
        }
        let count = selectedItemIDs.count
        return "\(count) \(count == 1 ? "issue" : "issues") selected"
    }

    /// Floating bar over the grid. Everything here applies to `selectedItems`.
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)

            Text(selectionSummary)
                .font(.callout.monospacedDigit())
                .foregroundStyle(CGTheme.text)

            Divider().frame(height: 16)

            Button("Select All") { selectAllVisible() }
                .buttonStyle(.plain)
                .foregroundStyle(CGTheme.subtext1)

            Menu {
                bulkActions
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(selectedItems.isEmpty)

            Divider().frame(height: 16)

            Button(selectionMode ? "Done" : "Clear") {
                withAnimation(.easeOut(duration: 0.18)) {
                    clearSelection()
                    selectionMode = false
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(CGTheme.subtext1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle, cornerRadius: 0)
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent.opacity(0.5)).frame(height: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// The single-issue context menu, applied to the whole selection.
    ///
    /// Toggles become explicit pairs: a mixed selection has no sensible "on"
    /// state, so "Add to Favorites" and "Remove from Favorites" both appear
    /// rather than one guessing which way you meant.
    ///
    /// Split into pieces because a ViewBuilder tops out at ten children.
    @ViewBuilder
    private var bulkActions: some View {
        let targets = selectedItems
        bulkGroupingActions(targets)
        bulkRatingMenu(targets)
        bulkStatusActions(targets)
        bulkFlagActions(targets)
        bulkRunActions(targets)
        bulkRemovalActions(targets)
    }

    @ViewBuilder
    private func bulkGroupingActions(_ targets: [LibraryItem]) -> some View {
        Button {
            fieldEdit = SeriesFieldEdit(
                field: .seriesGroup,
                displayName: selectionSummary,
                items: targets,
                current: agreedValue(targets.map(\.seriesGroupName)),
                scopeDescription: selectionScopeDescription
            )
        } label: {
            Label("Set Series Group…", systemImage: "square.stack")
        }

        Button {
            fieldEdit = SeriesFieldEdit(
                field: .publisher,
                displayName: selectionSummary,
                items: targets,
                current: agreedValue(targets.map(\.publisherName)),
                scopeDescription: selectionScopeDescription
            )
        } label: {
            Label("Set Publisher…", systemImage: "building.2")
        }

        LabelPickerMenu(
            items: targets,
            labels: allLabels,
            onManage: { showLabelManager = true },
            onChange: { try? context.save() }
        )
    }

    @ViewBuilder
    private func bulkRatingMenu(_ targets: [LibraryItem]) -> some View {
        Divider()

        Menu("Rating") {
            ForEach((1...5).reversed(), id: \.self) { stars in
                Button(String(repeating: "★", count: stars)) {
                    for item in targets { item.rating = stars }
                    try? context.save()
                }
            }
            Divider()
            Button("Clear Rating") {
                for item in targets { item.rating = 0 }
                try? context.save()
            }
        }
    }

    @ViewBuilder
    private func bulkStatusActions(_ targets: [LibraryItem]) -> some View {
        Divider()

        Button {
            for item in targets { StatusActions.markRead(item, context: context) }
            try? context.save()
        } label: {
            Label("Mark as Read", systemImage: "checkmark.circle")
        }

        Button {
            for item in targets { StatusActions.markUnread(item, context: context) }
            try? context.save()
        } label: {
            Label("Mark as Unread", systemImage: "circle")
        }
    }

    @ViewBuilder
    private func bulkFlagActions(_ targets: [LibraryItem]) -> some View {
        Divider()

        Button {
            for item in targets { item.isFavorite = true }
            try? context.save()
        } label: {
            Label("Add to Favorites", systemImage: "heart")
        }

        Button {
            for item in targets { item.isFavorite = false }
            try? context.save()
        } label: {
            Label("Remove from Favorites", systemImage: "heart.slash")
        }

        Button {
            ReadingListActions.addAll(targets, allItems: items)
            try? context.save()
        } label: {
            Label("Add to Reading List", systemImage: "text.badge.plus")
        }

        Button {
            ReadingListActions.clear(targets)
            try? context.save()
        } label: {
            Label("Remove from Reading List", systemImage: "text.badge.minus")
        }
    }

    @ViewBuilder
    private func bulkRunActions(_ targets: [LibraryItem]) -> some View {
        Divider()

        Button {
            for item in targets {
                item.isSpecial = true
                item.isMetadataLocked = true
            }
            try? context.save()
        } label: {
            Label("Mark as Special", systemImage: "star.square")
        }

        Button {
            for item in targets {
                item.isSpecial = false
                item.isMetadataLocked = true
            }
            try? context.save()
        } label: {
            Label("Move to Main Run", systemImage: "arrow.up.doc")
        }
    }

    @ViewBuilder
    private func bulkRemovalActions(_ targets: [LibraryItem]) -> some View {
        Divider()

        Button {
            removeFromLibraryOnly(targets, context: context)
            clearSelection()
        } label: {
            Label("Remove from Library", systemImage: "minus.circle")
        }

        Button(role: .destructive) {
            showBulkTrashConfirm = true
        } label: {
            Label("Move Files to Trash…", systemImage: "trash")
        }
    }

    // MARK: - Grids

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: coverSize.minWidth, maximum: coverSize.maxWidth), spacing: 20)]
    }

    private func seriesGrid(_ groups: [Series]) -> some View {
        LazyVGrid(columns: columns, spacing: 26) {
            ForEach(groups) { group in
                SeriesCard(
                    series: group,
                    allItems: items,
                    onRename: { renameTarget = group },
                    onMerge: { mergeSource = group },
                    onContinue: { item in
                        openAtEnd = false
                        withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
                    },
                    onSetGroup: {
                        fieldEdit = SeriesFieldEdit(
                            field: .seriesGroup,
                            displayName: group.name,
                            items: group.items,
                            current: currentGroup(of: group)
                        )
                    },
                    onSetPublisher: {
                        fieldEdit = SeriesFieldEdit(
                            field: .publisher,
                            displayName: group.name,
                            items: group.items,
                            current: agreedValue(group.items.map(\.publisherName))
                        )
                    }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            selectedSeriesNames.contains(group.name) ? accent : .clear,
                            lineWidth: 2
                        )
                        .padding(-4)
                }
                .overlay(alignment: .topLeading) {
                    selectionBadge(isSelected: selectedSeriesNames.contains(group.name))
                }
                .onTapGesture {
                    handleSeriesTap(group, in: groups)
                }
            }
        }
        .padding()
        .onAppear { navigableSeries = groups }
        .onChange(of: groups.map(\.name)) { _, _ in navigableSeries = groups }
        .onDisappear { navigableSeries = [] }
    }

    /// Items currently rendered as an issue grid, for keyboard navigation.
    @State private var navigableItems: [LibraryItem] = []
    /// Series currently rendered as cards, for Select All and Shift ranges.
    @State private var navigableSeries: [Series] = []
    @State private var gridColumnCount: Int = 1

    private func moveSelection(by delta: Int) {
        guard !navigableItems.isEmpty else { return }
        let currentIndex = navigableItems.firstIndex { $0.id == keyboardSelection } ?? -1
        let next = currentIndex < 0
            ? (delta > 0 ? 0 : navigableItems.count - 1)
            : min(max(currentIndex + delta, 0), navigableItems.count - 1)
        keyboardSelection = navigableItems[next].id
    }

    private func openSelection() {
        guard let id = keyboardSelection,
              let item = navigableItems.first(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
    }

    /// Arrow-key handling via a local event monitor.
    ///
    /// `.focusable()` + `.onKeyPress` never fired here: inside a
    /// NavigationSplitView the detail pane doesn't take first responder, so the
    /// grid was never focused. A monitor sidesteps focus entirely — it just
    /// declines the event whenever a text field is being edited.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Never intercept typing.
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            // The reader has its own shortcuts.
            guard openedItem == nil, !navigableItems.isEmpty else { return event }
            // Let modified keys through (⌘F, ⌘Z, and friends).
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }

            switch event.keyCode {
            case 123: moveSelection(by: -1); return nil                       // left
            case 124: moveSelection(by: 1); return nil                        // right
            case 126: moveSelection(by: useListView ? -1 : -gridColumnCount); return nil  // up
            case 125: moveSelection(by: useListView ? 1 : gridColumnCount); return nil    // down
            case 36, 76:                                                      // return / enter
                guard keyboardSelection != nil else { return event }
                openSelection()
                return nil
            case 53:                                                          // escape
                if hasSelection || selectionMode {
                    clearSelection()
                    selectionMode = false
                    return nil
                }
                guard keyboardSelection != nil else { return event }
                keyboardSelection = nil
                return nil
            default: return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    @ViewBuilder
    private func issueCollection(for list: [LibraryItem]) -> some View {
        if useListView {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 2) {
                        ForEach(list) { item in
                            LibraryItemRow(item: item, allItems: items)
                                .id(item.id)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedItemIDs.contains(item.id)
                                              ? accent.opacity(0.16) : .clear)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(
                                            selectedItemIDs.contains(item.id)
                                                || keyboardSelection == item.id ? accent : .clear,
                                            lineWidth: 2
                                        )
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleIssueTap(item, in: list)
                                }
                        }
                    }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onAppear { navigableItems = list }
                .onChange(of: list.map(\.id)) { _, _ in navigableItems = list }
                .onChange(of: keyboardSelection) { _, newValue in
                    if let newValue { withAnimation { proxy.scrollTo(newValue, anchor: .center) } }
                }
            }
        } else {
            ScrollViewReader { proxy in
                LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(list) { item in
                            LibraryItemCell(item: item, allItems: items, coverHeight: coverSize.coverHeight)
                                .id(item.id)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            selectedItemIDs.contains(item.id)
                                                || keyboardSelection == item.id ? accent : .clear,
                                            lineWidth: 2
                                        )
                                        .padding(-4)
                                }
                                .overlay(alignment: .topLeading) {
                                    selectionBadge(isSelected: selectedItemIDs.contains(item.id))
                                }
                                .onTapGesture {
                                    handleIssueTap(item, in: list)
                                }
                        }
                    }
                    .padding()
                    // Measured in the background so it can't affect layout —
                    // a GeometryReader in the flow collapses inside a ScrollView.
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { gridColumnCount = columnCount(for: geo.size.width) }
                                .onChange(of: geo.size.width) { _, width in
                                    gridColumnCount = columnCount(for: width)
                                }
                        }
                }
                .onAppear { navigableItems = list }
                .onChange(of: list.map(\.id)) { _, _ in navigableItems = list }
                .onChange(of: keyboardSelection) { _, newValue in
                    if let newValue { withAnimation { proxy.scrollTo(newValue, anchor: .center) } }
                }
            }
        }
    }

    /// Approximate column count for arrow-key row jumps.
    private func columnCount(for width: CGFloat) -> Int {
        let cell = coverSize.minWidth + 20
        return max(Int((width - 32) / cell), 1)
    }

    private var emptyState: some View {
        GhostEmptyState(title: emptyTitle, message: emptyDescription, accent: accent)
    }

    private var emptyTitle: String {
        switch activeFilter {
        case .library: return "No comics yet"
        case .new: return "Nothing new"
        case .inProgress: return "Nothing in progress"
        case .readingList: return "Reading list is empty"
        case .favorites: return "No favorites yet"
        case .completed: return "Nothing completed yet"
        }
    }

    private var emptyDescription: String {
        switch activeFilter {
        case .library:
            return "Pick a folder to watch in Settings (⌘,), drop some .cbr/.cbz files in it, then hit the rescan button up top."
        case .favorites:
            return "Right-click any comic and choose Add to Favorites."
        case .readingList:
            return "Right-click any comic or series and choose “Add to Reading List.”"
        case .new:
            return "Everything in your library has been opened at least once."
        case .inProgress:
            return "Start reading something and it'll show up here."
        case .completed:
            return "Finish an issue and it lands here."
        }
    }
}

// MARK: - Series sheets

struct SeriesRenameSheet: View {
    let series: Series
    var onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @State private var newName = ""

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Series").font(.headline).foregroundStyle(CGTheme.text)

            TextField("Series name", text: $newName).textFieldStyle(.roundedBorder)

            Text("Renames the series for all \(series.items.count) issues and updates their titles.")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("Rename") {
                    onRename(newName)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(
                    newName.trimmingCharacters(in: .whitespaces).isEmpty
                        || newName.trimmingCharacters(in: .whitespaces) == series.name
                )
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(CGTheme.base)
        .onAppear { newName = series.name }
    }
}

struct SeriesMergeSheet: View {
    let source: Series
    let candidates: [String]
    var onMerge: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    @State private var target = ""

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge Series").font(.headline).foregroundStyle(CGTheme.text)

            Text("Move all \(source.items.count) issues of “\(source.name)” into:")
                .font(.callout)
                .foregroundStyle(CGTheme.subtext1)

            if candidates.isEmpty {
                Text("No other series to merge into.")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext0)
            } else {
                Picker("Target series", selection: $target) {
                    ForEach(candidates, id: \.self) { name in Text(name).tag(name) }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("Merge") {
                    onMerge(target)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(target.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(CGTheme.base)
        .onAppear { target = candidates.first ?? "" }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [LibraryItem.self, ReadingProgress.self, SmartCollection.self], inMemory: true)
}

// MARK: - Folder scan sheet

/// Pick one subfolder of a library to scan, instead of walking the whole thing.
struct FolderScanSheet: View {
    let library: ComicLibrary
    var onScan: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue

    @State private var folders: [URL] = []
    @State private var selection: URL?

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scan One Folder")
                .font(.headline)
                .foregroundStyle(CGTheme.text)

            Text("Only this folder is scanned — everything else in \(library.name) is left alone.")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)

            if folders.isEmpty {
                Text("No subfolders found.")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(folders, id: \.self, selection: $selection) { folder in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(accent)
                        Text(folder.lastPathComponent).foregroundStyle(CGTheme.text)
                    }
                    .tag(folder)
                }
                .frame(height: 260)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Button("Choose Another Folder…") { pickManually() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Scan") {
                    if let selection { onScan(selection) }
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(selection == nil)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(CGTheme.base)
        .onAppear {
            if let root = library.resolveURL() {
                folders = LibraryFolder.topLevelFolders(in: root)
                selection = folders.first
            }
        }
    }

    private func pickManually() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = library.resolveURL()
        panel.prompt = "Scan This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            onScan(url)
            dismiss()
        }
    }
}

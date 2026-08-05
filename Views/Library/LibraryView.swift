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
    case master(String)          // umbrella folder, e.g. "Dragon Ball"
    case series(String)
    case collection(UUID)
    case label(UUID)
    case stats
    case tools
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
    @Query(sort: \LibraryItem.dateAdded, order: .reverse) private var items: [LibraryItem]
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
    @State private var openAtEnd = false
    @State private var keyMonitor: Any?
    @State private var openRequests = OpenRequests.shared
    @State private var isDropTargeted = false
    @State private var dropMessage: String?

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .title }
    private var coverSize: CoverSize { CoverSize(rawValue: coverSizeRaw) ?? .medium }

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
                        withAnimation(.easeInOut(duration: 0.3)) { self.openedItem = nil }
                    },
                    onOpenNext: { next in
                        openAtEnd = false
                        withAnimation(.easeInOut(duration: 0.3)) { self.openedItem = next }
                    },
                    onOpenPrevious: { previous in
                        openAtEnd = true
                        withAnimation(.easeInOut(duration: 0.3)) { self.openedItem = previous }
                    },
                    startAtEnd: openAtEnd
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
        case .master(let name): lastRouteRaw = "master:\(name)"
        case .series(let name): lastRouteRaw = "series:\(name)"
        case .collection(let id): lastRouteRaw = "collection:\(id.uuidString)"
        case .label(let id): lastRouteRaw = "label:\(id.uuidString)"
        case .label(let id): lastRouteRaw = "label:\(id.uuidString)"
        case .stats: lastRouteRaw = "stats"
        case .tools: lastRouteRaw = "tools"
        }
    }

    private func restoreIfEnabled() {
        guard restoreState, !didRestore else { return }
        didRestore = true
        let parts = lastRouteRaw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 || lastRouteRaw == "stats" || lastRouteRaw == "tools" else { return }
        if lastRouteRaw == "stats" { route = .stats; return }
        if lastRouteRaw == "tools" { route = .tools; return }
        switch parts[0] {
        case "filter":
            if let f = LibraryFilter(rawValue: parts[1]) { route = .filter(f) }
        case "master":
            route = .master(parts[1])
        case "series":
            route = .series(parts[1])
        case "collection":
            if let id = UUID(uuidString: parts[1]) { route = .collection(id) }
        case "label":
            if let id = UUID(uuidString: parts[1]) { route = .label(id) }
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

            Button { openRandomUnread() } label: {
                Label("Read something", systemImage: "shuffle")
            }
            .help("Open a random unread issue")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")

            Button {
                useListView.toggle()
            } label: {
                Label(useListView ? "Grid view" : "List view",
                      systemImage: useListView ? "square.grid.2x2" : "list.bullet")
            }
            .help(useListView ? "Switch to grid view" : "Switch to list view")

            if !useListView {
                Menu {
                    ForEach(CoverSize.allCases) { size in
                        Button {
                            coverSizeRaw = size.rawValue
                        } label: {
                            if coverSizeRaw == size.rawValue {
                                Label(size.label, systemImage: "checkmark")
                            } else {
                                Text(size.label)
                            }
                        }
                    }
                } label: {
                    Label("Cover size", systemImage: "square.resize")
                }
            }

            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

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
        case .series(let name):
            // If this series sits under an umbrella, go back to it.
            if let item = scopedItems.first(where: { $0.seriesKey == name }),
               item.hasMaster, let master = item.masterSeries, master != name {
                return .master(master)
            }
            return .filter(activeFilter)
        case .master:
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

            case .master(let name):
                let children = series(inMaster: name)
                if children.count == 1, let only = children.first, only.name == name {
                    seriesDetail(only)   // umbrella with a single series — skip a level
                } else if children.isEmpty {
                    GhostEmptyState(title: "Nothing here", message: "", accent: accent)
                } else {
                    seriesGrid(children)
                }

            case .label(let id):
                let tagged = sortItems(scopedItems.filter { $0.hasLabel(id) })
                if tagged.isEmpty {
                    GhostEmptyState(
                        title: "Nothing labelled yet",
                        message: "Right-click any comic and use the Labels menu to tag it.",
                        accent: accent
                    )
                } else {
                    issueCollection(for: tagged)
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
        } else if masterGroups.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if f == .library, !continueReading.isEmpty { continueShelf }
                if f == .library, !recentlyAdded.isEmpty { recentlyAddedShelf }
                seriesGrid(masterGroups)
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
        case .label(let id): return labels.first { $0.id == id }?.name ?? "Label"
        case .master(let name): return name
        case .series(let name): return name
        case .collection(let id):
            return collections.first(where: { $0.id == id })?.name ?? "Collection"
        case .label(let id):
            return allLabels.first(where: { $0.id == id })?.name ?? "Label"
        case .filter(let f): return f == .library ? "Comic Ghost" : f.rawValue
        }
    }

    private var backdropPath: String? {
        if case .series(let name) = route,
           let series = allSeries.first(where: { $0.name == name }) {
            return series.coverPath
        }
        if case .master(let name) = route,
           let group = masterGroups.first(where: { $0.name == name }) {
            return group.coverPath
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently added")
                .font(.headline)
                .foregroundStyle(CGTheme.subtext1)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentlyAdded) { item in continueCell(item) }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .padding(.top, 10)
    }

    private var continueShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue reading")
                .font(.headline)
                .foregroundStyle(CGTheme.subtext1)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(continueReading) { item in continueCell(item) }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
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
                if libraries.count > 1 {
                    sidebarLabel("Libraries")
                    libraryRow(nil, name: "All Libraries", count: items.count)
                    ForEach(libraries) { library in
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

                sidebarLabel("Insights").padding(.top, 10)
                statsRow
                toolsRow

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

            if seriesExpanded {
                ForEach(allSeries) { series in
                    seriesRow(series)
                }
            }
        }
        .padding(.top, 10)
    }

    private func seriesRow(_ series: Series) -> some View {
        let isSelected: Bool = {
            if case .series(let name) = route { return name == series.name }
            return false
        }()
        let unread = series.items.filter { $0.status != .completed }.count

        return Button {
            route = .series(series.name)
        } label: {
            HStack(spacing: 8) {
                Text(series.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CGTheme.subtext0)
                }
            }
            .font(.callout)
            .foregroundStyle(isSelected ? CGTheme.text : CGTheme.subtext1)
            .padding(.leading, 22)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename Series…") { renameTarget = series }
            Button("Merge Into…") { mergeSource = series }
        }
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

    /// Top-level groups: umbrella folders plus standalone series.
    private var masterGroups: [Series] {
        Dictionary(grouping: filteredItems, by: \.masterKey)
            .map { Series(name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Series inside one umbrella folder.
    private func series(inMaster master: String) -> [Series] {
        let members = filteredItems.filter { $0.masterKey == master }
        return Dictionary(grouping: members, by: \.seriesKey)
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
                    subSeriesCount: subSeriesCount(for: group),
                    onRename: { renameTarget = group },
                    onMerge: { mergeSource = group }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        route = destination(for: group)
                    }
                }
            }
        }
        .padding()
    }

    /// How many distinct series live under this tile (1 = a plain series).
    private func subSeriesCount(for group: Series) -> Int {
        Set(group.items.map(\.seriesKey)).count
    }

    private func destination(for group: Series) -> LibraryRoute {
        subSeriesCount(for: group) > 1 ? .master(group.name) : .series(group.name)
    }

    /// Items currently rendered as an issue grid, for keyboard navigation.
    @State private var navigableItems: [LibraryItem] = []
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
                                        .strokeBorder(
                                            keyboardSelection == item.id ? accent : .clear,
                                            lineWidth: 2
                                        )
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    keyboardSelection = item.id
                                    openAtEnd = false
                                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
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
                                            keyboardSelection == item.id ? accent : .clear,
                                            lineWidth: 2
                                        )
                                        .padding(-4)
                                }
                                .onTapGesture {
                                    keyboardSelection = item.id
                                    openAtEnd = false
                                    withAnimation(.easeInOut(duration: 0.3)) { openedItem = item }
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

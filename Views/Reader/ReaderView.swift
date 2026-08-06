import SwiftUI
import SwiftData
import ImageIO

/// Full-window reader. Pages group into display units — single pages, or pairs
/// in spread mode. Manga mode flips page-turn direction and spread order.
struct ReaderView: View {
    let item: LibraryItem
    var onClose: () -> Void
    var onOpenNext: (LibraryItem) -> Void = { _ in }
    var onOpenPrevious: (LibraryItem) -> Void = { _ in }
    /// Set when arriving by paging backwards, so we land on the last page.
    var startAtEnd: Bool = false
    /// Opens directly at a page, used when arriving from a bookmark or note.
    var startAtPage: Int?

    @Environment(\.modelContext) private var context
    @AppStorage(CGGlass.key) private var glassEnabled: Bool = true
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue
    /// Read so a theme change re-renders this view tree.
    @AppStorage(CGThemeCatalog.key) private var themeID: String = "mocha"
    @AppStorage("hasSeenReaderControls") private var hasSeenControls: Bool = false
    @AppStorage("readerFitMode") private var fitModeRaw: String = FitMode.page.rawValue
    @AppStorage("readerSpreadMode") private var spreadEnabled: Bool = false
    /// Shifts spread pairing by one page when the natural pairing is off.
    @AppStorage("readerSpreadOffset") private var spreadOffset: Bool = false
    @AppStorage("autoHideChrome") private var autoHideChrome: Bool = true
    /// Series names set to manga mode, stored as a newline-separated list.
    @AppStorage("mangaSeries") private var mangaSeriesRaw: String = ""
    /// Series set to continuous scrolling, newline-separated.
    @AppStorage("continuousSeries") private var continuousSeriesRaw: String = ""
    /// Per-series image adjustment overrides, one line per series:
    /// "seriesKey<tab>brightness,contrast,gamma,grayscale,autoContrast,autoCrop,rotation"
    @AppStorage("seriesAdjustments") private var seriesAdjustmentsRaw: String = ""
    @AppStorage("alwaysShowEdges") private var alwaysShowEdges: Bool = false
    @AppStorage("hideReaderControls") private var hideControls: Bool = false
    @AppStorage("readerPersistZoom") private var persistZoom: Bool = true
    @AppStorage("showEndOfIssueCard") private var showEndCard: Bool = true
    @AppStorage("readerZoomLevel") private var storedZoom: Double = 1.0
    @AppStorage(ImageAdjustments.brightnessKey) private var adjBrightness: Double = 0
    @AppStorage(ImageAdjustments.contrastKey) private var adjContrast: Double = 1
    @AppStorage(ImageAdjustments.gammaKey) private var adjGamma: Double = 1
    @AppStorage(ImageAdjustments.grayscaleKey) private var adjGrayscale: Bool = false
    @AppStorage(ImageAdjustments.autoContrastKey) private var adjAutoContrast: Bool = false
    @AppStorage(ImageAdjustments.autoCropKey) private var adjAutoCrop: Bool = false
    @AppStorage(ImageAdjustments.rotationKey) private var adjRotation: Int = 0
    @AppStorage("preventSleepWhileReading") private var preventSleep: Bool = true

    @State private var archive: ComicArchive?
    @State private var pageSizes: [Int: CGSize] = [:]
    @State private var units: [[ComicPage]] = []
    @State private var currentUnit = 0
    @State private var loadError: String?
    @State private var showNavPane = false
    @State private var showLegend = false
    @State private var showJump = false
    @State private var showStrip = false
    @State private var jumpText = ""
    @State private var zoom: CGFloat = 1.0
    @State private var hoveringLeft = false
    @State private var hoveringRight = false
    @State private var nextItem: LibraryItem?
    @State private var previousItem: LibraryItem?
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var sleepAssertion: NSObjectProtocol?
    @State private var showAdjustments = false
    @State private var magnifierOn = false
    @State private var bookmarks: [Bookmark] = []
    @State private var continuousPage = 0
    @State private var notes: [ComicNote] = []
    @State private var activeNote: ComicNote?
    @State private var endCardVisible = false
    /// The unit whose end card has already been dismissed, so continuing
    /// forward doesn't immediately show it again.
    @State private var endCardAcknowledgedUnit: Int?
    @State private var coverStatus: String?

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }
    private var fitMode: FitMode { FitMode(rawValue: fitModeRaw) ?? .page }

    private var adjustments: Binding<ImageAdjustments> {
        Binding(
            get: {
                // A series override wins when one exists; otherwise the global
                // settings apply, exactly as before.
                if let stored = seriesAdjustments[item.seriesKey] { return stored }
                return ImageAdjustments(
                    brightness: adjBrightness,
                    contrast: adjContrast,
                    gamma: adjGamma,
                    grayscale: adjGrayscale,
                    autoContrast: adjAutoContrast,
                    autoCrop: adjAutoCrop,
                    rotation: adjRotation
                )
            },
            set: { newValue in
                if hasSeriesAdjustments {
                    setSeriesAdjustments(newValue)
                    return
                }
                adjBrightness = newValue.brightness
                adjContrast = newValue.contrast
                adjGamma = newValue.gamma
                adjGrayscale = newValue.grayscale
                adjAutoContrast = newValue.autoContrast
                adjAutoCrop = newValue.autoCrop
                adjRotation = newValue.rotation
            }
        )
    }

    // MARK: - Image adjustments (per series)

    /// A 1970s scan and a modern digital release rarely want the same gamma.
    private var seriesAdjustments: [String: ImageAdjustments] {
        var result: [String: ImageAdjustments] = [:]
        for line in seriesAdjustmentsRaw.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let values = parts[1].split(separator: ",").map(String.init)
            guard values.count == 7 else { continue }
            result[String(parts[0])] = ImageAdjustments(
                brightness: Double(values[0]) ?? 0,
                contrast: Double(values[1]) ?? 1,
                gamma: Double(values[2]) ?? 1,
                grayscale: values[3] == "1",
                autoContrast: values[4] == "1",
                autoCrop: values[5] == "1",
                rotation: Int(values[6]) ?? 0
            )
        }
        return result
    }

    private var hasSeriesAdjustments: Bool {
        seriesAdjustments[item.seriesKey] != nil
    }

    private func setSeriesAdjustments(_ value: ImageAdjustments) {
        var all = seriesAdjustments
        all[item.seriesKey] = value
        writeSeriesAdjustments(all)
    }

    private func clearSeriesAdjustments() {
        var all = seriesAdjustments
        all.removeValue(forKey: item.seriesKey)
        writeSeriesAdjustments(all)
    }

    private func writeSeriesAdjustments(_ all: [String: ImageAdjustments]) {
        seriesAdjustmentsRaw = all
            .map { key, value in
                let encoded = [
                    String(value.brightness),
                    String(value.contrast),
                    String(value.gamma),
                    value.grayscale ? "1" : "0",
                    value.autoContrast ? "1" : "0",
                    value.autoCrop ? "1" : "0",
                    String(value.rotation)
                ].joined(separator: ",")
                return "\(key)\t\(encoded)"
            }
            .sorted()
            .joined(separator: "\n")
    }

    /// Turning this on snapshots whatever is on screen into the series slot.
    private func setUsesSeriesAdjustments(_ enabled: Bool) {
        if enabled {
            setSeriesAdjustments(adjustments.wrappedValue)
        } else {
            clearSeriesAdjustments()
        }
    }

    // MARK: - Continuous mode (per series)

    private var continuousSeriesSet: Set<String> {
        Set(continuousSeriesRaw.split(separator: "\n").map(String.init))
    }

    private var isContinuous: Bool {
        continuousSeriesSet.contains(item.seriesKey)
    }

    private func setContinuous(_ enabled: Bool) {
        var set = continuousSeriesSet
        if enabled { set.insert(item.seriesKey) } else { set.remove(item.seriesKey) }
        continuousSeriesRaw = set.sorted().joined(separator: "\n")
    }
    private var isZoomed: Bool { zoom > 1.01 }

    // MARK: - Manga mode (per series)

    private var mangaSeriesSet: Set<String> {
        Set(mangaSeriesRaw.split(separator: "\n").map(String.init))
    }

    private var isManga: Bool {
        mangaSeriesSet.contains(item.seriesKey)
    }

    private func setManga(_ enabled: Bool) {
        var set = mangaSeriesSet
        if enabled { set.insert(item.seriesKey) } else { set.remove(item.seriesKey) }
        mangaSeriesRaw = set.sorted().joined(separator: "\n")
    }

    private var isOnLastUnit: Bool {
        !units.isEmpty && currentUnit >= units.count - 1
    }

    private var readProgress: Double {
        guard units.count > 1 else { return 1 }
        return Double(currentUnit) / Double(units.count - 1)
    }

    private var currentPagePath: String? {
        guard units.indices.contains(currentUnit) else { return nil }
        return units[currentUnit].first?.imageURL.path
    }

    private var chromeShown: Bool {
        // Panels the user opened always win over the hide setting.
        let overlayOpen = showNavPane || showLegend || showJump || showStrip || showAdjustments
        if hideControls { return overlayOpen }
        return !autoHideChrome || chromeVisible || overlayOpen
    }

    /// The page counter is the one piece of chrome that survives Hide Controls.
    /// Full strength while the rest of the chrome is up, dimmed but legible
    /// once it goes away.
    private var counterOpacity: Double {
        chromeShown ? 1 : 0.35
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if archive != nil, !units.isEmpty {
                pager
                    .contextMenu { readerMenu }
            } else if let loadError {
                ContentUnavailableView("Couldn't open comic",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView("Opening…").tint(accent)
            }

            edgeHoverZone

            if showNavPane {
                navPane.transition(.move(edge: .leading).combined(with: .opacity))
            }

            helpButton.opacity(chromeShown ? 1 : 0)

            if showLegend { legendOverlay }

            if showAdjustments {
                VStack {
                    HStack {
                        Spacer()
                        AdjustmentsPanel(
                            adjustments: adjustments,
                            glassEnabled: glassEnabled,
                            accent: accent,
                            seriesName: item.seriesKey,
                            usesSeriesSettings: hasSeriesAdjustments,
                            onSeriesScopeChange: { setUsesSeriesAdjustments($0) }
                        ) { showAdjustments = false }
                        .padding(.top, 84)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showStrip, !units.isEmpty {
                PageStrip(units: units, currentUnit: currentUnit,
                          accent: accent, rightToLeft: isManga,
                          chapterStarts: chapterStartPages) { index in
                    jump(to: index)
                }
                .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) { edgeProgressBar }
        .overlay {
            if endCardVisible {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.45))
                        .ignoresSafeArea()
                        .onTapGesture {
                            endCardAcknowledgedUnit = currentUnit
                            withAnimation(.easeOut(duration: 0.2)) { endCardVisible = false }
                        }
                    endOfIssueCard
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let coverStatus {
                Text(coverStatus)
                    .font(.callout)
                    .foregroundStyle(CGTheme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle)
                    .clipShape(Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: coverStatus)
        .background {
            if glassEnabled {
                GlassBackdrop(imagePath: currentPagePath, tint: CGTheme.crust, blur: 70, artOpacity: 0.5)
                    .animation(.easeOut(duration: 0.35), value: currentUnit)
            } else {
                CGTheme.crust
            }
        }
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
        .animation(.easeOut(duration: 0.22), value: showNavPane)
        .animation(.easeOut(duration: 0.22), value: showLegend)
        .animation(.easeOut(duration: 0.25), value: showStrip)
        .animation(.easeOut(duration: 0.2), value: showAdjustments)
        .animation(.easeInOut(duration: 0.25), value: hideControls)
        .animation(.easeOut(duration: 0.25), value: isContinuous)
        .animation(.easeInOut(duration: 0.3), value: chromeShown)
        .onChange(of: zoom) { _, newValue in
            // Pinch, Cmd-scroll and double-click all write through the binding,
            // so persistence is captured here rather than in setZoom.
            if persistZoom { storedZoom = Double(newValue) }
        }
        .onChange(of: persistZoom) { _, enabled in
            if enabled { storedZoom = Double(zoom) } else { setZoom(1.0) }
        }
        .task {
            if persistZoom {
                zoom = min(max(CGFloat(storedZoom), minZoom), maxZoom)
            }
            await load()
            if !hasSeenControls {
                showLegend = true
                hasSeenControls = true
            }
            loadNotes()
            wakeChrome()
            startSleepPrevention()
        }
        .onDisappear {
            hideTask?.cancel()
            stopSleepPrevention()
        }
        .sheet(item: $activeNote) { note in
            NoteEditorSheet(note: note)
                .onDisappear { loadNotes() }
        }
        .onChange(of: spreadEnabled) { _, _ in rebuildUnits(preservingPage: true) }
        .onChange(of: spreadOffset) { _, _ in rebuildUnits(preservingPage: true) }
        .background { shortcuts }
    }

    private var shortcuts: some View {
        Group {
            Button("") {
                if endCardVisible {
                    endCardAcknowledgedUnit = currentUnit
                    withAnimation(.easeOut(duration: 0.2)) { endCardVisible = false }
                } else {
                    dismissOrClose()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            Button("") { showLegend.toggle() }
                .keyboardShortcut("?", modifiers: [])
            Button("") { showLegend.toggle() }
                .keyboardShortcut("/", modifiers: .shift)
            Button("") { toggleFitMode() }
                .keyboardShortcut("f", modifiers: [])
            Button("") { spreadEnabled.toggle() }
                .keyboardShortcut("s", modifiers: [])
            Button("") { setManga(!isManga) }
                .keyboardShortcut("m", modifiers: [])
            Button("") { withAnimation(.easeOut(duration: 0.2)) { setContinuous(!isContinuous) } }
                .keyboardShortcut("c", modifiers: [])
            Button("") { toggleBookmark() }
                .keyboardShortcut("b", modifiers: [])
            Button("") { addNote() }
                .keyboardShortcut("n", modifiers: [])
            Button("") { showAdjustments.toggle() }
                .keyboardShortcut("i", modifiers: [])
            Button("") { magnifierOn.toggle() }
                .keyboardShortcut("l", modifiers: [])
            Button("") { withAnimation(.easeInOut(duration: 0.25)) { hideControls.toggle() } }
                .keyboardShortcut("h", modifiers: [])
            Button("") { if spreadEnabled { spreadOffset.toggle() } }
                .keyboardShortcut("o", modifiers: [])
            Button("") { showJump = true }
                .keyboardShortcut("g", modifiers: [])
            Button("") { showStrip.toggle() }
                .keyboardShortcut("t", modifiers: [])
            Button("") { toggleFullScreen() }
                .keyboardShortcut("f", modifiers: [.command, .control])
            Button("") { adjustZoom(by: zoomStep) }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { adjustZoom(by: -zoomStep) }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { setZoom(1.0) }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
    }

    // MARK: - Chrome

    private func wakeChrome() {
        chromeVisible = true
        hideTask?.cancel()
        guard autoHideChrome else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            chromeVisible = false
        }
    }

    /// Keeps the display awake while a comic is open — reading is quiet,
    /// and the screen dimming mid-page is annoying.
    private func startSleepPrevention() {
        guard preventSleep, sleepAssertion == nil else { return }
        sleepAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Reading a comic"
        )
    }

    private func stopSleepPrevention() {
        if let sleepAssertion {
            ProcessInfo.processInfo.endActivity(sleepAssertion)
        }
        sleepAssertion = nil
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func dismissOrClose() {
        if showLegend { showLegend = false }
        else if showAdjustments { showAdjustments = false }
        else if showJump { showJump = false }
        else if showStrip { showStrip = false }
        else if magnifierOn { magnifierOn = false }
        else { onClose() }
    }

    private func toggleFitMode() {
        fitModeRaw = (fitMode == .page ? FitMode.width : FitMode.page).rawValue
    }

    private var edgeProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: isManga ? .trailing : .leading) {
                Rectangle().fill(CGTheme.surface0.opacity(0.5))
                Rectangle()
                    .fill(accent)
                    .frame(width: geo.size.width * readProgress)
            }
            .frame(height: 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }

    private var legendOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { showLegend = false }

            ControlsLegend(glassEnabled: glassEnabled, rightToLeft: isManga) {
                showLegend = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var helpButton: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer()
                if isManga {
                    Text("MANGA")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CGTheme.crust)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent, in: Capsule())
                }
                chromeButton(magnifierOn ? "magnifyingglass.circle.fill" : "magnifyingglass.circle") {
                    magnifierOn.toggle()
                }
                .help("Magnifier (L)")
                chromeButton("slider.horizontal.3") { showAdjustments.toggle() }
                    .help("Image adjustments (I)")
                chromeButton(isBookmarked ? "bookmark.fill" : "bookmark") { toggleBookmark() }
                    .help("Bookmark this page (B)")
                chromeButton("eye.slash") {
                    withAnimation(.easeInOut(duration: 0.25)) { hideControls = true }
                }
                .help("Hide controls (H)")
                chromeButton("rectangle.grid.1x2") { showStrip.toggle() }
                    .help("Page thumbnails (T)")
                chromeButton("arrow.up.left.and.arrow.down.right") { toggleFullScreen() }
                    .help("Full screen (⌃⌘F)")
                chromeButton("questionmark.circle") { showLegend.toggle() }
                    .help("Show controls (?)")
            }
            .padding(.top, 40)
            .padding(.trailing, 20)
            Spacer()
        }
    }

    private func chromeButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(CGTheme.subtext0)
                .padding(8)
                .background {
                    if glassEnabled {
                        Circle().fill(.ultraThinMaterial)
                    } else {
                        Circle().fill(CGTheme.base.opacity(0.8))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nav pane

    private var edgeHoverZone: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { showNavPane = true }
            }
    }

    private var navPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { onClose() } label: {
                Label("Back to Library", systemImage: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(CGTheme.text)
            }
            .buttonStyle(.plain)

            Divider().overlay(CGTheme.surface1)

            Text(item.title)
                .font(.callout)
                .foregroundStyle(CGTheme.subtext1)
                .lineLimit(3)

            Text(pageLabel).font(.caption).foregroundStyle(CGTheme.subtext0)

            if let previousItem {
                Button { onOpenPrevious(previousItem) } label: {
                    Label("Previous: \(previousItem.title)", systemImage: "arrow.left")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext1)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            }

            if let nextItem {
                Button { onOpenNext(nextItem) } label: {
                    Label("Next: \(nextItem.title)", systemImage: "arrow.right")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext1)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(CGTheme.surface1)

            displayControls
            zoomControls

            Button { showStrip.toggle() } label: {
                Label("Page thumbnails", systemImage: "rectangle.grid.1x2")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext1)
            }
            .buttonStyle(.plain)

            notesSection

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { hideControls.toggle() }
            } label: {
                Label(hideControls ? "Show controls" : "Hide controls",
                      systemImage: hideControls ? "eye" : "eye.slash")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext1)
            }
            .buttonStyle(.plain)

            Button { showAdjustments.toggle() } label: {
                Label("Image adjustments", systemImage: "slider.horizontal.3")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext1)
            }
            .buttonStyle(.plain)

            Button { showLegend = true } label: {
                Label("Controls", systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(CGTheme.subtext1)
            }
            .buttonStyle(.plain)

            if !bookmarks.isEmpty {
                Divider().overlay(CGTheme.surface1)
                Text("Bookmarks").font(.caption).foregroundStyle(CGTheme.subtext0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(bookmarks) { bookmark in
                            Button { jumpToBookmark(bookmark) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption2)
                                        .foregroundStyle(accent)
                                    Text(bookmark.displayLabel)
                                        .font(.callout)
                                        .foregroundStyle(CGTheme.subtext1)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    context.delete(bookmark)
                                    try? context.save()
                                    loadBookmarks()
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()
        }
        .padding(20)
        .padding(.top, 40)
        .frame(width: 220, alignment: .leading)
        .frame(maxHeight: .infinity)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle)
        .softGlow(accent, radius: 9)
        .onHover { hovering in
            if !hovering { showNavPane = false }
        }
    }

    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fit").font(.caption).foregroundStyle(CGTheme.subtext0)
                Picker("", selection: $fitModeRaw) {
                    Text("Page").tag(FitMode.page.rawValue)
                    Text("Width").tag(FitMode.width.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pages").font(.caption).foregroundStyle(CGTheme.subtext0)
                Picker("", selection: $spreadEnabled) {
                    Text("Single").tag(false)
                    Text("Spread").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if spreadEnabled {
                    Toggle("Offset pairing", isOn: $spreadOffset)
                        .toggleStyle(.switch)
                        .tint(accent)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Mode").font(.caption).foregroundStyle(CGTheme.subtext0)
                Picker("", selection: Binding(
                    get: { isContinuous },
                    set: { value in
                        withAnimation(.easeOut(duration: 0.2)) { setContinuous(value) }
                    }
                )) {
                    Text("Paged").tag(false)
                    Text("Scroll").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Direction").font(.caption).foregroundStyle(CGTheme.subtext0)
                Picker("", selection: Binding(
                    get: { isManga },
                    set: { setManga($0) }
                )) {
                    Text("Western").tag(false)
                    Text("Manga").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Applies to \(item.seriesKey)")
                    .font(.system(size: 9))
                    .foregroundStyle(CGTheme.subtext0.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }

    /// Keyboard and button zoom moves in 25-point steps.
    private let zoomStep: CGFloat = 0.25
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0

    private var zoomControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zoom \(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(CGTheme.subtext0)

            HStack(spacing: 8) {
                zoomButton("minus.magnifyingglass") { adjustZoom(by: -zoomStep) }
                zoomButton("plus.magnifyingglass") { adjustZoom(by: zoomStep) }
                zoomButton("arrow.counterclockwise") { setZoom(1.0) }
            }

            // Drag straight to a zoom level instead of stepping there.
            Slider(
                value: Binding(
                    get: { Double(zoom) },
                    set: { setZoom(CGFloat($0)) }
                ),
                in: Double(minZoom)...Double(maxZoom),
                step: Double(zoomStep)
            )
            .controlSize(.small)
            .tint(accent)

            HStack {
                Text("\(Int(minZoom * 100))%")
                Spacer()
                Text("\(Int(maxZoom * 100))%")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(CGTheme.subtext0.opacity(0.7))

            Toggle(isOn: $persistZoom) {
                Text("Keep zoom between pages")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext1)
            }
            .toggleStyle(.checkbox)
            .tint(accent)
            .padding(.top, 2)
        }
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(CGTheme.text)
                .frame(width: 30, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CGTheme.surface0.opacity(glassEnabled ? 0.7 : 1))
                }
        }
        .buttonStyle(.plain)
    }

    private func adjustZoom(by delta: CGFloat) { setZoom(zoom + delta) }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = min(max(value, minZoom), maxZoom)
        }
    }

    // MARK: - Pager

    private var pager: some View {
        ZStack {
            if isContinuous, let archive {
                ContinuousPagesView(
                    pages: archive.pages,
                    adjustments: adjustments.wrappedValue,
                    widthFraction: fitMode == .width ? 1.0 : 0.72,
                    currentPage: $continuousPage
                )
                .onChange(of: continuousPage) { _, newPage in
                    currentUnit = unitIndex(containing: newPage)
                    saveProgress()
                }
            } else if units.indices.contains(currentUnit) {
                PageView(pages: units[currentUnit], fitMode: fitMode,
                         rightToLeft: isManga,
                         scrollPanningEnabled: !showStrip && !showLegend && !showJump && !showAdjustments,
                         onHorizontalSwipe: { direction in
                             turnUnit(isManga ? -direction : direction)
                         },
                         adjustments: adjustments.wrappedValue,
                         magnifierEnabled: magnifierOn,
                         persistZoom: persistZoom,
                         zoom: $zoom)
                .id(currentUnit)
                .transition(.opacity)
            }

            if !isZoomed {
                HStack {
                    // In manga mode the left edge advances.
                    pageTurnZone(
                        direction: isManga ? 1 : -1,
                        symbol: "chevron.left",
                        isHovering: $hoveringLeft,
                        enabled: isManga ? !isOnLastUnit : currentUnit > 0
                    )
                    Spacer()
                    pageTurnZone(
                        direction: isManga ? -1 : 1,
                        symbol: "chevron.right",
                        isHovering: $hoveringRight,
                        enabled: isManga ? currentUnit > 0 : !isOnLastUnit
                    )
                }
            }

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    zoomScale.opacity(chromeShown ? 1 : 0)
                    // The counter outlives the rest of the chrome: hiding
                    // controls shouldn't cost you your place in a 900-page
                    // omnibus. It just fades back rather than disappearing.
                    pageCounter.opacity(counterOpacity)
                }
            }

            if isOnLastUnit, let nextItem {
                HStack {
                    if isManga { nextIssueCard(nextItem).padding(.leading, 16); Spacer() }
                    else { Spacer(); nextIssueCard(nextItem).padding(.trailing, 16) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Group {
                Button("") { turnUnit(isManga ? 1 : -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { turnUnit(isManga ? -1 : 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { turnUnit(isManga ? 1 : -1) }.keyboardShortcut("a", modifiers: [])
                Button("") { turnUnit(isManga ? -1 : 1) }.keyboardShortcut("d", modifiers: [])
            }
            .opacity(0)
        }
    }

    private func nextIssueCard(_ next: LibraryItem) -> some View {
        Button { onOpenNext(next) } label: {
            VStack(spacing: 8) {
                Image(systemName: isManga ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text("Up next").font(.caption2).foregroundStyle(CGTheme.subtext0)
                Text(next.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CGTheme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(width: 88)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background {
                if glassEnabled {
                    RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(CGTheme.base.opacity(0.9))
                }
            }
            .softGlow(accent, radius: 8)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: isManga ? .leading : .trailing)))
    }

    private func pageTurnZone(
        direction: Int, symbol: String, isHovering: Binding<Bool>, enabled: Bool
    ) -> some View {
        ZStack {
            Rectangle().fill(.clear)
            PageTurnHint(
                symbol: symbol,
                isVisible: enabled && (alwaysShowEdges || isHovering.wrappedValue),
                dimmed: alwaysShowEdges && !isHovering.wrappedValue
            )
        }
        .frame(width: 130)
        .contentShape(Rectangle())
        .onHover { isHovering.wrappedValue = $0 }
        .onTapGesture { turnUnit(direction) }
    }

    private var pageLabel: String {
        guard let archive, units.indices.contains(currentUnit) else { return "" }
        let unit = units[currentUnit]
        if unit.count == 2, let first = unit.first, let last = unit.last {
            return "Pages \(first.index + 1)–\(last.index + 1) of \(archive.pageCount)"
        }
        if let first = unit.first {
            return "Page \(first.index + 1) of \(archive.pageCount)"
        }
        return ""
    }

    /// Always-visible zoom control, so it isn't buried in the nav pane.
    private var zoomScale: some View {
        HStack(spacing: 10) {
            Button { adjustZoom(by: -zoomStep) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .disabled(zoom <= minZoom)

            Slider(
                value: Binding(
                    get: { Double(zoom) },
                    set: { setZoom(CGFloat($0)) }
                ),
                in: Double(minZoom)...Double(maxZoom),
                step: Double(zoomStep)
            )
            .controlSize(.small)
            .tint(accent)
            .frame(width: 160)

            Button { adjustZoom(by: zoomStep) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(zoom >= maxZoom)

            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)

            Button { setZoom(1.0) } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .disabled(!isZoomed)
        }
        .foregroundStyle(CGTheme.subtext1)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            if glassEnabled {
                Capsule().fill(.ultraThinMaterial)
            } else {
                Capsule().fill(CGTheme.base.opacity(0.85))
            }
        }
    }

    private var pageCounter: some View {
        Button { showJump = true } label: {
            HStack(spacing: 8) {
                Text(counterText).font(.callout.monospacedDigit())
                if let chapterProgressLabel {
                    Text("· \(chapterProgressLabel)").font(.caption)
                }
                if isZoomed {
                    Text("· \(Int(zoom * 100))%").font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(CGTheme.subtext1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                if glassEnabled {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(CGTheme.base.opacity(0.85))
                }
            }
        }
        .buttonStyle(.plain)
        .help("Jump to page (G)")
        .popover(isPresented: $showJump, arrowEdge: .top) { jumpPopover }
        .padding(.bottom, showStrip ? 148 : 22)
    }

    private var jumpPopover: some View {
        HStack(spacing: 8) {
            TextField("Page", text: $jumpText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .onSubmit { jumpToPage() }
            Text("of \(archive?.pageCount ?? 0)")
                .font(.callout)
                .foregroundStyle(CGTheme.subtext0)
            Button("Go") { jumpToPage() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(12)
        .onAppear { jumpText = "" }
    }

    private func jumpToPage() {
        guard let archive, let number = Int(jumpText) else { return }
        let target = min(max(number, 1), archive.pageCount) - 1
        jump(to: unitIndex(containing: target))
        showJump = false
    }

    private func jump(to index: Int) {
        guard units.indices.contains(index) else { return }
        currentUnit = index
        if !persistZoom { zoom = 1.0 }
        saveProgress()
        preloadAround()
    }

    private var counterText: String {
        guard let archive, units.indices.contains(currentUnit) else { return "" }
        let unit = units[currentUnit]
        if unit.count == 2, let first = unit.first, let last = unit.last {
            return "\(first.index + 1)–\(last.index + 1) / \(archive.pageCount)"
        }
        if let first = unit.first {
            return "\(first.index + 1) / \(archive.pageCount)"
        }
        return ""
    }

    private func turnUnit(_ direction: Int) {
        wakeChrome()

        // Landing beat between issues. Without this, finishing an issue drops
        // you straight onto page 1 of the next one with no acknowledgement.
        if direction > 0, showEndCard, endCardAcknowledgedUnit != currentUnit, isAtSectionEnd {
            withAnimation(.easeOut(duration: 0.25)) { endCardVisible = true }
            return
        }

        let next = currentUnit + direction
        if next >= units.count, direction > 0, let nextItem {
            onOpenNext(nextItem)
            return
        }
        if next < 0, direction < 0, let previousItem {
            onOpenPrevious(previousItem)
            return
        }
        guard next >= 0, next < units.count else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            currentUnit = next
        }
        if !persistZoom { zoom = 1.0 }
        saveProgress()
        preloadAround()
    }

    // MARK: - Units

    private func buildUnits(from pages: [ComicPage]) -> [[ComicPage]] {
        guard spreadEnabled else { return pages.map { [$0] } }

        var result: [[ComicPage]] = []
        var index = 0
        // Normally the cover stands alone; the offset toggle flips that, which
        // fixes runs where the natural pairing lands a spread across two units.
        let soloFirst = !spreadOffset
        while index < pages.count {
            let page = pages[index]
            if (index == 0 && soloFirst) || isLandscape(page) {
                result.append([page])
                index += 1
                continue
            }
            if index + 1 < pages.count, !isLandscape(pages[index + 1]) {
                result.append([page, pages[index + 1]])
                index += 2
            } else {
                result.append([page])
                index += 1
            }
        }
        return result
    }

    private func isLandscape(_ page: ComicPage) -> Bool {
        guard let size = pageSizes[page.index], size.height > 0 else { return false }
        return size.width / size.height > 1.0
    }

    private func rebuildUnits(preservingPage: Bool) {
        guard let archive else { return }
        let pageToKeep = preservingPage
            ? (units.indices.contains(currentUnit) ? units[currentUnit].first?.index ?? 0 : 0)
            : 0
        units = buildUnits(from: archive.pages)
        currentUnit = unitIndex(containing: pageToKeep)
        preloadAround()
    }

    private func unitIndex(containing pageIndex: Int) -> Int {
        for (i, unit) in units.enumerated() where unit.contains(where: { $0.index == pageIndex }) {
            return i
        }
        return 0
    }

    private func preloadAround() {
        var urls: [URL] = []
        for offset in [1, 2, -1] {
            let index = currentUnit + offset
            guard units.indices.contains(index) else { continue }
            urls.append(contentsOf: units[index].map(\.imageURL))
        }
        ImageCache.shared.preload(urls)
    }

    // MARK: - Loading & progress

    /// All extraction runs off the main actor — opening a 40-page CBR used to
    /// shell out to unrar and write every page while the UI thread waited.
    private func load() async {
        let url = URL(fileURLWithPath: item.filePath)

        let result = await Task.detached(priority: .userInitiated) { () -> LoadResult in
            do {
                let extractor = try ArchiveExtractorRouter.extractor(for: url)
                let pages = try extractor.extractPages(from: url)

                var sizes: [Int: CGSize] = [:]
                for page in pages {
                    guard let source = CGImageSourceCreateWithURL(page.imageURL as CFURL, nil),
                          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
                          let height = props[kCGImagePropertyPixelHeight] as? CGFloat
                    else { continue }
                    sizes[page.index] = CGSize(width: width, height: height)
                }
                return LoadResult(pages: pages, sizes: sizes, error: nil)
            } catch {
                return LoadResult(pages: [], sizes: [:], error: error.localizedDescription)
            }
        }.value

        if let message = result.error {
            loadError = message
            return
        }

        let format = ComicArchive.Format(fileExtension: url.pathExtension) ?? .cbz
        archive = ComicArchive(sourceURL: url, format: format, pages: result.pages)
        pageSizes = result.sizes
        units = buildUnits(from: result.pages)

        item.isNew = false

        // Explicit page wins, then "open at the end" when paging backwards into
        // the previous issue, then the saved resume point.
        let lastPage = max(result.pages.count - 1, 0)
        let target: Int
        if let startAtPage {
            target = min(max(startAtPage, 0), lastPage)
        } else if startAtEnd {
            target = lastPage
        } else {
            target = min(item.progress?.currentPage ?? 0, lastPage)
        }
        currentUnit = unitIndex(containing: target)
        continuousPage = target
        nextItem = findNextIssue()
        preloadAround()
    }

    private struct LoadResult: Sendable {
        let pages: [ComicPage]
        let sizes: [Int: CGSize]
        let error: String?
    }

    private func findPreviousIssue() -> LibraryItem? {
        let all = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        let siblings = all
            .filter { $0.seriesKey == item.seriesKey }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }), index > 0 else {
            return nil
        }
        return siblings[index - 1]
    }

    private func findNextIssue() -> LibraryItem? {
        let all = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        let siblings = all
            .filter { $0.seriesKey == item.seriesKey }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }),
              index + 1 < siblings.count else { return nil }
        return siblings[index + 1]
    }

    // MARK: - Bookmarks

    private var currentPageIndex: Int {
        if isContinuous { return continuousPage }
        guard units.indices.contains(currentUnit) else { return 0 }
        return units[currentUnit].first?.index ?? 0
    }

    private var isBookmarked: Bool {
        bookmarks.contains { $0.page == currentPageIndex }
    }

    private func loadBookmarks() {
        let id = item.id
        let all = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        bookmarks = all
            .filter { $0.itemID == id }
            .sorted { $0.page < $1.page }
    }

    // MARK: - End of issue

    /// True at the last page of a chapter, or at the end of the file.
    private var isAtSectionEnd: Bool {
        if item.hasChapters, item.isChapterEnd(page: lastPageOfCurrentUnit) { return true }
        return isOnLastUnit
    }

    private var lastPageOfCurrentUnit: Int {
        guard units.indices.contains(currentUnit) else { return 0 }
        return units[currentUnit].last?.index ?? 0
    }

    /// What was just finished — a chapter inside a collection, or the whole file.
    private var finishedTitle: String {
        if item.hasChapters, let chapter = item.chapter(forPage: lastPageOfCurrentUnit) {
            return chapter.title
        }
        return item.title
    }

    /// What comes after it.
    private var upNextTitle: String? {
        if item.hasChapters {
            let marks = item.chapters
            if let index = item.chapterIndex(forPage: lastPageOfCurrentUnit),
               index + 1 < marks.count {
                return marks[index + 1].title
            }
        }
        return nextItem?.title
    }

    /// 0-based page indices where a new chapter begins.
    private var chapterStartPages: Set<Int> {
        guard item.hasChapters else { return [] }
        return Set(item.chapters.map(\.startPage))
    }

    private var chapterProgressLabel: String? {
        guard item.hasChapters,
              let index = item.chapterIndex(forPage: currentPageIndex) else { return nil }
        return "Issue \(index + 1) of \(item.chapters.count)"
    }

    private func continueFromEndCard() {
        endCardAcknowledgedUnit = currentUnit
        withAnimation(.easeOut(duration: 0.2)) { endCardVisible = false }
        turnUnit(1)
    }

    private var endOfIssueCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Finished")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CGTheme.subtext0)
                    .textCase(.uppercase)
                Text(finishedTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(CGTheme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let chapterProgressLabel {
                    Text(chapterProgressLabel)
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                }
            }

            if let upNextTitle {
                VStack(spacing: 4) {
                    Text("Up next")
                        .font(.caption)
                        .foregroundStyle(CGTheme.subtext0)
                    Text(upNextTitle)
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext1)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 12) {
                Button { onClose() } label: {
                    Label("Back to Library", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(CGTheme.subtext1)

                if upNextTitle != nil {
                    Button { continueFromEndCard() } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
                }
            }

            Button("Keep reading this page") {
                endCardAcknowledgedUnit = currentUnit
                withAnimation(.easeOut(duration: 0.2)) { endCardVisible = false }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(CGTheme.subtext0)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24)
    }

    // MARK: - Cover

    /// Scene releases often lead with a scanner credits page, so the first page
    /// isn't always the cover you want in the grid.
    private func setCoverFromCurrentPage() {
        let page = currentPageIndex
        let id = item.id
        let path = item.filePath

        coverStatus = "Updating cover…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> String? in
                try? ThumbnailGenerator.regenerate(
                    for: id, archivePath: path, pageIndex: page
                ).path
            }.value

            if let result {
                item.coverPageIndex = page
                item.coverThumbnailPath = result
                try? context.save()
                coverStatus = "Cover set to page \(page + 1)"
            } else {
                coverStatus = "Couldn't update the cover"
            }

            try? await Task.sleep(for: .seconds(2))
            coverStatus = nil
        }
    }

    // MARK: - Notes

    private func loadNotes() {
        let id = item.id
        let all = (try? context.fetch(FetchDescriptor<ComicNote>())) ?? []
        notes = all
            .filter { $0.itemID == id }
            .sorted { ($0.page ?? Int.max, $0.dateCreated) < ($1.page ?? Int.max, $1.dateCreated) }
    }

    /// Notes anchored to the page currently on screen.
    private var notesOnThisPage: [ComicNote] {
        let page = currentPageIndex + 1
        return notes.filter { $0.page == page }
    }

    /// Captures the page you're looking at, which is the whole point — an
    /// editor's note on page 13 is only findable later if the note remembers 13.
    private func addNote() {
        let note = ComicNote(
            itemID: item.id,
            itemTitle: item.title,
            page: currentPageIndex + 1
        )
        context.insert(note)
        try? context.save()
        loadNotes()
        activeNote = note
    }

    /// Right-click menu over the page.
    @ViewBuilder
    private var readerMenu: some View {
        Button { addNote() } label: {
            Label("Add Note on Page \(currentPageIndex + 1)…", systemImage: "note.text.badge.plus")
        }

        if !notesOnThisPage.isEmpty {
            Menu("Notes on This Page") {
                ForEach(notesOnThisPage) { note in
                    Button(note.displayTitle) { activeNote = note }
                }
            }
        }

        if !notes.isEmpty {
            Menu("All Notes in This Issue") {
                ForEach(notes) { note in
                    Button(noteMenuLabel(note)) {
                        if let page = note.page { jumpToPageNumber(page) }
                        activeNote = note
                    }
                }
            }
        }

        Divider()

        Button { toggleBookmark() } label: {
            Label(isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                  systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
        }

        Button { showJump = true } label: {
            Label("Jump to Page…", systemImage: "arrow.right.to.line")
        }

        Divider()

        Button { setCoverFromCurrentPage() } label: {
            Label("Set as Cover", systemImage: "photo.badge.checkmark")
        }
    }

    private func noteMenuLabel(_ note: ComicNote) -> String {
        if let pageLabel = note.pageLabel {
            return "\(pageLabel) — \(note.displayTitle)"
        }
        return note.displayTitle
    }

    /// Sidebar block listing this issue's notes.
    @ViewBuilder
    private var notesSection: some View {
        Button { addNote() } label: {
            Label("Add Note (N)", systemImage: "note.text.badge.plus")
                .font(.callout)
                .foregroundStyle(CGTheme.subtext1)
        }
        .buttonStyle(.plain)

        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)

                ForEach(notes) { note in
                    Button {
                        if let page = note.page { jumpToPageNumber(page) }
                        activeNote = note
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.displayTitle)
                                .font(.caption)
                                .foregroundStyle(CGTheme.subtext1)
                                .lineLimit(1)
                            if let pageLabel = note.pageLabel {
                                Text(pageLabel)
                                    .font(.caption2)
                                    .foregroundStyle(CGTheme.subtext0.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Notes store 1-based pages; everything internal is 0-based.
    private func jumpToPageNumber(_ page: Int) {
        let index = max(0, page - 1)
        if isContinuous {
            continuousPage = index
        } else {
            jump(to: unitIndex(containing: index))
        }
    }

    private func toggleBookmark() {
        let page = currentPageIndex
        if let existing = bookmarks.first(where: { $0.page == page }) {
            context.delete(existing)
        } else {
            context.insert(Bookmark(itemID: item.id, page: page))
        }
        try? context.save()
        loadBookmarks()
    }

    private func jumpToBookmark(_ bookmark: Bookmark) {
        if isContinuous {
            continuousPage = bookmark.page
        } else {
            jump(to: unitIndex(containing: bookmark.page))
        }
    }

    private func saveProgress() {
        guard let archive, units.indices.contains(currentUnit),
              let lastPage = units[currentUnit].last else { return }
        if item.progress == nil {
            let progress = ReadingProgress(item: item)
            context.insert(progress)
            item.progress = progress
        }
        item.progress?.update(page: lastPage.index, of: archive.pageCount)
    }
}

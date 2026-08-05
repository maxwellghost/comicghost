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
    @AppStorage("alwaysShowEdges") private var alwaysShowEdges: Bool = false
    @AppStorage("hideReaderControls") private var hideControls: Bool = false
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

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }
    private var fitMode: FitMode { FitMode(rawValue: fitModeRaw) ?? .page }

    private var adjustments: Binding<ImageAdjustments> {
        Binding(
            get: {
                ImageAdjustments(
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            if archive != nil, !units.isEmpty {
                pager
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
                            accent: accent
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
                          accent: accent, rightToLeft: isManga) { index in
                    jump(to: index)
                }
                .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) { edgeProgressBar }
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
        .task {
            await load()
            if !hasSeenControls {
                showLegend = true
                hasSeenControls = true
            }
            wakeChrome()
            startSleepPrevention()
        }
        .onDisappear {
            hideTask?.cancel()
            stopSleepPrevention()
        }
        .onChange(of: spreadEnabled) { _, _ in rebuildUnits(preservingPage: true) }
        .onChange(of: spreadOffset) { _, _ in rebuildUnits(preservingPage: true) }
        .background { shortcuts }
    }

    private var shortcuts: some View {
        Group {
            Button("") { dismissOrClose() }
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
            Button("") { adjustZoom(by: 0.5) }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { adjustZoom(by: -0.5) }
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

    private var zoomControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zoom \(Int(zoom * 100))%").font(.caption).foregroundStyle(CGTheme.subtext0)
            HStack(spacing: 8) {
                zoomButton("minus.magnifyingglass") { adjustZoom(by: -0.5) }
                zoomButton("plus.magnifyingglass") { adjustZoom(by: 0.5) }
                zoomButton("arrow.counterclockwise") { setZoom(1.0) }
            }
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
            zoom = min(max(value, 1.0), 6.0)
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
                pageCounter.opacity(chromeShown ? 1 : 0)
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

    private var pageCounter: some View {
        Button { showJump = true } label: {
            HStack(spacing: 8) {
                Text(counterText).font(.callout.monospacedDigit())
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
        zoom = 1.0
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
        zoom = 1.0
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
        let savedPage = min(item.progress?.currentPage ?? 0, max(result.pages.count - 1, 0))
        currentUnit = unitIndex(containing: savedPage)
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

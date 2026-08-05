import SwiftUI
import AppKit

enum FitMode: String {
    case page   // whole page visible
    case width  // fill width, scroll vertically
}

/// Renders one display unit — a single page or a two-page spread.
///
/// Panning works whenever the rendered content is larger than the window:
/// two-finger scroll or drag. Pinch and ⌘-scroll zoom.
struct PageView: View {
    let pages: [ComicPage]
    let fitMode: FitMode
    var rightToLeft: Bool = false
    /// Off while overlays that scroll themselves are open.
    var scrollPanningEnabled: Bool = true
    /// Fired by a horizontal trackpad swipe: +1 forward, -1 back.
    var onHorizontalSwipe: (Int) -> Void = { _ in }
    var adjustments: ImageAdjustments = .neutral
    var magnifierEnabled: Bool = false
    @Binding var zoom: CGFloat

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0

    @State private var committedZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var scrollMonitor: Any?

    // The scroll monitor's closure captures a snapshot of this view, so any
    // plain property it reads (fitMode, pages) would be frozen at the moment
    // the monitor was installed. @State is reference-backed, so the monitor
    // reads live values through these instead.
    @State private var contentSize: CGSize = .zero      // on-screen size at current zoom
    @State private var panningEnabled: Bool = true
    @State private var magnifierPoint: CGPoint?
    @State private var swipeAccum: CGFloat = 0
    @State private var swipeFired = false
    @State private var processed: [URL: NSImage] = [:]

    private var orderedPages: [ComicPage] {
        rightToLeft ? pages.reversed() : pages
    }

    private var images: [NSImage] {
        orderedPages.compactMap { page in
            processed[page.imageURL] ?? ImageCache.shared.image(for: page.imageURL)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let loaded = images
            Group {
                if loaded.count == pages.count, !loaded.isEmpty {
                    unitView(loaded, in: geo.size)
                } else {
                    ContentUnavailableView("Page failed to load", systemImage: "photo")
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .grayscale(adjustments.grayscale ? 1 : 0)
            .brightness(adjustments.brightness)
            .contrast(adjustments.contrast)
            .rotationEffect(adjustments.rotationAngle)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay {
                if magnifierEnabled, let magnifierPoint {
                    MagnifierLens(
                        images: images,
                        containerSize: geo.size,
                        contentSize: contentSize,
                        offset: offset,
                        point: magnifierPoint,
                        adjustments: adjustments
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): magnifierPoint = point
                case .ended: magnifierPoint = nil
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 2) { toggleZoom() }
            .onAppear {
                containerSize = geo.size
                applyFit(in: geo.size)
                startScrollMonitor()
            }
            .onDisappear { stopScrollMonitor() }
            .onChange(of: geo.size) { _, newSize in
                containerSize = newSize
                refreshMetrics(in: newSize)
                offset = clamp(offset)
                committedOffset = offset
            }
            // Images decode asynchronously — recompute once they arrive.
            .onChange(of: loaded.count) { _, _ in refreshMetrics(in: geo.size) }
            .onChange(of: unitID) { _, _ in
                applyFit(in: geo.size)
                swipeAccum = 0
                swipeFired = false
            }
            .onChange(of: fitMode) { _, _ in applyFit(in: geo.size) }
            .onChange(of: rightToLeft) { _, _ in applyFit(in: geo.size) }
            .onChange(of: adjustments.rotation) { _, _ in applyFit(in: geo.size) }
            .onChange(of: scrollPanningEnabled) { _, newValue in
                panningEnabled = newValue
            }
            .task(id: "\(unitID)#\(adjustments.processingSignature)") {
                await applyProcessing()
                refreshMetrics(in: containerSize)
            }
        }
    }

    private var unitID: String {
        pages.map(\.id.uuidString).joined(separator: "+")
    }

    /// Gamma, auto-contrast, and auto-crop need a pixel pass;
    /// brightness, contrast, grayscale, and rotation are cheap modifiers.
    private func applyProcessing() async {
        guard adjustments.needsProcessing else {
            if !processed.isEmpty { processed = [:] }
            return
        }
        let urls = orderedPages.map(\.imageURL)
        let settings = adjustments
        let result = await Task.detached(priority: .userInitiated) { () -> [URL: NSImage] in
            var output: [URL: NSImage] = [:]
            for url in urls {
                guard let base = ImageCache.shared.image(for: url) else { continue }
                output[url] = GammaProcessor.shared.process(
                    base, with: settings, key: url.lastPathComponent
                )
            }
            return output
        }.value
        processed = result
    }

    // MARK: - Metrics
    //
    // Everything the scroll monitor needs is mirrored into @State here.

    private func refreshMetrics(in container: CGSize) {
        contentSize = computeDisplaySize(in: container)
        panningEnabled = scrollPanningEnabled
    }

    private func computeDisplaySize(in container: CGSize) -> CGSize {
        let loaded = images
        guard !loaded.isEmpty, container.width > 0, container.height > 0 else { return .zero }

        let aspect = loaded.map { image -> CGFloat in
            let size = image.size
            return size.height > 0 ? size.width / size.height : 0.7
        }.reduce(0, +)
        guard aspect > 0 else { return container }

        let fittedHeight = min(container.height, container.width / aspect)
        let fitted = CGSize(width: fittedHeight * aspect, height: fittedHeight)

        // Fit-width blows the page up to fill the window horizontally,
        // which is what makes it taller than the window and scrollable.
        let base: CGFloat = fitMode == .width && fitted.width > 0
            ? max(container.width / fitted.width, 1.0)
            : 1.0

        return CGSize(width: fitted.width * base * zoom, height: fitted.height * base * zoom)
    }

    /// True when there's actually something off-screen to move to.
    private var canPan: Bool {
        guard containerSize.width > 0 else { return false }
        return contentSize.width - containerSize.width > 1
            || contentSize.height - containerSize.height > 1
    }

    private func clamp(_ proposed: CGSize) -> CGSize {
        let maxX = max((contentSize.width - containerSize.width) / 2, 0)
        let maxY = max((contentSize.height - containerSize.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    // MARK: - Scroll monitor

    private func startScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard panningEnabled else { return event }

            if event.modifierFlags.contains(.command) {
                setZoom(zoom * (1 + event.scrollingDeltaY * 0.006))
                return nil
            }

            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 8.0
            let dx = event.scrollingDeltaX * multiplier
            let dy = event.scrollingDeltaY * multiplier

            // Horizontal swipe turns pages when there's no width to pan.
            let canPanH = contentSize.width - containerSize.width > 1
            if !canPanH, abs(dx) > abs(dy) * 1.5 {
                accumulateSwipe(
                    event.scrollingDeltaX,
                    phase: event.phase,
                    momentum: event.momentumPhase
                )
                return nil
            }

            guard canPan else { return event }

            offset = clamp(CGSize(
                width: offset.width + dx,
                height: offset.height + dy
            ))
            committedOffset = offset
            return nil   // consumed
        }
    }

    private func stopScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        swipeAccum = 0
        swipeFired = false
    }

    /// One physical swipe turns exactly one page.
    ///
    /// A trackpad flick emits a burst of events and then a long momentum tail;
    /// treating them all as input made a light swipe skip several pages. So the
    /// momentum tail is discarded, and each gesture is allowed one page turn,
    /// tracked from its .began through its .ended phase.
    private func accumulateSwipe(_ dx: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) {
        // Ignore the coasting tail after fingers lift.
        guard momentum.isEmpty else { return }

        if phase.contains(.began) {
            swipeAccum = 0
            swipeFired = false
        }

        if phase.contains(.ended) || phase.contains(.cancelled) {
            swipeAccum = 0
            swipeFired = false
            return
        }

        guard !swipeFired else { return }

        swipeAccum += dx
        guard abs(swipeAccum) >= 55 else { return }

        // Swiping left (negative) moves forward, matching trackpad convention.
        onHorizontalSwipe(swipeAccum < 0 ? 1 : -1)
        swipeAccum = 0
        swipeFired = true
    }

    // MARK: - Rendering

    private func unitView(_ loaded: [NSImage], in container: CGSize) -> some View {
        let aspect = loaded.map { image -> CGFloat in
            let size = image.size
            return size.height > 0 ? size.width / size.height : 0.7
        }.reduce(0, +)
        let fittedHeight = aspect > 0 ? min(container.height, container.width / aspect) : container.height
        let fitted = CGSize(width: fittedHeight * max(aspect, 0.01), height: fittedHeight)
        let base: CGFloat = fitMode == .width && fitted.width > 0
            ? max(container.width / fitted.width, 1.0)
            : 1.0

        return HStack(spacing: 0) {
            ForEach(Array(loaded.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .scaleEffect(base * zoom)
        .offset(offset)
        .frame(width: container.width, height: container.height)
    }

    // MARK: - Gestures

    /// Damped so a small pinch doesn't jump hundreds of percent.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let damped = 1 + (value.magnification - 1) * 0.45
                setZoom(committedZoom * damped)
            }
            .onEnded { _ in committedZoom = zoom }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard canPan else { return }
                offset = clamp(CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                ))
            }
            .onEnded { _ in committedOffset = offset }
    }

    // MARK: - Zoom

    /// Single entry point — always refreshes metrics and re-clamps, so zooming
    /// back out can never leave the page parked off-centre.
    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, minZoom), maxZoom)
        committedZoom = zoom
        refreshMetrics(in: containerSize)
        offset = clamp(offset)
        committedOffset = offset
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.22)) {
            zoom = zoom > minZoom + 0.01 ? minZoom : 2.5
        }
        committedZoom = zoom
        refreshMetrics(in: containerSize)
        offset = zoom <= minZoom + 0.01 ? .zero : clamp(offset)
        committedOffset = offset
    }

    // MARK: - Fit

    private func applyFit(in container: CGSize) {
        zoom = 1.0
        committedZoom = 1.0
        containerSize = container
        refreshMetrics(in: container)

        if fitMode == .width {
            // Start at the top of the page.
            let maxY = max((contentSize.height - container.height) / 2, 0)
            offset = CGSize(width: 0, height: maxY)
        } else {
            offset = .zero
        }
        committedOffset = offset
    }
}

// MARK: - Magnifier

/// Circular lens that follows the cursor and shows the page at extra zoom.
struct MagnifierLens: View {
    let images: [NSImage]
    let containerSize: CGSize
    let contentSize: CGSize
    let offset: CGSize
    let point: CGPoint
    var adjustments: ImageAdjustments = .neutral

    private let diameter: CGFloat = 220
    private let extraZoom: CGFloat = 2.4

    var body: some View {
        // Where the cursor sits relative to the centre of the content.
        let dx = point.x - containerSize.width / 2 - offset.width
        let dy = point.y - containerSize.height / 2 - offset.height

        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .scaleEffect(extraZoom)
            .offset(x: -dx * extraZoom, y: -dy * extraZoom)
            .brightness(adjustments.brightness)
            .contrast(adjustments.contrast)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(CGTheme.text.opacity(0.35), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.45), radius: 14)
        .position(x: point.x, y: point.y)
        .allowsHitTesting(false)
    }
}

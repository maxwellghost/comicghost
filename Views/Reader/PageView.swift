import SwiftUI
import AppKit

enum FitMode: String {
    case page   // whole page visible
    case width  // fill width, pan vertically
}

/// Renders one display unit — a single page or a two-page spread.
/// Pinch or ⌘-scroll to zoom, two-finger scroll or drag to pan,
/// double-click to toggle 2.5×.
struct PageView: View {
    let pages: [ComicPage]
    let fitMode: FitMode
    /// Manga mode: spreads read right-to-left.
    var rightToLeft: Bool = false
    @Binding var zoom: CGFloat

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0

    @State private var committedZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    /// Display order — reversed for manga so page N sits on the right.
    private var orderedPages: [ComicPage] {
        rightToLeft ? pages.reversed() : pages
    }

    private var images: [NSImage] {
        orderedPages.compactMap { ImageCache.shared.image(for: $0.imageURL) }
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
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo.size))
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 2) { toggleZoom() }
            .background(
                ScrollEventCatcher(
                    onScroll: { delta, isPrecise in
                        handleScroll(delta, isPrecise: isPrecise, in: geo.size)
                    },
                    onZoomScroll: { delta in
                        setZoomClamped(zoom * (1 + (delta.y * 0.01)))
                    }
                )
            )
            .onChange(of: unitID) { _, _ in applyFit(in: geo.size) }
            .onChange(of: fitMode) { _, _ in applyFit(in: geo.size) }
            .onChange(of: rightToLeft) { _, _ in applyFit(in: geo.size) }
            .onAppear { applyFit(in: geo.size) }
        }
    }

    private var unitID: String {
        pages.map(\.id.uuidString).joined(separator: "+")
    }

    // MARK: - Layout

    private func combinedAspect(_ loaded: [NSImage]) -> CGFloat {
        loaded.map { image -> CGFloat in
            let size = image.size
            return size.height > 0 ? size.width / size.height : 0.7
        }.reduce(0, +)
    }

    private func fittedSize(_ loaded: [NSImage], in container: CGSize) -> CGSize {
        let aspect = combinedAspect(loaded)
        guard aspect > 0 else { return container }
        let height = min(container.height, container.width / aspect)
        return CGSize(width: height * aspect, height: height)
    }

    private func baseScale(_ loaded: [NSImage], in container: CGSize) -> CGFloat {
        guard fitMode == .width else { return 1.0 }
        let fitted = fittedSize(loaded, in: container)
        guard fitted.width > 0 else { return 1.0 }
        return max(container.width / fitted.width, 1.0)
    }

    private func unitView(_ loaded: [NSImage], in container: CGSize) -> some View {
        let fitted = fittedSize(loaded, in: container)
        let base = baseScale(loaded, in: container)

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

    // MARK: - Scroll panning

    private func handleScroll(_ delta: CGPoint, isPrecise: Bool, in container: CGSize) {
        guard canPan(in: container) else { return }
        let multiplier: CGFloat = isPrecise ? 1.0 : 6.0
        let proposed = CGSize(
            width: offset.width + delta.x * multiplier,
            height: offset.height + delta.y * multiplier
        )
        offset = clamp(proposed, in: container)
        committedOffset = offset
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in setZoomClamped(committedZoom * value.magnification) }
            .onEnded { _ in committedZoom = zoom }
    }

    private func setZoomClamped(_ value: CGFloat) {
        zoom = min(max(value, minZoom), maxZoom)
        committedZoom = zoom
    }

    private func dragGesture(in container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard canPan(in: container) else { return }
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clamp(proposed, in: container)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func canPan(in container: CGSize) -> Bool {
        zoom > 1.01 || fitMode == .width
    }

    private func clamp(_ proposed: CGSize, in container: CGSize) -> CGSize {
        let loaded = images
        let fitted = fittedSize(loaded, in: container)
        let base = baseScale(loaded, in: container)
        let displayW = fitted.width * base * zoom
        let displayH = fitted.height * base * zoom
        let maxX = max((displayW - container.width) / 2, 0)
        let maxY = max((displayH - container.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    // MARK: - Fit & zoom state

    private func applyFit(in container: CGSize) {
        zoom = 1.0
        committedZoom = 1.0

        if fitMode == .width {
            let loaded = images
            let fitted = fittedSize(loaded, in: container)
            let base = baseScale(loaded, in: container)
            let maxY = max((fitted.height * base - container.height) / 2, 0)
            offset = CGSize(width: 0, height: maxY)
        } else {
            offset = .zero
        }
        committedOffset = offset
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.25)) {
            if zoom > minZoom + 0.01 {
                zoom = minZoom
                offset = .zero
            } else {
                zoom = 2.5
            }
        }
        committedZoom = zoom
        committedOffset = offset
    }
}

// MARK: - Scroll wheel bridge

/// Transparent AppKit view that forwards scroll events to SwiftUI.
struct ScrollEventCatcher: NSViewRepresentable {
    var onScroll: (CGPoint, Bool) -> Void
    var onZoomScroll: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        view.onZoomScroll = onZoomScroll
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onZoomScroll = onZoomScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGPoint, Bool) -> Void)?
        var onZoomScroll: ((CGPoint) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            if event.modifierFlags.contains(.command) {
                onZoomScroll?(delta)
            } else {
                onScroll?(delta, event.hasPreciseScrollingDeltas)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

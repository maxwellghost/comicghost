import SwiftUI

/// Continuous mode — every page stacked vertically in one scroll view.
/// Suits webtoons and anyone who'd rather scroll than turn pages.
struct ContinuousPagesView: View {
    let pages: [ComicPage]
    let adjustments: ImageAdjustments
    /// Width the pages are drawn at, as a fraction of the window.
    var widthFraction: CGFloat = 1.0
    @Binding var currentPage: Int

    @State private var visiblePages: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(pages) { page in
                            ContinuousPage(
                                page: page,
                                width: geo.size.width * widthFraction,
                                adjustments: adjustments
                            )
                            .id(page.index)
                            .onAppear {
                                visiblePages.insert(page.index)
                                updateCurrent()
                            }
                            .onDisappear {
                                visiblePages.remove(page.index)
                                updateCurrent()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    // Resume where the reader left off.
                    proxy.scrollTo(currentPage, anchor: .top)
                }
            }
        }
    }

    /// Topmost visible page wins — that's what you're reading.
    private func updateCurrent() {
        guard let top = visiblePages.min() else { return }
        if top != currentPage { currentPage = top }
    }
}

private struct ContinuousPage: View {
    let page: ComicPage
    let width: CGFloat
    let adjustments: ImageAdjustments

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .grayscale(adjustments.grayscale ? 1 : 0)
                    .brightness(adjustments.brightness)
                    .contrast(adjustments.contrast)
                    .rotationEffect(adjustments.rotationAngle)
            } else {
                Rectangle()
                    .fill(CGTheme.surface0.opacity(0.4))
                    .frame(width: width, height: width * 1.5)
                    .overlay {
                        ProgressView().controlSize(.small)
                    }
            }
        }
        .task(id: adjustments.processingSignature) { await load() }
    }

    private func load() async {
        let url = page.imageURL
        let settings = adjustments
        let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let base = ImageCache.shared.image(for: url) else { return nil }
            return GammaProcessor.shared.process(
                base, with: settings, key: url.lastPathComponent
            )
        }.value
        image = loaded
    }
}

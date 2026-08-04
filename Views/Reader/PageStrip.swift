import SwiftUI

/// Filmstrip of page thumbnails across the bottom of the reader.
struct PageStrip: View {
    let units: [[ComicPage]]
    let currentUnit: Int
    var accent: Color = CGTheme.mauve
    /// Manga mode: strip runs right-to-left.
    var rightToLeft: Bool = false
    var onSelect: (Int) -> Void

    private var displayOrder: [Int] {
        let indices = Array(units.indices)
        return rightToLeft ? indices.reversed() : indices
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayOrder, id: \.self) { index in
                        thumbnail(units[index], index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear { proxy.scrollTo(currentUnit, anchor: .center) }
            .onChange(of: currentUnit) { _, newValue in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 132)
    }

    private func thumbnail(_ unit: [ComicPage], index: Int) -> some View {
        let isCurrent = index == currentUnit
        let ordered = rightToLeft ? Array(unit.reversed()) : unit

        return Button {
            onSelect(index)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 1) {
                    ForEach(ordered) { page in
                        PageThumb(url: page.imageURL)
                    }
                }
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isCurrent ? accent : CGTheme.surface1, lineWidth: isCurrent ? 2 : 1)
                }
                .softGlow(accent, radius: 8, isActive: isCurrent)

                Text(label(for: unit))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(isCurrent ? CGTheme.text : CGTheme.subtext0)
            }
        }
        .buttonStyle(.plain)
    }

    private func label(for unit: [ComicPage]) -> String {
        if unit.count == 2, let first = unit.first, let last = unit.last {
            return "\(first.index + 1)–\(last.index + 1)"
        }
        return "\((unit.first?.index ?? 0) + 1)"
    }
}

private struct PageThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(CGTheme.surface0)
                    .frame(width: 56)
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            image = await Task.detached(priority: .utility) {
                ImageCache.shared.thumbnail(for: url, maxPixel: 180)
            }.value
        }
    }
}

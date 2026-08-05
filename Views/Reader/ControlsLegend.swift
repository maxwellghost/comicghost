import SwiftUI

/// Keyboard/gesture cheat sheet for the reader.
struct ControlsLegend: View {
    var glassEnabled: Bool
    var rightToLeft: Bool = false
    var onDismiss: () -> Void

    private var controls: [(symbol: String, keys: String, action: String)] {
        [
            ("arrow.left.arrow.right", "← → / A D",
             rightToLeft ? "Next / previous page (manga)" : "Previous / next page"),
            ("cursorarrow.click", "Click edges", "Turn page"),
            ("number", "G / click counter", "Jump to page"),
            ("magnifyingglass", "Pinch", "Zoom in and out"),
            ("cursorarrow.motionlines", "Drag / scroll", "Pan while zoomed"),
            ("cursorarrow.click.2", "Double-click", "Toggle 2.5× zoom"),
            ("plus.forwardslash.minus", "⌘+ ⌘− ⌘0", "Zoom in / out / fit"),
            ("arrow.left.and.right.square", "F", "Fit page / fit width"),
            ("book", "S", "Single page / spread"),
            ("scroll", "C", "Paged / continuous scroll"),
            ("bookmark", "B", "Bookmark this page"),
            ("slider.horizontal.3", "I", "Image adjustments"),
            ("magnifyingglass.circle", "L", "Floating magnifier"),
            ("eye.slash", "H", "Hide / show controls"),
            ("hand.draw", "Swipe", "Turn pages on trackpad"),
            ("character.book.closed.ja", "M", "Manga mode (right-to-left)"),
            ("rectangle.grid.1x2", "T", "Page thumbnails"),
            ("arrow.up.left.and.arrow.down.right", "⌃⌘F", "Full screen"),
            ("sidebar.left", "Hover left edge", "Show navigation pane"),
            ("escape", "Esc", "Back to library"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Controls").font(.headline).foregroundStyle(CGTheme.text)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(CGTheme.subtext0)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(controls, id: \.action) { control in
                    HStack(spacing: 12) {
                        Image(systemName: control.symbol)
                            .font(.callout)
                            .foregroundStyle(CGTheme.mauve)
                            .frame(width: 22)

                        Text(control.keys)
                            .font(.caption.monospaced())
                            .foregroundStyle(CGTheme.text)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(CGTheme.surface0.opacity(glassEnabled ? 0.75 : 1))
                            }
                            .frame(width: 118, alignment: .leading)

                        Text(control.action)
                            .font(.callout)
                            .foregroundStyle(CGTheme.subtext1)

                        Spacer(minLength: 0)
                    }
                }
            }

            Text("Press ? anytime to bring this back")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)
        }
        .padding(22)
        .frame(width: 430, alignment: .leading)
        .glassPanel(enabled: glassEnabled, fallback: CGTheme.mantle, cornerRadius: 14)
        .softGlow(CGTheme.mauve, radius: 18)
    }
}

/// Faint chevron that fades in on hover, so the click zones are discoverable.
struct PageTurnHint: View {
    let symbol: String
    var isVisible: Bool
    /// Shown but faded, for the always-visible edges setting.
    var dimmed: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(CGTheme.text.opacity(0.85))
            .padding(14)
            .background { Circle().fill(.ultraThinMaterial) }
            .softGlow(CGTheme.mauve, radius: 10, isActive: isVisible && !dimmed)
            .opacity(isVisible ? (dimmed ? 0.35 : 1) : 0)
            .animation(.easeOut(duration: 0.18), value: isVisible)
            .animation(.easeOut(duration: 0.18), value: dimmed)
    }
}

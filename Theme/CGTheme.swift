import SwiftUI

/// Catppuccin Mocha palette + shared style helpers for Comic Ghost.
/// Palette for the active theme. Every colour reads from the current
/// selection, so switching themes recolours the whole app.
enum CGTheme {
    private static var t: CGThemeDefinition { CGThemeCatalog.current }

    static var crust: Color    { Color(hex: t.crust) }
    static var mantle: Color   { Color(hex: t.mantle) }
    static var base: Color     { Color(hex: t.base) }
    static var surface0: Color { Color(hex: t.surface0) }
    static var surface1: Color { Color(hex: t.surface1) }

    static var text: Color     { Color(hex: t.text) }
    static var subtext1: Color { Color(hex: t.subtext1) }
    static var subtext0: Color { Color(hex: t.subtext0) }

    static var mauve: Color    { Color(hex: t.mauve) }
    static var lavender: Color { Color(hex: t.lavender) }
    static var pink: Color     { Color(hex: t.pink) }
    static var sky: Color      { Color(hex: t.sky) }
    static var sapphire: Color { Color(hex: t.sapphire) }
    static var green: Color    { Color(hex: t.green) }
    static var red: Color      { Color(hex: t.red) }
    static var peach: Color    { Color(hex: t.peach) }
    static var teal: Color     { Color(hex: t.teal) }

    /// Whether the active theme is a dark one — drives colour scheme.
    static var isDark: Bool { t.isDark }

    /// Current accent, resolved from user preference.
    static var accent: Color { CGAccent.current.color }
}

/// User-selectable accent color.
enum CGAccent: String, CaseIterable, Identifiable {
    case mauve, lavender, pink, sky, teal, green, peach

    static let key = "accentColor"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .mauve: return CGTheme.mauve
        case .lavender: return CGTheme.lavender
        case .pink: return CGTheme.pink
        case .sky: return CGTheme.sky
        case .teal: return CGTheme.teal
        case .green: return CGTheme.green
        case .peach: return CGTheme.peach
        }
    }

    var label: String { rawValue.capitalized }

    static var current: CGAccent {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let accent = CGAccent(rawValue: raw) else { return .mauve }
        return accent
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue:  Double(hex & 0xff) / 255
        )
    }
}

// MARK: - Glass

enum CGGlass {
    static let key = "useGlassEffect"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

struct GlassPanel: ViewModifier {
    var enabled: Bool
    var fallback: Color
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        if enabled {
            content.background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(fallback.opacity(0.35))
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            content.background {
                fallback.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}

extension View {
    func glassPanel(enabled: Bool, fallback: Color, cornerRadius: CGFloat = 0) -> some View {
        modifier(GlassPanel(enabled: enabled, fallback: fallback, cornerRadius: cornerRadius))
    }
}

// MARK: - Glow

struct SoftGlow: ViewModifier {
    var color: Color = CGTheme.mauve
    var radius: CGFloat = 12
    var isActive: Bool = true

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: radius)
            .shadow(color: isActive ? color.opacity(0.18) : .clear, radius: radius * 2.2)
    }
}

extension View {
    func softGlow(_ color: Color = CGTheme.mauve, radius: CGFloat = 12, isActive: Bool = true) -> some View {
        modifier(SoftGlow(color: color, radius: radius, isActive: isActive))
    }
}

// MARK: - Loading skeleton

/// Shimmering placeholder used while covers decode.
struct SkeletonBox: View {
    var cornerRadius: CGFloat = 8
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(CGTheme.surface0)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, CGTheme.surface1.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

import SwiftUI

/// Catppuccin Mocha palette + shared style helpers for Comic Ghost.
enum CGTheme {
    static let crust  = Color(hex: 0x11111b)
    static let mantle = Color(hex: 0x181825)
    static let base   = Color(hex: 0x1e1e2e)
    static let surface0 = Color(hex: 0x313244)
    static let surface1 = Color(hex: 0x45475a)

    static let text     = Color(hex: 0xcdd6f4)
    static let subtext1 = Color(hex: 0xbac2de)
    static let subtext0 = Color(hex: 0xa6adc8)

    static let mauve    = Color(hex: 0xcba6f7)
    static let lavender = Color(hex: 0xb4befe)
    static let pink     = Color(hex: 0xf5c2e7)
    static let sky      = Color(hex: 0x89dceb)
    static let sapphire = Color(hex: 0x74c7ec)
    static let green    = Color(hex: 0xa6e3a1)
    static let red      = Color(hex: 0xf38ba8)
    static let peach    = Color(hex: 0xfab387)
    static let teal     = Color(hex: 0x94e2d5)

    /// Current accent, resolved from user preference.
    static var accent: Color {
        CGAccent.current.color
    }
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

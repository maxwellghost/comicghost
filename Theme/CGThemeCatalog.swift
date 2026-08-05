import SwiftUI

/// A complete palette. Field names follow Catppuccin's vocabulary since that's
/// what the app was built against; other schemes map their nearest equivalents.
struct CGThemeDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let family: String
    let isDark: Bool

    // Surfaces, darkest to lightest
    let crust: UInt32
    let mantle: UInt32
    let base: UInt32
    let surface0: UInt32
    let surface1: UInt32

    // Text
    let text: UInt32
    let subtext1: UInt32
    let subtext0: UInt32

    // Accents
    let mauve: UInt32
    let lavender: UInt32
    let pink: UInt32
    let sky: UInt32
    let sapphire: UInt32
    let green: UInt32
    let red: UInt32
    let peach: UInt32
    let teal: UInt32
}

enum CGThemeCatalog {
    static let key = "appTheme"

    static var current: CGThemeDefinition {
        let id = UserDefaults.standard.string(forKey: key) ?? "mocha"
        return all.first { $0.id == id } ?? all[0]
    }

    static var families: [String] {
        var seen: [String] = []
        for theme in all where !seen.contains(theme.family) { seen.append(theme.family) }
        return seen
    }

    static func themes(in family: String) -> [CGThemeDefinition] {
        all.filter { $0.family == family }
    }

    static let all: [CGThemeDefinition] = [
        // MARK: Catppuccin
        CGThemeDefinition(
            id: "mocha", name: "Mocha", family: "Catppuccin", isDark: true,
            crust: 0x11111b, mantle: 0x181825, base: 0x1e1e2e, surface0: 0x313244, surface1: 0x45475a,
            text: 0xcdd6f4, subtext1: 0xbac2de, subtext0: 0xa6adc8,
            mauve: 0xcba6f7, lavender: 0xb4befe, pink: 0xf5c2e7, sky: 0x89dceb,
            sapphire: 0x74c7ec, green: 0xa6e3a1, red: 0xf38ba8, peach: 0xfab387, teal: 0x94e2d5
        ),
        CGThemeDefinition(
            id: "macchiato", name: "Macchiato", family: "Catppuccin", isDark: true,
            crust: 0x181926, mantle: 0x1e2030, base: 0x24273a, surface0: 0x363a4f, surface1: 0x494d64,
            text: 0xcad3f5, subtext1: 0xb8c0e0, subtext0: 0xa5adcb,
            mauve: 0xc6a0f6, lavender: 0xb7bdf8, pink: 0xf5bde6, sky: 0x91d7e3,
            sapphire: 0x7dc4e4, green: 0xa6da95, red: 0xed8796, peach: 0xf5a97f, teal: 0x8bd5ca
        ),
        CGThemeDefinition(
            id: "frappe", name: "Frappé", family: "Catppuccin", isDark: true,
            crust: 0x232634, mantle: 0x292c3c, base: 0x303446, surface0: 0x414559, surface1: 0x51576d,
            text: 0xc6d0f5, subtext1: 0xb5bfe2, subtext0: 0xa5adce,
            mauve: 0xca9ee6, lavender: 0xbabbf1, pink: 0xf4b8e4, sky: 0x99d1db,
            sapphire: 0x85c1dc, green: 0xa6d189, red: 0xe78284, peach: 0xef9f76, teal: 0x81c8be
        ),
        CGThemeDefinition(
            id: "latte", name: "Latte", family: "Catppuccin", isDark: false,
            crust: 0xdce0e8, mantle: 0xe6e9ef, base: 0xeff1f5, surface0: 0xccd0da, surface1: 0xbcc0cc,
            text: 0x4c4f69, subtext1: 0x5c5f77, subtext0: 0x6c6f85,
            mauve: 0x8839ef, lavender: 0x7287fd, pink: 0xea76cb, sky: 0x04a5e5,
            sapphire: 0x209fb5, green: 0x40a02b, red: 0xd20f39, peach: 0xfe640b, teal: 0x179299
        ),

        // MARK: Nord
        CGThemeDefinition(
            id: "nord", name: "Nord", family: "Nord", isDark: true,
            crust: 0x242933, mantle: 0x2e3440, base: 0x3b4252, surface0: 0x434c5e, surface1: 0x4c566a,
            text: 0xeceff4, subtext1: 0xe5e9f0, subtext0: 0xd8dee9,
            mauve: 0xb48ead, lavender: 0x81a1c1, pink: 0xb48ead, sky: 0x88c0d0,
            sapphire: 0x5e81ac, green: 0xa3be8c, red: 0xbf616a, peach: 0xd08770, teal: 0x8fbcbb
        ),
        CGThemeDefinition(
            id: "nord-light", name: "Snow Storm", family: "Nord", isDark: false,
            crust: 0xc8ced9, mantle: 0xd8dee9, base: 0xeceff4, surface0: 0xdfe4ec, surface1: 0xc8ced9,
            text: 0x2e3440, subtext1: 0x3b4252, subtext0: 0x4c566a,
            mauve: 0xa4638f, lavender: 0x5e81ac, pink: 0xa4638f, sky: 0x2f7c94,
            sapphire: 0x5e81ac, green: 0x6a8a4f, red: 0xa4343e, peach: 0xb0603f, teal: 0x4a8c8a
        ),

        // MARK: Gruvbox
        CGThemeDefinition(
            id: "gruvbox", name: "Gruvbox Dark", family: "Gruvbox", isDark: true,
            crust: 0x1d2021, mantle: 0x282828, base: 0x32302f, surface0: 0x3c3836, surface1: 0x504945,
            text: 0xebdbb2, subtext1: 0xd5c4a1, subtext0: 0xbdae93,
            mauve: 0xd3869b, lavender: 0x83a598, pink: 0xd3869b, sky: 0x83a598,
            sapphire: 0x458588, green: 0xb8bb26, red: 0xfb4934, peach: 0xfe8019, teal: 0x8ec07c
        ),
        CGThemeDefinition(
            id: "gruvbox-light", name: "Gruvbox Light", family: "Gruvbox", isDark: false,
            crust: 0xd5c4a1, mantle: 0xebdbb2, base: 0xfbf1c7, surface0: 0xebdbb2, surface1: 0xd5c4a1,
            text: 0x3c3836, subtext1: 0x504945, subtext0: 0x665c54,
            mauve: 0xb16286, lavender: 0x458588, pink: 0xb16286, sky: 0x076678,
            sapphire: 0x458588, green: 0x79740e, red: 0x9d0006, peach: 0xaf3a03, teal: 0x427b58
        ),

        // MARK: Dracula
        CGThemeDefinition(
            id: "dracula", name: "Dracula", family: "Dracula", isDark: true,
            crust: 0x191a21, mantle: 0x21222c, base: 0x282a36, surface0: 0x343746, surface1: 0x44475a,
            text: 0xf8f8f2, subtext1: 0xe2e2dc, subtext0: 0x6272a4,
            mauve: 0xbd93f9, lavender: 0xbd93f9, pink: 0xff79c6, sky: 0x8be9fd,
            sapphire: 0x6272a4, green: 0x50fa7b, red: 0xff5555, peach: 0xffb86c, teal: 0x8be9fd
        ),

        // MARK: Kanagawa
        CGThemeDefinition(
            id: "kanagawa", name: "Wave", family: "Kanagawa", isDark: true,
            crust: 0x16161d, mantle: 0x1f1f28, base: 0x2a2a37, surface0: 0x363646, surface1: 0x54546d,
            text: 0xdcd7ba, subtext1: 0xc8c093, subtext0: 0x727169,
            mauve: 0x957fb8, lavender: 0x7e9cd8, pink: 0xd27e99, sky: 0x7fb4ca,
            sapphire: 0x658594, green: 0x98bb6c, red: 0xe82424, peach: 0xffa066, teal: 0x7aa89f
        ),
        CGThemeDefinition(
            id: "kanagawa-lotus", name: "Lotus", family: "Kanagawa", isDark: false,
            crust: 0xd5cea3, mantle: 0xe5ddb0, base: 0xf2ecbc, surface0: 0xe7dba0, surface1: 0xdcd5ac,
            text: 0x545464, subtext1: 0x43436c, subtext0: 0x8a8980,
            mauve: 0x624c83, lavender: 0x4d699b, pink: 0xb35b79, sky: 0x6693bf,
            sapphire: 0x5d57a3, green: 0x6f894e, red: 0xc84053, peach: 0xcc6d00, teal: 0x597b75
        ),

        // MARK: Tokyo Night
        CGThemeDefinition(
            id: "tokyonight", name: "Tokyo Night", family: "Tokyo Night", isDark: true,
            crust: 0x16161e, mantle: 0x1a1b26, base: 0x24283b, surface0: 0x292e42, surface1: 0x414868,
            text: 0xc0caf5, subtext1: 0xa9b1d6, subtext0: 0x787c99,
            mauve: 0xbb9af7, lavender: 0x7aa2f7, pink: 0xf7768e, sky: 0x7dcfff,
            sapphire: 0x2ac3de, green: 0x9ece6a, red: 0xf7768e, peach: 0xff9e64, teal: 0x73daca
        ),
        CGThemeDefinition(
            id: "tokyonight-day", name: "Tokyo Night Day", family: "Tokyo Night", isDark: false,
            crust: 0xc4c8da, mantle: 0xd0d5e3, base: 0xe1e2e7, surface0: 0xd0d5e3, surface1: 0xa8aecb,
            text: 0x3760bf, subtext1: 0x6172b0, subtext0: 0x848cb5,
            mauve: 0x9854f1, lavender: 0x2e7de9, pink: 0xd20065, sky: 0x007197,
            sapphire: 0x007197, green: 0x587539, red: 0xf52a65, peach: 0xb15c00, teal: 0x118c74
        ),

        // MARK: Rosé Pine
        CGThemeDefinition(
            id: "rosepine", name: "Rosé Pine", family: "Rosé Pine", isDark: true,
            crust: 0x191724, mantle: 0x1f1d2e, base: 0x26233a, surface0: 0x2a273f, surface1: 0x403d52,
            text: 0xe0def4, subtext1: 0x908caa, subtext0: 0x6e6a86,
            mauve: 0xc4a7e7, lavender: 0xc4a7e7, pink: 0xebbcba, sky: 0x9ccfd8,
            sapphire: 0x31748f, green: 0x9ccfd8, red: 0xeb6f92, peach: 0xf6c177, teal: 0x9ccfd8
        ),
        CGThemeDefinition(
            id: "rosepine-dawn", name: "Dawn", family: "Rosé Pine", isDark: false,
            crust: 0xdfdad9, mantle: 0xfffaf3, base: 0xfaf4ed, surface0: 0xf2e9e1, surface1: 0xdfdad9,
            text: 0x575279, subtext1: 0x797593, subtext0: 0x9893a5,
            mauve: 0x907aa9, lavender: 0x907aa9, pink: 0xd7827e, sky: 0x56949f,
            sapphire: 0x286983, green: 0x56949f, red: 0xb4637a, peach: 0xea9d34, teal: 0x56949f
        ),

        // MARK: Everforest
        CGThemeDefinition(
            id: "everforest", name: "Everforest Dark", family: "Everforest", isDark: true,
            crust: 0x1e2326, mantle: 0x232a2e, base: 0x2d353b, surface0: 0x343f44, surface1: 0x3d484d,
            text: 0xd3c6aa, subtext1: 0x9da9a0, subtext0: 0x859289,
            mauve: 0xd699b6, lavender: 0x7fbbb3, pink: 0xd699b6, sky: 0x7fbbb3,
            sapphire: 0x7fbbb3, green: 0xa7c080, red: 0xe67e80, peach: 0xe69875, teal: 0x83c092
        ),
        CGThemeDefinition(
            id: "everforest-light", name: "Everforest Light", family: "Everforest", isDark: false,
            crust: 0xe0dcc7, mantle: 0xefebd4, base: 0xfdf6e3, surface0: 0xf4f0d9, surface1: 0xe0dcc7,
            text: 0x5c6a72, subtext1: 0x829181, subtext0: 0x939f91,
            mauve: 0xdf69ba, lavender: 0x3a94c5, pink: 0xdf69ba, sky: 0x3a94c5,
            sapphire: 0x3a94c5, green: 0x8da101, red: 0xf85552, peach: 0xf57d26, teal: 0x35a77c
        ),

        // MARK: One
        CGThemeDefinition(
            id: "onedark", name: "One Dark", family: "One", isDark: true,
            crust: 0x1e2127, mantle: 0x21252b, base: 0x282c34, surface0: 0x31353f, surface1: 0x3e4451,
            text: 0xabb2bf, subtext1: 0x9da5b4, subtext0: 0x828997,
            mauve: 0xc678dd, lavender: 0x61afef, pink: 0xc678dd, sky: 0x56b6c2,
            sapphire: 0x61afef, green: 0x98c379, red: 0xe06c75, peach: 0xd19a66, teal: 0x56b6c2
        ),
        CGThemeDefinition(
            id: "onelight", name: "One Light", family: "One", isDark: false,
            crust: 0xd4d4d4, mantle: 0xe8e8e9, base: 0xfafafa, surface0: 0xeaeaeb, surface1: 0xd4d4d4,
            text: 0x383a42, subtext1: 0x4f525e, subtext0: 0x696c77,
            mauve: 0xa626a4, lavender: 0x4078f2, pink: 0xa626a4, sky: 0x0184bc,
            sapphire: 0x4078f2, green: 0x50a14f, red: 0xe45649, peach: 0xc18401, teal: 0x0997b3
        ),

        // MARK: SNES
        CGThemeDefinition(
            id: "snes-dark", name: "Super Purple", family: "SNES", isDark: true,
            crust: 0x1a1424, mantle: 0x231a30, base: 0x2e2340, surface0: 0x3d2f54, surface1: 0x4d3b6b,
            text: 0xe8e4f0, subtext1: 0xc9c2da, subtext0: 0xa89fc0,
            mauve: 0xb48ee8, lavender: 0x9d8ad6, pink: 0xe0a3d6, sky: 0x8ab6e8,
            sapphire: 0x6f96cc, green: 0x9dd68a, red: 0xe88a9d, peach: 0xe8b48a, teal: 0x8ad6c9
        ),
        CGThemeDefinition(
            id: "snes-light", name: "Super Grey", family: "SNES", isDark: false,
            crust: 0xcfcbd6, mantle: 0xe0dde6, base: 0xefedf2, surface0: 0xdedae6, surface1: 0xc9c3d6,
            text: 0x3a2f4d, subtext1: 0x4f4266, subtext0: 0x6b5f80,
            mauve: 0x6b3fa0, lavender: 0x5b4b96, pink: 0xa03f8c, sky: 0x2f6ba0,
            sapphire: 0x3f5b96, green: 0x3f8c4d, red: 0xa03f52, peach: 0xa06b2f, teal: 0x2f8c7d
        ),
    ]
}

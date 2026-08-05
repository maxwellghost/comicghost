import SwiftUI
import SwiftData

@main
struct ComicGhostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Reading the stored theme here means changing it re-renders everything,
    /// since CGTheme's colours are computed from the current selection.
    @AppStorage(CGThemeCatalog.key) private var themeID: String = "mocha"

    private var theme: CGThemeDefinition {
        CGThemeCatalog.all.first { $0.id == themeID } ?? CGThemeCatalog.all[0]
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(theme.isDark ? .dark : .light)
                .background(CGTheme.base)
                .tint(CGTheme.accent)
        }
        .modelContainer(ModelContainerSetup.shared)
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .preferredColorScheme(theme.isDark ? .dark : .light)
                .tint(CGTheme.accent)
        }
    }
}

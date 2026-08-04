import SwiftUI
import SwiftData

@main
struct ComicGhostApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .preferredColorScheme(.dark)
                .background(CGTheme.base)
        }
        .modelContainer(ModelContainerSetup.shared)
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}

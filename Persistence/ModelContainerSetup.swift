import Foundation
import SwiftData
import AppKit

enum ModelContainerSetup {
    static let shared: ModelContainer = {
        let schema = Schema([
            LibraryItem.self,
            ReadingProgress.self,
            SmartCollection.self,
            ComicLibrary.self,
            Bookmark.self,
            ComicLabel.self,
            ComicLabel.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            // Enables ⌘Z / ⇧⌘Z for library edits.
            container.mainContext.undoManager = UndoManager()
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

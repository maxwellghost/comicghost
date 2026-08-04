import Foundation
import SwiftData

enum ModelContainerSetup {
    static let shared: ModelContainer = {
        let schema = Schema([
            LibraryItem.self,
            ReadingProgress.self,
            SmartCollection.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

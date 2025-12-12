import SwiftData
import SwiftUI

@main
struct Packing_ListApp: App { // swiftlint:disable:this type_name
    init() {
        // Install touch observer on app launch
        TouchBeginObserver.shared.install()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PackingList.self,
            ChecklistItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(self.sharedModelContainer)
    }
}

import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ListView(isTemplate: false)
                .tabItem {
                    Label("Trips", systemImage: "airplane")
                }

            ListView(isTemplate: true)
                .tabItem {
                    Label("Templates", systemImage: "list.bullet.clipboard")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PackingList.self, inMemory: true)
}

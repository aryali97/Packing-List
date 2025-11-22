import SwiftUI
import SwiftData

struct ListView: View {
    var isTemplate: Bool
    
    @Query private var packingLists: [PackingList]
    @Environment(\.modelContext) private var modelContext
    
    init(isTemplate: Bool) {
        self.isTemplate = isTemplate
        // Filter the query based on whether we are showing templates or trips
        _packingLists = Query(filter: #Predicate<PackingList> { list in
            list.isTemplate == isTemplate
        }, sort: \PackingList.name)
    }
    
    @State private var showCreateTripSheet = false
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(packingLists) { list in
                        NavigationLink(destination: DetailView(packingList: list)) {
                            PackingListCard(packingList: list)
                        }
                        .buttonStyle(.plain) // Removes default button styling
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(list)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(isTemplate ? "Templates" : "Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateTripSheet) {
                CreateTripView()
            }
        }
    }

    private func addItem() {
        if isTemplate {
            withAnimation {
                let newItem = PackingList(name: "", isTemplate: true)
                modelContext.insert(newItem)
            }
        } else {
            showCreateTripSheet = true
        }
    }

}

#Preview {
    ListView(isTemplate: true)
        .modelContainer(for: PackingList.self, inMemory: true)
}

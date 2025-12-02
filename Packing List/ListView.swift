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
    @State private var selectedListForNavigation: PackingList?
    @State private var navigateToDetail = false
    @State private var startEditingName = false

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
                CreateTripView { newTrip in
                    navigateToDetail(for: newTrip, shouldStartEditing: true)
                }
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                if let selectedListForNavigation {
                    DetailView(packingList: selectedListForNavigation, startEditingName: startEditingName)
                }
            }
        }
    }

    private func addItem() {
        if isTemplate {
            withAnimation {
                let newItem = PackingList(name: "", isTemplate: true)
                modelContext.insert(newItem)
                navigateToDetail(for: newItem, shouldStartEditing: true)
            }
        } else {
            showCreateTripSheet = true
        }
    }

    private func navigateToDetail(for list: PackingList, shouldStartEditing: Bool) {
        selectedListForNavigation = list
        startEditingName = shouldStartEditing
        navigateToDetail = true
    }

}

#Preview {
    ListView(isTemplate: true)
        .modelContainer(for: PackingList.self, inMemory: true)
}

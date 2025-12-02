import SwiftData
import SwiftUI

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
        GridItem(.flexible()),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: self.columns, spacing: 16) {
                    ForEach(self.packingLists) { list in
                        NavigationLink(destination: DetailView(packingList: list)) {
                            PackingListCard(packingList: list)
                        }
                        .buttonStyle(.plain) // Removes default button styling
                        .contextMenu {
                            Button(role: .destructive) {
                                self.modelContext.delete(list)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(self.isTemplate ? "Templates" : "Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: self.addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: self.$showCreateTripSheet) {
                CreateTripView { newTrip in
                    self.navigateToDetail(for: newTrip, shouldStartEditing: true)
                }
            }
            .navigationDestination(isPresented: self.$navigateToDetail) {
                if let selectedListForNavigation {
                    DetailView(packingList: selectedListForNavigation, startEditingName: self.startEditingName)
                }
            }
        }
    }

    private func addItem() {
        if self.isTemplate {
            withAnimation {
                let newItem = PackingList(name: "", isTemplate: true)
                self.modelContext.insert(newItem)
                self.navigateToDetail(for: newItem, shouldStartEditing: true)
            }
        } else {
            self.showCreateTripSheet = true
        }
    }

    private func navigateToDetail(for list: PackingList, shouldStartEditing: Bool) {
        self.selectedListForNavigation = list
        self.startEditingName = shouldStartEditing
        self.navigateToDetail = true
    }
}

#Preview {
    ListView(isTemplate: true)
        .modelContainer(for: PackingList.self, inMemory: true)
}

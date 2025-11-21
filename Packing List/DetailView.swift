import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var packingList: PackingList
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            Section {
                TextField("List Name", text: $packingList.name)
                    .font(.headline)
                
                if !packingList.isTemplate {
                    DatePicker("Trip Date", selection: Binding(get: {
                        packingList.tripDate ?? Date()
                    }, set: {
                        packingList.tripDate = $0
                    }), displayedComponents: .date)
                }
            }
            
            Section("Items") {
                ForEach(packingList.items.sorted(by: { $0.title < $1.title })) { item in
                    ChecklistRowView(item: item)
                }
                .onDelete(perform: deleteItems)
                
                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .navigationTitle(packingList.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func addItem() {
        let newItem = ChecklistItem(title: "New Item")
        newItem.packingList = packingList
        modelContext.insert(newItem)
    }
    
    private func deleteItems(offsets: IndexSet) {
        let sortedItems = packingList.items.sorted(by: { $0.title < $1.title })
        for index in offsets {
            modelContext.delete(sortedItems[index])
        }
    }
}

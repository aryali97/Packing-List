import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DetailView: View {
    @Bindable var packingList: PackingList
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            Section("Details") {
                TextField("Trip Name", text: $packingList.name)
                if !packingList.isTemplate {
                    DatePicker("Trip Date", selection: Binding(get: {
                        packingList.tripDate ?? Date()
                    }, set: {
                        packingList.tripDate = $0
                    }), displayedComponents: .date)
                }
            }
            
            Section("Items") {
                ForEach(packingList.items.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                    ChecklistRowView(item: item)
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)
                
                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .navigationTitle(packingList.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }
    
    private func addItem() {
        let maxOrder = packingList.items.map { $0.sortOrder }.max() ?? -1
        let newItem = ChecklistItem(title: "New Item", sortOrder: maxOrder + 1)
        newItem.packingList = packingList
        packingList.items.append(newItem) // Explicitly append to trigger UI update
        // modelContext.insert(newItem) // Not needed if appended to relationship
    }
    
    private func deleteItems(offsets: IndexSet) {
        let sortedItems = packingList.items.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sortedItems[index])
        }
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        print("� moveItems called - from: \(source), to: \(destination)")
        var sortedItems = packingList.items.sorted(by: { $0.sortOrder < $1.sortOrder })
        sortedItems.move(fromOffsets: source, toOffset: destination)
        
        // Update sort orders
        for (index, item) in sortedItems.enumerated() {
            item.sortOrder = index
        }
        print("✅ Move complete")
    }
}

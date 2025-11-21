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
                ForEach(packingList.items.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                    ChecklistRowView(item: item)
                }
                .onDelete(perform: deleteItems)
                
                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .dropDestination(for: Data.self) { items, location in
            guard let draggedData = items.first,
                  let draggedIdString = String(data: draggedData, encoding: .utf8),
                  let draggedId = UUID(uuidString: draggedIdString) else { return false }
            
            moveItemToRoot(draggedId: draggedId)
            return true
        }
        .navigationTitle(packingList.name)
        .navigationBarTitleDisplayMode(.inline)
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
    
    private func moveItemToRoot(draggedId: UUID) {
        // Fetch the dragged item
        let descriptor = FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.id == draggedId })
        guard let draggedItem = try? modelContext.fetch(descriptor).first else { return }
        
        // Check if it's already at root of this list
        if draggedItem.packingList?.id == packingList.id && draggedItem.parent == nil {
            return
        }
        
        // Remove from old parent
        draggedItem.parent = nil
        
        // Remove from old list if different
        if let oldList = draggedItem.packingList, oldList.id != packingList.id {
            oldList.items.removeAll(where: { $0.id == draggedId })
        }
        
        // Add to this list
        draggedItem.packingList = packingList
        if !packingList.items.contains(where: { $0.id == draggedId }) {
            let maxOrder = packingList.items.map { $0.sortOrder }.max() ?? -1
            draggedItem.sortOrder = maxOrder + 1
            packingList.items.append(draggedItem)
        }
    }
}

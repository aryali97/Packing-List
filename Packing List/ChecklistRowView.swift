import SwiftUI
import SwiftData

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded: Bool = true
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let children = item.children, !children.isEmpty {
                ForEach(children.sorted(by: { $0.sortOrder < $1.sortOrder })) { child in
                    ChecklistRowView(item: child)
                }
                .onDelete(perform: deleteChild)
            }
            
        } label: {
            HStack {
                Toggle(isOn: $item.isCompleted) {
                    EmptyView()
                }
                .labelsHidden()
                
                TextField("Item Name", text: $item.title)
                    .strikethrough(item.isSkipped)
                    .opacity(item.isSkipped ? 0.5 : 1.0)
                
                Spacer()
                
                if item.isSkipped {
                    Image(systemName: "nosign")
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    deleteSelf()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                
                Button {
                    item.isSkipped.toggle()
                } label: {
                    Label(item.isSkipped ? "Unskip" : "Skip", systemImage: "nosign")
                }
            }
        }
        .draggable(item.id.uuidString)
        .dropDestination(for: String.self) { items, location in
            guard let draggedIdString = items.first,
                  let draggedId = UUID(uuidString: draggedIdString) else { return false }
            
            moveItem(draggedId: draggedId, to: item)
            return true
        }
    }
    
    private func moveItem(draggedId: UUID, to targetItem: ChecklistItem) {
        // Prevent dropping onto self
        guard draggedId != targetItem.id else { return }
        
        // Fetch the dragged item
        let descriptor = FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.id == draggedId })
        guard let draggedItem = try? modelContext.fetch(descriptor).first else { return }
        
        // Prevent circular references (checking if target is a child of dragged item)
        var current = targetItem.parent
        while let parent = current {
            if parent.id == draggedId { return }
            current = parent.parent
        }
        
        // Update relationships
        // Remove from old parent (handled by setting new parent)
        // Remove from old root list if it was a root item
        if let oldList = draggedItem.packingList {
            oldList.items.removeAll(where: { $0.id == draggedId })
            draggedItem.packingList = nil
        }
        
        // Set new parent
        draggedItem.parent = targetItem
        
        // Set sort order (append to end)
        let maxOrder = targetItem.children?.map { $0.sortOrder }.max() ?? -1
        draggedItem.sortOrder = maxOrder + 1
        
        // targetItem.children?.append(draggedItem) // Auto-handled
        
        // Ensure target is expanded to show the new child
        isExpanded = true
    }
    
    private func deleteChild(offsets: IndexSet) {
        guard let children = item.children else { return }
        let sortedChildren = children.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sortedChildren[index])
        }
    }
    
    private func deleteSelf() {
        modelContext.delete(item)
    }
}

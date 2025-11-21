import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var packingList: PackingList
    @Environment(\.modelContext) private var modelContext
    
    private struct FlatItem: Identifiable {
        let id: UUID
        let item: ChecklistItem
        let depth: Int
    }
    
    private var flatItems: [FlatItem] {
        flatten(parent: packingList.rootItem, depth: 1)
    }
    
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
                ForEach(flatItems) { flat in
                    ChecklistRowView(item: flat.item, depth: flat.depth)
                }
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
        let rootItem = packingList.rootItem
        
        let maxOrder = rootItem.children.map { $0.sortOrder }.max() ?? -1
        let newItem = ChecklistItem(title: "New Item", sortOrder: maxOrder + 1)
        newItem.parent = rootItem
        
        modelContext.insert(newItem)
        
        // Force save to update the relationship and trigger UI refresh
        try? modelContext.save()
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        guard let start = source.first else { return }
        
        var flat = flatItems
        guard start < flat.count else { return }
        
        let moveRange = subtreeRange(in: flat, at: start)
        let block = Array(flat[moveRange])
        flat.removeSubrange(moveRange)
        
        var adjustedDestination = destination
        if destination > moveRange.lowerBound {
            adjustedDestination -= moveRange.count
        }
        adjustedDestination = max(0, min(adjustedDestination, flat.count))
        
        let previousDepth = adjustedDestination > 0 ? flat[adjustedDestination - 1].depth : 0
        let originalBaseDepth = block.first?.depth ?? 1
        let newBaseDepth = max(1, min(originalBaseDepth, previousDepth + 1))
        let depthDelta = newBaseDepth - originalBaseDepth
        
        let adjustedBlock = block.map { flatItem in
            FlatItem(id: flatItem.id, item: flatItem.item, depth: max(1, flatItem.depth + depthDelta))
        }
        
        flat.insert(contentsOf: adjustedBlock, at: adjustedDestination)
        apply(flatOrder: flat)
    }
    
    private func flatten(parent: ChecklistItem, depth: Int) -> [FlatItem] {
        let sortedChildren = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        return sortedChildren.flatMap { child in
            [FlatItem(id: child.id, item: child, depth: depth)] + flatten(parent: child, depth: depth + 1)
        }
    }
    
    private func subtreeRange(in flat: [FlatItem], at index: Int) -> Range<Int> {
        let baseDepth = flat[index].depth
        var end = index + 1
        while end < flat.count && flat[end].depth > baseDepth {
            end += 1
        }
        return index..<end
    }
    
    private func apply(flatOrder: [FlatItem]) {
        var stack: [ChecklistItem] = [packingList.rootItem]
        var nextOrder: [UUID: Int] = [packingList.rootItem.id: 0]
        
        for flat in flatOrder {
            let depth = flat.depth
            while stack.count > depth {
                stack.removeLast()
            }
            
            let parent = stack.last ?? packingList.rootItem
            let currentOrder = nextOrder[parent.id] ?? 0
            
            flat.item.parent = parent
            flat.item.sortOrder = currentOrder
            nextOrder[parent.id] = currentOrder + 1
            
            if stack.count > depth {
                stack[depth] = flat.item
            } else {
                stack.append(flat.item)
            }
            
            nextOrder[flat.item.id] = 0
        }
        
        try? modelContext.save()
    }
}

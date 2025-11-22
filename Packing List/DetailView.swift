import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var packingList: PackingList
    @Environment(\.modelContext) private var modelContext
    @State private var draggingItemID: UUID?
    
    // Query all items to make the view reactive to deletions/changes
    @Query private var allItems: [ChecklistItem]
    
    private struct FlatItem: Identifiable {
        let id: UUID
        let item: ChecklistItem
        let depth: Int
        let parentID: UUID?
    }
    
    private var flatItems: [FlatItem] {
        flatten(parent: packingList.rootItem, depth: 1, parentID: packingList.rootItem.id)
    }
    
    private var visibleItems: [FlatItem] {
        let flat = flatItems
        return visibleList(from: flat, collapsingID: draggingItemID).map { flat[$0] }
    }
    
    var body: some View {
        List {
            Section("Details") {
                TextField("Name", text: $packingList.name)
                if !packingList.isTemplate {
                    DatePicker("Trip Date", selection: Binding(get: {
                        packingList.tripDate ?? Date()
                    }, set: {
                        packingList.tripDate = $0
                    }), displayedComponents: .date)
                }
            }
            
            Section("Items") {
                ForEach(visibleItems) { flat in
                    ChecklistRowView(
                        item: flat.item,
                        depth: flat.depth,
                        onDragStart: { draggingItemID = flat.item.id },
                        onDragEnd: { draggingItemID = nil }
                    )
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
        let newItem = ChecklistItem(title: "", sortOrder: maxOrder + 1)
        newItem.parent = rootItem
        
        modelContext.insert(newItem)
        
        // Force save to update the relationship and trigger UI refresh
        try? modelContext.save()
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        guard let sourceVisibleIndex = source.first else { return }
        
        let flat = flatItems
        let visibleBefore = visibleList(from: flat, collapsingID: draggingItemID)
        guard sourceVisibleIndex < visibleBefore.count else { return }
        
        let sourceFlatIndex = visibleBefore[sourceVisibleIndex]
        let moveRange = subtreeRange(in: flat, at: sourceFlatIndex)
        let block = Array(flat[moveRange])
        
        var flatWithoutBlock = flat
        flatWithoutBlock.removeSubrange(moveRange)
        
        let visibleAfter = visibleList(from: flatWithoutBlock, collapsingID: nil)
        
        // Adjust destination to account for hidden children that were removed but not represented in the visible list move.
        let adjustedDestinationVisible: Int
        if block.count > 1 && destination > sourceVisibleIndex {
            adjustedDestinationVisible = max(sourceVisibleIndex + 1, destination - (block.count - 1))
        } else {
            adjustedDestinationVisible = destination
        }
        
        let clampedDestination = min(adjustedDestinationVisible, visibleAfter.count)
        let destinationFlatIndex = clampedDestination < visibleAfter.count
            ? visibleAfter[clampedDestination]
            : flatWithoutBlock.count
        
        let previousDepth = destinationFlatIndex > 0 ? flatWithoutBlock[destinationFlatIndex - 1].depth : 0
        let originalBaseDepth = block.first?.depth ?? 1
        let newBaseDepth = max(1, min(originalBaseDepth, previousDepth + 1))
        let depthDelta = newBaseDepth - originalBaseDepth
        
        let adjustedBlock = block.map { flatItem in
            FlatItem(
                id: flatItem.id,
                item: flatItem.item,
                depth: max(1, flatItem.depth + depthDelta),
                parentID: flatItem.parentID
            )
        }
        
        flatWithoutBlock.insert(contentsOf: adjustedBlock, at: destinationFlatIndex)
        apply(flatOrder: flatWithoutBlock)
        draggingItemID = nil
    }
    
    private func flatten(parent: ChecklistItem, depth: Int, parentID: UUID?) -> [FlatItem] {
        let sortedChildren = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        return sortedChildren.flatMap { child in
            [FlatItem(id: child.id, item: child, depth: depth, parentID: parentID)] + flatten(parent: child, depth: depth + 1, parentID: child.id)
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
    
    private func visibleList(from flat: [FlatItem], collapsingID: UUID?) -> [Int] {
        guard let collapsingID else {
            return Array(flat.indices)
        }
        var result: [Int] = []
        var skippingDepth: Int?
        
        for (idx, entry) in flat.enumerated() {
            if let skipDepth = skippingDepth {
                if entry.depth > skipDepth { continue }
                skippingDepth = nil
            }
            result.append(idx)
            if entry.id == collapsingID {
                skippingDepth = entry.depth
            }
        }
        return result
    }
}

import Foundation

struct ChecklistReorderer {
    struct FlatItem: Identifiable {
        let id: UUID
        let item: ChecklistItem
        let depth: Int
    }
    
    static func flatten(root: ChecklistItem) -> [FlatItem] {
        flatten(parent: root, depth: 1)
    }
    
    static func visibleIndices(flat: [FlatItem], collapsingID: UUID?) -> [Int] {
        guard let collapsingID else { return Array(flat.indices) }
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
    
    static func move(
        flat: [FlatItem],
        sourceVisible: Int,
        destinationVisible: Int,
        collapsingID: UUID?
    ) -> [FlatItem] {
        let visibleBefore = visibleIndices(flat: flat, collapsingID: collapsingID)
        guard sourceVisible < visibleBefore.count else { return flat }
        
        let sourceFlatIndex = visibleBefore[sourceVisible]
        let moveRange = subtreeRange(in: flat, at: sourceFlatIndex)
        let block = Array(flat[moveRange])
        
        var flatWithoutBlock = flat
        flatWithoutBlock.removeSubrange(moveRange)
        
        let visibleAfter = visibleIndices(flat: flatWithoutBlock, collapsingID: nil)
        
        let adjustedDestinationVisible: Int
        if block.count > 1 && destinationVisible > sourceVisible {
            adjustedDestinationVisible = max(sourceVisible + 1, destinationVisible - (block.count - 1))
        } else {
            adjustedDestinationVisible = destinationVisible
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
                depth: max(1, flatItem.depth + depthDelta)
            )
        }
        
        flatWithoutBlock.insert(contentsOf: adjustedBlock, at: destinationFlatIndex)
        return flatWithoutBlock
    }
    
    static func apply(flatOrder: [FlatItem], to root: ChecklistItem) {
        var stack: [ChecklistItem] = [root]
        var nextOrder: [UUID: Int] = [root.id: 0]
        
        for flat in flatOrder {
            let depth = flat.depth
            while stack.count > depth {
                stack.removeLast()
            }
            
            let parent = stack.last ?? root
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
    }
    
    // MARK: - Helpers
    
    private static func flatten(parent: ChecklistItem, depth: Int) -> [FlatItem] {
        let sortedChildren = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        return sortedChildren.flatMap { child in
            [FlatItem(id: child.id, item: child, depth: depth)] + flatten(parent: child, depth: depth + 1)
        }
    }
    
    private static func subtreeRange(in flat: [FlatItem], at index: Int) -> Range<Int> {
        let baseDepth = flat[index].depth
        var end = index + 1
        while end < flat.count && flat[end].depth > baseDepth {
            end += 1
        }
        return index..<end
    }
}

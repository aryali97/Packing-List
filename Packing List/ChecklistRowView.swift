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
                .onMove(perform: moveChild)
            }
        } label: {
            HStack(spacing: 12) {
                // Drag handle icon - only this should trigger reordering
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                    .frame(width: 20)
                
                // Main content area - swipe gestures for indent/outdent
                HStack(spacing: 8) {
                    TextField("Item Name", text: $item.title)
                        .strikethrough(item.isSkipped)
                        .opacity(item.isSkipped ? 0.5 : 1.0)
                    
                    Spacer()
                    
                    if item.isSkipped {
                        Image(systemName: "nosign")
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            handleDragGesture(translation: value.translation)
                        }
                )
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
                
                Divider()
                
                Button {
                    indentItem()
                } label: {
                    Label("Indent", systemImage: "increase.indent")
                }
                .disabled(!canIndent())
                
                Button {
                    outdentItem()
                } label: {
                    Label("Outdent", systemImage: "decrease.indent")
                }
                .disabled(item.parent == nil)
            }
        }
        .draggable(item)
        .dropDestination(for: ChecklistItem.self) { droppedItems, location in
            guard let draggedItem = droppedItems.first else { return false }
            print("🔵 Attempting to nest item \(draggedItem.id) under \(item.title)")
            nestItem(draggedItem: draggedItem)
            return true
        }
    }
    
    private func nestItem(draggedItem: ChecklistItem) {
        // Fetch the real items from context
        let draggedDescriptor = FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.id == draggedItem.id })
        guard let realDraggedItem = try? modelContext.fetch(draggedDescriptor).first else {
            print("🔴 Failed to fetch dragged item")
            return
        }
        
        // Prevent nesting an item under itself
        guard realDraggedItem.id != item.id else {
            print("🔴 Cannot nest item under itself")
            return
        }
        
        // Prevent circular nesting (e.g., nesting a parent under its own child)
        var current = item.parent
        while let parent = current {
            if parent.id == realDraggedItem.id {
                print("🔴 Circular nesting prevented")
                return
            }
            current = parent.parent
        }
        
        print("🟢 Nesting \(realDraggedItem.title) under \(item.title)")
        
        // Remove from old parent or root list
        if let oldList = realDraggedItem.packingList {
            oldList.items.removeAll(where: { $0.id == realDraggedItem.id })
            realDraggedItem.packingList = nil
        }
        
        // Set new parent
        realDraggedItem.parent = item
        
        // Calculate sort order for the new child
        let maxOrder = item.children?.map { $0.sortOrder }.max() ?? -1
        realDraggedItem.sortOrder = maxOrder + 1
        
        // Expand to show the new child
        isExpanded = true
        
        print("✅ Nesting complete")
    }
    
    private func addChild() {
        let newChild = ChecklistItem(title: "New Item")
        newChild.parent = item
        // item.children?.append(newChild) // Relationship managed by SwiftData, but setting parent is usually enough.
        // However, to update UI immediately, we might need to append if the relationship is not auto-updating the array in memory immediately.
        // Safest is to insert into context.
        modelContext.insert(newChild)
        // Ensure expansion
        isExpanded = true
    }
    
    private func deleteChild(offsets: IndexSet) {
        guard let children = item.children else { return }
        let sortedChildren = children.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sortedChildren[index])
        }
    }
    
    private func moveChild(from source: IndexSet, to destination: Int) {
        guard let children = item.children else { return }
        print("🔵 moveChild called - from: \(source), to: \(destination)")
        
        var sortedChildren = children.sorted(by: { $0.sortOrder < $1.sortOrder })
        sortedChildren.move(fromOffsets: source, toOffset: destination)
        
        // Update sort orders
        for (index, child) in sortedChildren.enumerated() {
            child.sortOrder = index
        }
        
        print("✅ Child move complete")
    }
    
    private func deleteSelf() {
        modelContext.delete(item)
    }
    
    // MARK: - Indent/Outdent Logic
    
    private func handleDragGesture(translation: CGSize) {
        let horizontalDrag = translation.width
        let verticalDrag = abs(translation.height)
        
        // Only process if drag is mostly horizontal
        guard abs(horizontalDrag) > verticalDrag else { return }
        
        if horizontalDrag > 50 {
            // Dragged right - indent
            print("🔵 Swipe right detected - attempting to indent")
            indentItem()
        } else if horizontalDrag < -50 {
            // Dragged left - outdent
            print("🔵 Swipe left detected - attempting to outdent")
            outdentItem()
        }
    }
    
    private func canIndent() -> Bool {
        // Can indent if there's a previous sibling at the same level
        guard let packingList = item.packingList else {
            // If item has a parent, check siblings
            guard let parent = item.parent,
                  let siblings = parent.children else { return false }
            
            let sortedSiblings = siblings.sorted(by: { $0.sortOrder < $1.sortOrder })
            guard let currentIndex = sortedSiblings.firstIndex(where: { $0.id == item.id }),
                  currentIndex > 0 else { return false }
            
            return true
        }
        
        // Root level item - check if there's a previous item
        let sortedItems = packingList.items.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let currentIndex = sortedItems.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return false }
        
        return true
    }
    
    private func indentItem() {
        guard canIndent() else {
            print("🔴 Cannot indent - no previous sibling")
            return
        }
        
        withAnimation {
            if let packingList = item.packingList {
                // Root level item
                let sortedItems = packingList.items.sorted(by: { $0.sortOrder < $1.sortOrder })
                guard let currentIndex = sortedItems.firstIndex(where: { $0.id == item.id }),
                      currentIndex > 0 else { return }
                
                let previousItem = sortedItems[currentIndex - 1]
                
                print("🟢 Indenting \(item.title) under \(previousItem.title)")
                
                // Remove from root list
                packingList.items.removeAll(where: { $0.id == item.id })
                item.packingList = nil
                
                // Add as child of previous item
                item.parent = previousItem
                let maxOrder = previousItem.children?.map { $0.sortOrder }.max() ?? -1
                item.sortOrder = maxOrder + 1
                
                print("✅ Indent complete")
            } else if let parent = item.parent,
                      let siblings = parent.children {
                // Child item - indent under previous sibling
                let sortedSiblings = siblings.sorted(by: { $0.sortOrder < $1.sortOrder })
                guard let currentIndex = sortedSiblings.firstIndex(where: { $0.id == item.id }),
                      currentIndex > 0 else { return }
                
                let previousSibling = sortedSiblings[currentIndex - 1]
                
                print("🟢 Indenting \(item.title) under \(previousSibling.title)")
                
                // Change parent
                item.parent = previousSibling
                let maxOrder = previousSibling.children?.map { $0.sortOrder }.max() ?? -1
                item.sortOrder = maxOrder + 1
                
                print("✅ Indent complete")
            }
            
            // Force a save to trigger SwiftData updates
            try? modelContext.save()
        }
    }
    
    private func outdentItem() {
        guard let currentParent = item.parent else {
            print("🔴 Cannot outdent - already at root level")
            return
        }
        
        print("🟢 Outdenting \(item.title)")
        
        withAnimation {
            if let grandparent = currentParent.parent {
                // Move to grandparent's children
                item.parent = grandparent
                let maxOrder = grandparent.children?.map { $0.sortOrder }.max() ?? -1
                item.sortOrder = maxOrder + 1
            } else if let packingList = currentParent.packingList {
                // Move to root level
                item.parent = nil
                item.packingList = packingList
                let maxOrder = packingList.items.map { $0.sortOrder }.max() ?? -1
                item.sortOrder = maxOrder + 1
                
                if !packingList.items.contains(where: { $0.id == item.id }) {
                    packingList.items.append(item)
                }
            }
            
            // Force a save to trigger SwiftData updates
            try? modelContext.save()
        }
        
        print("✅ Outdent complete")
    }
}

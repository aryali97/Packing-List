import SwiftUI
import SwiftData

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded: Bool = true
    
    // Query children dynamically to ensure UI updates when parent changes
    @Query private var allItems: [ChecklistItem]
    
    private var children: [ChecklistItem] {
        allItems.filter { $0.parent?.id == item.id }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
    }
    
    var body: some View {
        let labelContent = {
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
        
        Group {
            if children.isEmpty {
                labelContent()
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(children) { child in
                        ChecklistRowView(item: child)
                    }
                    .onDelete(perform: deleteChild)
                    .onMove(perform: moveChild)
                } label: {
                    labelContent()
                }
            }
        }
        .draggable(item)
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
        let children = item.children
        let sortedChildren = children.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sortedChildren[index])
        }
    }
    
    private func moveChild(from source: IndexSet, to destination: Int) {
        let children = item.children
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
        guard let parent = item.parent else { return false }
        let siblings = parent.children
        
        let sortedSiblings = siblings.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let currentIndex = sortedSiblings.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return false }
        
        return true
    }
    
    private func indentItem() {
        guard canIndent() else {
            print("🔴 Cannot indent - no previous sibling")
            return
        }
        
        guard let parent = item.parent else { return }
        let siblings = parent.children
        
        let sortedSiblings = siblings.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let currentIndex = sortedSiblings.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return }
        
        let previousSibling = sortedSiblings[currentIndex - 1]
        
        print("🟢 Indenting \(item.title) under \(previousSibling.title)")
        
        // Change parent to previous sibling
        item.parent = previousSibling
        let maxOrder = previousSibling.children.map { $0.sortOrder }.max() ?? -1
        item.sortOrder = maxOrder + 1
        
        // Force a save to trigger SwiftData updates BEFORE animation
        try? modelContext.save()
        
        print("✅ Indent complete")
    }
    
    private func outdentItem() {
        guard let currentParent = item.parent else {
            print("🔴 Cannot outdent - already at root level")
            return
        }
        
        print("🟢 Outdenting \(item.title) from \(currentParent.title)")
        
        // Move to grandparent's children (or root if grandparent is the invisible root)
        let newParent = currentParent.parent
        item.parent = newParent
        
        if let grandparent = newParent {
            let maxOrder = grandparent.children.map { $0.sortOrder }.max() ?? -1
            item.sortOrder = maxOrder + 1
        } else {
            // Moving to root level (parent is the invisible root)
            let maxOrder = newParent?.children.map { $0.sortOrder }.max() ?? -1
            item.sortOrder = maxOrder + 1
        }
        
        // Force save immediately
        try? modelContext.save()
        
        print("✅ Outdent complete")
    }
}

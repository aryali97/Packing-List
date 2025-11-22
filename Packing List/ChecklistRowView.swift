import SwiftUI
import SwiftData

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    let depth: Int
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @State private var dragOffset: CGFloat = 0
    @State private var hasNotifiedDragStart = false
    @FocusState private var isEditing: Bool
    
    private enum Constants {
        static let dragThreshold: CGFloat = 25
    }
    
    private var baseIndent: CGFloat {
        CGFloat(max(depth - 1, 0)) * 20
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle icon - only this should trigger reordering
            Image("DragHandle")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)
                .frame(width: 20)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            handleHorizontalDragChanged(translation: value.translation)
                        }
                        .onEnded { value in
                            handleHorizontalDrag(translation: value.translation)
                            dragOffset = 0
                        }
                )
            
            // Main content area
            HStack(spacing: 8) {
                TextField("Item", text: $item.title)
                    .strikethrough(item.isSkipped)
                    .opacity(item.isSkipped ? 0.5 : 1.0)
                    .focused($isEditing)
                
                Spacer()
                
                if isEditing {
                    Button(action: deleteSelf) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                } else if item.isSkipped {
                    Image(systemName: "nosign")
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isEditing = true
            }
        }
        .padding(.leading, baseIndent)
        .offset(x: dragOffset)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: dragOffset)
        .contentShape(Rectangle())
        .onDrag {
            onDragStart()
            return NSItemProvider(object: NSString(string: item.id.uuidString))
        }
        .onDrop(of: [.text], isTargeted: nil) { _, _ in
            onDragEnd()
            return false
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
    
    private func deleteSelf() {
        modelContext.delete(item)
        try? modelContext.save()
    }
    
    // MARK: - Indent/Outdent Logic
    
    private func canIndent() -> Bool {
        guard let parent = item.parent else { return false }
        let siblings = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let currentIndex = siblings.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return false }
        return true
    }
    
    private func indentItem() {
        guard canIndent(),
              let parent = item.parent else { return }
        
        let siblings = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let currentIndex = siblings.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return }
        
        let previousSibling = siblings[currentIndex - 1]
        let oldParent = item.parent
        
        item.parent = previousSibling
        let nextOrder = (previousSibling.children.map { $0.sortOrder }.max() ?? -1) + 1
        item.sortOrder = nextOrder
        
        rebalanceSortOrders(for: oldParent)
        rebalanceSortOrders(for: previousSibling)
        try? modelContext.save()
    }
    
    private func outdentItem() {
        guard let currentParent = item.parent else { return }
        
        let newParent = currentParent.parent
        item.parent = newParent
        
        rebalanceAfterOutdent(newParent: newParent, after: currentParent)
        rebalanceSortOrders(for: currentParent)
        rebalanceSortOrders(for: newParent)
        try? modelContext.save()
    }
    
    private func handleHorizontalDragChanged(translation: CGSize) {
        let horizontal = translation.width
        let vertical = abs(translation.height)
        guard abs(horizontal) > vertical + 4 else { dragOffset = 0; return }
        
        let limited = max(min(horizontal, 24), -24)
        if limited > 0, canIndent() {
            dragOffset = limited
        } else if limited < 0, canOutdent() {
            dragOffset = limited
        } else {
            dragOffset = 0
        }
    }
    
    private func handleHorizontalDrag(translation: CGSize) {
        let horizontal = translation.width
        let vertical = abs(translation.height)
        guard abs(horizontal) > vertical else { return }
        
        if horizontal > Constants.dragThreshold {
            indentItem()
        } else if horizontal < -Constants.dragThreshold, canOutdent() {
            outdentItem()
        }
        dragOffset = 0
    }
    
    private func canOutdent() -> Bool {
        return item.parent != nil
    }
    
    private func rebalanceSortOrders(for parent: ChecklistItem?) {
        guard let parent = parent else { return }
        let sortedChildren = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        for (index, child) in sortedChildren.enumerated() {
            child.sortOrder = index
        }
    }
    
    private func rebalanceAfterOutdent(newParent: ChecklistItem?, after parent: ChecklistItem) {
        guard let newParent = newParent else { return }
        
        var reordered = newParent.children
            .filter { $0.id != item.id }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
        
        if let parentIndex = reordered.firstIndex(where: { $0.id == parent.id }) {
            reordered.insert(item, at: parentIndex + 1)
        } else {
            reordered.append(item)
        }
        
        for (idx, child) in reordered.enumerated() {
            child.sortOrder = idx
        }
    }
}

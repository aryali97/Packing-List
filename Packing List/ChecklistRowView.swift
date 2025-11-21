import SwiftUI
import SwiftData

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    let depth: Int
    @Environment(\.modelContext) private var modelContext
    @State private var dragOffset: CGFloat = 0
    
    private var baseIndent: CGFloat {
        CGFloat(max(depth - 1, 0)) * 20
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle icon - only this should trigger reordering
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
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
                TextField("Item Name", text: $item.title)
                    .strikethrough(item.isSkipped)
                    .opacity(item.isSkipped ? 0.5 : 1.0)
                
                Spacer()
                
                if item.isSkipped {
                    Image(systemName: "nosign")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.leading, baseIndent)
        .offset(x: dragOffset)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: dragOffset)
        .contentShape(Rectangle())
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
        .draggable(item)
    }
    
    private func deleteSelf() {
        modelContext.delete(item)
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
        let oldParent = item.parent
        item.parent = newParent
        
        let nextOrder = (newParent?.children.map { $0.sortOrder }.max() ?? -1) + 1
        item.sortOrder = nextOrder
        
        rebalanceSortOrders(for: oldParent)
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
        
        if horizontal > 40 {
            indentItem()
        } else if horizontal < -40, canOutdent() {
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
}

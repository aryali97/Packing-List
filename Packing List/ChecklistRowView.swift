import SwiftUI
import SwiftData

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    let depth: Int
    var showCheckbox: Bool = false
    var isInCompletedSection: Bool = false
    var isImmutable: Bool = false
    var focusBinding: FocusState<UUID?>.Binding?
    var pendingFocusID: UUID?
    var consumePendingFocus: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onCheckToggle: () -> Void = {}
    var onSubmit: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @State private var dragOffset: CGFloat = 0
    @State private var hasNotifiedDragStart = false
    
    private enum Constants {
        static let dragThreshold: CGFloat = 25
    }
    
    private var baseIndent: CGFloat {
        CGFloat(max(depth - 1, 0)) * 20
    }
    
    private var isFocused: Bool {
        focusBinding?.wrappedValue == item.id
    }
    
    private var shouldShowDeleteButton: Bool {
        let listIsInEditMode = editMode?.wrappedValue.isEditing ?? false
        let canShow = !isImmutable && !isInCompletedSection
        return (isFocused || listIsInEditMode) && canShow
    }
    
    @ViewBuilder
    private var titleField: some View {
        let base = TextField("Item", text: $item.title, axis: .vertical)
            .disabled(isImmutable || isInCompletedSection)
            .strikethrough(item.isCompleted && isInCompletedSection)
            .opacity(isInCompletedSection ? 0.6 : 1.0)
            .submitLabel(.return)
            .onChange(of: item.title) { newValue in
                guard isFocused else { return }
                guard newValue.contains("\n") else { return }
                item.title = newValue.replacingOccurrences(of: "\n", with: "")
                onSubmit()
            }
        
        if let focusBinding {
            base.focused(focusBinding, equals: item.id)
        } else {
            base
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle icon - only show if not in completed section
            if isInCompletedSection {
                // Preserve spacing where drag handle would be
                Color.clear
                    .frame(width: 20, height: 16)
            } else {
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
            }
            
            // Checkbox (only for non-template trips)
            if showCheckbox {
                Button(action: {
                    if !isImmutable {
                        onCheckToggle()
                    }
                }) {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundColor(isImmutable ? .secondary.opacity(0.5) : .primary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(isImmutable)
            }
            
            // Main content area
            HStack(spacing: 8) {
                titleField
                
                Spacer()
                
                if shouldShowDeleteButton {
                    Button(action: deleteSelf) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !isImmutable && !isInCompletedSection {
                    focusBinding?.wrappedValue = item.id
                }
            }
        }
        .padding(.leading, baseIndent)
        .offset(x: dragOffset)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: dragOffset)
        .contentShape(Rectangle())
        .onDrag {
            focusBinding?.wrappedValue = nil
            if !isInCompletedSection {
                onDragStart()
                return NSItemProvider(object: NSString(string: item.id.uuidString))
            }
            return NSItemProvider()
        }
        .onDrop(of: [.text], isTargeted: nil) { _, _ in
            if !isInCompletedSection {
                onDragEnd()
            }
            return false
        }
        .onAppear {
            if pendingFocusID == item.id {
                focusBinding?.wrappedValue = item.id
                consumePendingFocus()
            }
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

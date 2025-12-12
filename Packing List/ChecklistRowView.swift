import ObjectiveC.runtime
import SwiftData
import SwiftUI
import UIKit

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    let depth: Int
    var showCheckbox: Bool = false
    var isInCompletedSection: Bool = false
    var isImmutable: Bool = false
    var focusBinding: FocusState<UUID?>.Binding?
    var onDragStart: () -> Void = {}
    var onCheckToggle: () -> Void = {}
    var onSubmit: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @State private var dragOffset: CGFloat = 0

    private enum Constants {
        static let dragThreshold: CGFloat = 25
    }

    private var baseIndent: CGFloat {
        CGFloat(max(self.depth - 1, 0)) * 20
    }

    private var isFocused: Bool {
        self.focusBinding?.wrappedValue == self.item.id
    }

    private var shouldShowDeleteButton: Bool {
        let listIsInEditMode = self.editMode?.wrappedValue.isEditing ?? false
        let canShow = !self.isImmutable && !self.isInCompletedSection
        return (self.isFocused || listIsInEditMode) && canShow
    }

    @ViewBuilder
    private var titleField: some View {
        let base = BackspaceAwareTextField(
            text: $item.title,
            isFirstResponder: Binding(
                get: { focusBinding?.wrappedValue == self.item.id },
                set: { newValue in
                    if newValue && focusBinding?.wrappedValue != self.item.id {
                        focusBinding?.wrappedValue = self.item.id
                    }
                }
            ),
            isEditable: !(self.isImmutable || self.isInCompletedSection),
            isStrikethrough: self.item.isCompleted && self.isInCompletedSection,
            opacity: self.isInCompletedSection ? 0.6 : 1.0,
            onSubmitNewline: {
                self.item.title = self.item.title.replacingOccurrences(of: "\n", with: "")
                self.onSubmit()
            },
            onDeleteWhenEmpty: {
                guard self.item.title.isEmpty else { return }
                self.deleteSelf()
            }
        )
        if let focusBinding {
            base.focused(focusBinding, equals: self.item.id)
        } else {
            base
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle icon - only show if not in completed section
            if self.isInCompletedSection {
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
                                self.handleHorizontalDragChanged(translation: value.translation)
                            }
                            .onEnded { value in
                                self.handleHorizontalDrag(translation: value.translation)
                                self.dragOffset = 0
                            }
                    )
            }

            // Checkbox (only for non-template trips)
            if self.showCheckbox {
                Button(action: {
                    if !self.isImmutable {
                        self.onCheckToggle()
                    }
                }) {
                    Image(systemName: self.item.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundColor(self.isImmutable ? .secondary.opacity(0.5) : .primary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(self.isImmutable)
            }

            // Main content area
            HStack(spacing: 8) {
                self.titleField

                Spacer()

                if self.shouldShowDeleteButton {
                    Button(action: self.deleteSelf) {
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
                if !self.isImmutable, !self.isInCompletedSection {
                    self.focusBinding?.wrappedValue = self.item.id
                }
            }
        }
        .padding(.leading, self.baseIndent)
        .offset(x: self.dragOffset)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: self.dragOffset)
        .contentShape(Rectangle())
        .onDrag {
            print("🟡 onDrag triggered for item: \(self.item.title)")
            self.focusBinding?.wrappedValue = nil
            if !self.isInCompletedSection {
                self.onDragStart()
            }
            return NSItemProvider(object: NSString(string: self.item.id.uuidString))
        }
    }

    private func deleteSelf() {
        // Move focus to the previous visible row (preorder) before deleting this row.
        if let focusBinding, let previousID = previousVisibleRowID() {
            focusBinding.wrappedValue = previousID
        }

        self.modelContext.delete(self.item)
        try? self.modelContext.save()
    }

    /// Finds the previous visible row in preorder traversal, matching the list display order.
    private func previousVisibleRowID() -> UUID? {
        guard let parent = item.parent else { return nil }

        let siblings = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        if let index = siblings.firstIndex(where: { $0.id == item.id }), index > 0 {
            let previousSibling = siblings[index - 1]
            return self.deepestDescendantID(of: previousSibling)
        }

        // No previous sibling: fall back to parent, unless the parent is the hidden root.
        if parent.parent != nil {
            return parent.id
        }

        return nil
    }

    /// Returns the deepest descendant (last in preorder) for a given item, or the item itself if it has no children.
    private func deepestDescendantID(of node: ChecklistItem) -> UUID {
        var current = node
        while let lastChild = current.children.sorted(by: { $0.sortOrder < $1.sortOrder }).last {
            current = lastChild
        }
        return current.id
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
        guard self.canIndent(),
              let parent = item.parent else { return }

        let siblings = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let currentIndex = siblings.firstIndex(where: { $0.id == item.id }),
              currentIndex > 0 else { return }

        let previousSibling = siblings[currentIndex - 1]
        let oldParent = self.item.parent

        self.item.parent = previousSibling
        let nextOrder = (previousSibling.children.map(\.sortOrder).max() ?? -1) + 1
        self.item.sortOrder = nextOrder

        self.rebalanceSortOrders(for: oldParent)
        self.rebalanceSortOrders(for: previousSibling)
        try? self.modelContext.save()
    }

    private func outdentItem() {
        guard let currentParent = item.parent else { return }

        let newParent = currentParent.parent
        self.item.parent = newParent

        self.rebalanceAfterOutdent(newParent: newParent, after: currentParent)
        self.rebalanceSortOrders(for: currentParent)
        self.rebalanceSortOrders(for: newParent)
        try? self.modelContext.save()
    }

    private func handleHorizontalDragChanged(translation: CGSize) {
        let horizontal = translation.width
        let vertical = abs(translation.height)
        guard abs(horizontal) > vertical + 4 else { self.dragOffset = 0; return }

        let limited = max(min(horizontal, 24), -24)
        if limited > 0, self.canIndent() {
            self.dragOffset = limited
        } else if limited < 0, self.canOutdent() {
            self.dragOffset = limited
        } else {
            self.dragOffset = 0
        }
    }

    private func handleHorizontalDrag(translation: CGSize) {
        let horizontal = translation.width
        let vertical = abs(translation.height)
        guard abs(horizontal) > vertical else { return }

        if horizontal > Constants.dragThreshold {
            self.indentItem()
        } else if horizontal < -Constants.dragThreshold, self.canOutdent() {
            self.outdentItem()
        }
        self.dragOffset = 0
    }

    private func canOutdent() -> Bool {
        self.item.parent != nil
    }

    private func rebalanceSortOrders(for parent: ChecklistItem?) {
        guard let parent else { return }
        let sortedChildren = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        for (index, child) in sortedChildren.enumerated() {
            child.sortOrder = index
        }
    }

    private func rebalanceAfterOutdent(newParent: ChecklistItem?, after parent: ChecklistItem) {
        guard let newParent else { return }

        var reordered = newParent.children
            .filter { $0.id != self.item.id }
            .sorted(by: { $0.sortOrder < $1.sortOrder })

        if let parentIndex = reordered.firstIndex(where: { $0.id == parent.id }) {
            reordered.insert(self.item, at: parentIndex + 1)
        } else {
            reordered.append(self.item)
        }

        for (idx, child) in reordered.enumerated() {
            child.sortOrder = idx
        }
    }
}

// MARK: - Drag Preview View

/// A simple preview view for drag operations that tracks when the drag ends via onDisappear.
private struct DragPreviewView: View {
    let title: String
    let onDisappear: () -> Void

    var body: some View {
        Text(title.isEmpty ? "Item" : title)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            .onDisappear {
                onDisappear()
            }
    }
}

// MARK: - Backspace-aware TextField

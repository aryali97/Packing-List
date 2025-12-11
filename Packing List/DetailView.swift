import SwiftData
import SwiftUI
import UIKit

// MARK: - Drag Session Observer

/// Observes drag sessions at the window level to detect when any drag ends.
/// This is needed because SwiftUI's List handles drag/drop internally for onMove,
/// bypassing standard onDrop handlers.
struct DragSessionObserver: UIViewRepresentable {
    let onDragEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = SessionObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDragEnd = onDragEnd
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDragEnd: onDragEnd)
    }

    class SessionObserverView: UIView {
        weak var coordinator: Coordinator?
        private var dropInteraction: UIDropInteraction?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setupInteraction()
        }

        private func setupInteraction() {
            // Remove existing interaction if any
            if let existing = dropInteraction {
                window?.removeInteraction(existing)
                dropInteraction = nil
            }

            // Add interaction to window to monitor all drag sessions
            guard let window, let coordinator else { return }
            let interaction = UIDropInteraction(delegate: coordinator)
            window.addInteraction(interaction)
            dropInteraction = interaction
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            // Clean up when leaving window
            if let existing = dropInteraction, let oldWindow = window {
                oldWindow.removeInteraction(existing)
                dropInteraction = nil
            }
            super.willMove(toWindow: newWindow)
        }
    }

    class Coordinator: NSObject, UIDropInteractionDelegate {
        var onDragEnd: () -> Void

        init(onDragEnd: @escaping () -> Void) {
            self.onDragEnd = onDragEnd
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            // Accept all sessions so we can observe them
            true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            // Cancel from our perspective - let the List handle actual drops
            UIDropProposal(operation: .cancel)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            // Called when any drag session ends, regardless of outcome
            onDragEnd()
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @Bindable var packingList: PackingList
    var startEditingName: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var draggingItemID: UUID?
    @FocusState private var isNameFocused: Bool
    @FocusState private var focusedItemID: UUID?

    // Query all items to make the view reactive to deletions/changes
    @Query private var allItems: [ChecklistItem]

    private struct FlatItem: Identifiable {
        let id: UUID
        let item: ChecklistItem
        let depth: Int
        let parentID: UUID?
    }

    private var flatItems: [FlatItem] {
        ChecklistReorderer.flatten(root: self.packingList.rootItem).map {
            FlatItem(id: $0.id, item: $0.item, depth: $0.depth, parentID: nil)
        }
    }

    private var visibleItems: [FlatItem] {
        let flat = self.flatItems
        let indices = ChecklistReorderer.visibleIndices(
            flat: flat.map { ChecklistReorderer.FlatItem(id: $0.id, item: $0.item, depth: $0.depth) },
            collapsingID: self.draggingItemID
        )
        return indices.map { flat[$0] }
    }

    private var visibleUncompletedItems: [FlatItem] {
        let flat = self.flatItems
        let conv = flat.map { ChecklistReorderer.FlatItem(id: $0.id, item: $0.item, depth: $0.depth) }
        let indices = ChecklistReorderer.visibleIndices(flat: conv, collapsingID: self.draggingItemID)
        return indices.map { flat[$0] }.filter { !self.isFullyCompleted($0.item) }
    }

    private var editableItems: [FlatItem] {
        self.packingList.isTemplate ? self.visibleItems : self.visibleUncompletedItems
    }

    // Check if item and all its descendants are completed
    private func isFullyCompleted(_ item: ChecklistItem) -> Bool {
        // Item itself must be completed
        guard item.isCompleted else { return false }

        // All children must be fully completed
        for child in item.children {
            if !self.isFullyCompleted(child) {
                return false
            }
        }

        return true
    }

    // Items that are not fully completed (item or any descendant unchecked)
    private var uncompletedItems: [FlatItem] {
        self.flatItems.filter { !self.isFullyCompleted($0.item) }
    }

    // Completed items with their parent chain preserved
    private var completedItemsWithParents: [FlatItem] {
        var result: [FlatItem] = []
        var includedIDs = Set<UUID>()

        // First pass: collect all fully completed items
        let fullyCompletedItems = self.flatItems.filter { self.isFullyCompleted($0.item) }

        for completedItem in fullyCompletedItems {
            // Add ancestor chain
            var current: ChecklistItem? = completedItem.item
            var ancestorChain: [ChecklistItem] = []

            while let item = current, item.parent != nil {
                ancestorChain.append(item)
                current = item.parent
            }

            // Add ancestors to result (in reverse order, from root to leaf)
            for ancestor in ancestorChain.reversed() {
                if !includedIDs.contains(ancestor.id) {
                    includedIDs.insert(ancestor.id)
                    // Find the FlatItem for this ancestor
                    if let flatItem = flatItems.first(where: { $0.id == ancestor.id }) {
                        result.append(flatItem)
                    }
                }
            }
        }

        return result
    }

    var body: some View {
        ZStack {
            // Invisible observer to detect when any drag session ends
            DragSessionObserver {
                if self.draggingItemID != nil {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.draggingItemID = nil
                    }
                }
            }
            .frame(width: 0, height: 0)

            List {
            Section("Details") {
                TextField("Name", text: self.$packingList.name)
                    .focused(self.$isNameFocused)
                if !self.packingList.isTemplate {
                    DatePicker("Trip Date", selection: Binding(get: {
                        self.packingList.tripDate ?? Date()
                    }, set: {
                        self.packingList.tripDate = $0
                    }), displayedComponents: .date)
                }
            }

            // Main items section
            Section("Items") {
                if self.packingList.isTemplate {
                    // Template view - no checkboxes
                    ForEach(self.visibleItems) { flat in
                        ChecklistRowView(
                            item: flat.item,
                            depth: flat.depth,
                            showCheckbox: false,
                            focusBinding: self.$focusedItemID,
                            onDragStart: {
                                withAnimation(.easeInOut(duration: 0.2)) { self.draggingItemID = flat.item.id }
                            },
                            onSubmit: { self.handleSubmit(for: flat.item) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .onMove(perform: self.moveItems)
                    .animation(.easeInOut(duration: 0.25), value: self.visibleItems.map(\.id))
                    .animation(.easeInOut(duration: 0.25), value: self.draggingItemID)
                } else {
                    // Trip view - show checkboxes and uncompleted items only
                    ForEach(self.visibleUncompletedItems) { flat in
                        ChecklistRowView(
                            item: flat.item,
                            depth: flat.depth,
                            showCheckbox: true,
                            isInCompletedSection: false,
                            isImmutable: false,
                            focusBinding: self.$focusedItemID,
                            onDragStart: {
                                withAnimation(.easeInOut(duration: 0.2)) { self.draggingItemID = flat.item.id }
                            },
                            onCheckToggle: { self.toggleItemCompletion(item: flat.item) },
                            onSubmit: { self.handleSubmit(for: flat.item) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .onMove(perform: self.moveItems)
                    .animation(.easeInOut(duration: 0.25), value: self.visibleUncompletedItems.map(\.id))
                    .animation(.easeInOut(duration: 0.25), value: self.draggingItemID)
                }

                Button(action: self.addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }

            // Completed section (only for trips, not templates)
            if !self.packingList.isTemplate, !self.completedItemsWithParents.isEmpty {
                Section("Completed") {
                    ForEach(self.completedItemsWithParents) { flat in
                        ChecklistRowView(
                            item: flat.item,
                            depth: flat.depth,
                            showCheckbox: true,
                            isInCompletedSection: true,
                            isImmutable: !self.isFullyCompleted(flat.item),
                            focusBinding: self.$focusedItemID,
                            onCheckToggle: { self.toggleItemCompletion(item: flat.item) }
                        )
                    }
                }
            }
        }
            .navigationTitle(self.packingList.name)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .animation(.easeInOut(duration: 0.25), value: self.draggingItemID)
        }
        .onAppear {
            if self.startEditingName {
                // Delay to allow view to appear before focusing
                DispatchQueue.main.async { self.isNameFocused = true }
            }
        }
    }

    private func handleSubmit(for item: ChecklistItem) {
        let newItem = self.insertItem(after: item)
        self.focusedItemID = newItem.id
    }

    private func insertItem(after item: ChecklistItem) -> ChecklistItem {
        let parent = item.parent ?? self.packingList.rootItem
        let siblings = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        let newItem = ChecklistItem(title: "", sortOrder: 0)
        newItem.parent = parent

        if let index = siblings.firstIndex(where: { $0.id == item.id }) {
            let insertionOrder = siblings[index].sortOrder + 1
            for sibling in siblings where sibling.sortOrder >= insertionOrder {
                sibling.sortOrder += 1
            }
            newItem.sortOrder = insertionOrder
        } else {
            newItem.sortOrder = (siblings.last?.sortOrder ?? -1) + 1
        }

        self.modelContext.insert(newItem)
        self.rebalanceSortOrders(for: parent)
        try? self.modelContext.save()
        return newItem
    }

    private func addItem() {
        let rootItem = self.packingList.rootItem

        let maxOrder = rootItem.children.map(\.sortOrder).max() ?? -1
        let newItem = ChecklistItem(title: "", sortOrder: maxOrder + 1)
        newItem.parent = rootItem

        self.modelContext.insert(newItem)

        // Force save to update the relationship and trigger UI refresh
        try? self.modelContext.save()
        self.focusedItemID = newItem.id
    }

    // Toggle completion and handle children recursively
    private func toggleItemCompletion(item: ChecklistItem) {
        let newCompletionState = !item.isCompleted

        if newCompletionState {
            // Checking: set this item and all children to completed
            self.setCompletionRecursively(item: item, isCompleted: true)
        } else {
            // Unchecking: set this item and all children to uncompleted
            self.setCompletionRecursively(item: item, isCompleted: false)
            // Also uncheck all ancestors
            self.uncheckAncestors(item: item)
        }

        try? self.modelContext.save()
    }

    // Recursively set completion state for item and all children
    private func setCompletionRecursively(item: ChecklistItem, isCompleted: Bool) {
        item.isCompleted = isCompleted
        for child in item.children {
            self.setCompletionRecursively(item: child, isCompleted: isCompleted)
        }
    }

    // Uncheck all ancestors up the chain
    private func uncheckAncestors(item: ChecklistItem) {
        var current = item.parent
        while let parent = current {
            parent.isCompleted = false
            current = parent.parent
        }
    }

    private func rebalanceSortOrders(for parent: ChecklistItem) {
        let sortedChildren = parent.children.sorted(by: { $0.sortOrder < $1.sortOrder })
        for (index, child) in sortedChildren.enumerated() {
            child.sortOrder = index
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        guard let sourceVisibleIndex = source.first else { return }

        let flat = self.flatItems
        let converted = flat.map { ChecklistReorderer.FlatItem(id: $0.id, item: $0.item, depth: $0.depth) }

        let moved = ChecklistReorderer.move(
            flat: converted,
            sourceVisible: sourceVisibleIndex,
            destinationVisible: destination,
            collapsingID: self.draggingItemID
        )

        ChecklistReorderer.apply(flatOrder: moved, to: self.packingList.rootItem)
        self.draggingItemID = nil
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

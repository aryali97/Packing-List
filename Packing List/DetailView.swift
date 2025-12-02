import SwiftUI
import SwiftData

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
        ChecklistReorderer.flatten(root: packingList.rootItem).map {
            FlatItem(id: $0.id, item: $0.item, depth: $0.depth, parentID: nil)
        }
    }

    private var visibleItems: [FlatItem] {
        let flat = flatItems
        let indices = ChecklistReorderer.visibleIndices(flat: flat.map { ChecklistReorderer.FlatItem(id: $0.id, item: $0.item, depth: $0.depth) }, collapsingID: draggingItemID)
        return indices.map { flat[$0] }
    }

    private var visibleUncompletedItems: [FlatItem] {
        let flat = flatItems
        let conv = flat.map { ChecklistReorderer.FlatItem(id: $0.id, item: $0.item, depth: $0.depth) }
        let indices = ChecklistReorderer.visibleIndices(flat: conv, collapsingID: draggingItemID)
        return indices.map { flat[$0] }.filter { !isFullyCompleted($0.item) }
    }

    private var editableItems: [FlatItem] {
        packingList.isTemplate ? visibleItems : visibleUncompletedItems
    }

    // Check if item and all its descendants are completed
    private func isFullyCompleted(_ item: ChecklistItem) -> Bool {
        // Item itself must be completed
        guard item.isCompleted else { return false }

        // All children must be fully completed
        for child in item.children {
            if !isFullyCompleted(child) {
                return false
            }
        }

        return true
    }

    // Items that are not fully completed (item or any descendant unchecked)
    private var uncompletedItems: [FlatItem] {
        flatItems.filter { !isFullyCompleted($0.item) }
    }

    // Completed items with their parent chain preserved
    private var completedItemsWithParents: [FlatItem] {
        var result: [FlatItem] = []
        var includedIDs = Set<UUID>()

        // First pass: collect all fully completed items
        let fullyCompletedItems = flatItems.filter { isFullyCompleted($0.item) }

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
        List {
            Section("Details") {
                TextField("Name", text: $packingList.name)
                    .focused($isNameFocused)
                if !packingList.isTemplate {
                    DatePicker("Trip Date", selection: Binding(get: {
                        packingList.tripDate ?? Date()
                    }, set: {
                        packingList.tripDate = $0
                    }), displayedComponents: .date)
                }
            }

            // Main items section
            Section("Items") {
                if packingList.isTemplate {
                    // Template view - no checkboxes
                    ForEach(visibleItems) { flat in
                        ChecklistRowView(
                            item: flat.item,
                            depth: flat.depth,
                            showCheckbox: false,
                            focusBinding: $focusedItemID,
                            onDragStart: { withAnimation(.easeInOut(duration: 0.2)) { draggingItemID = flat.item.id } },
                            onDragEnd: { withAnimation(.easeInOut(duration: 0.2)) { draggingItemID = nil } },
                            onSubmit: { handleSubmit(for: flat.item) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .onMove(perform: moveItems)
                    .animation(.easeInOut(duration: 0.25), value: visibleItems.map { $0.id })
                    .animation(.easeInOut(duration: 0.25), value: draggingItemID)
                } else {
                    // Trip view - show checkboxes and uncompleted items only
                    ForEach(visibleUncompletedItems) { flat in
                        ChecklistRowView(
                            item: flat.item,
                            depth: flat.depth,
                            showCheckbox: true,
                            isInCompletedSection: false,
                            isImmutable: false,
                            focusBinding: $focusedItemID,
                            onDragStart: { withAnimation(.easeInOut(duration: 0.2)) { draggingItemID = flat.item.id } },
                            onDragEnd: { withAnimation(.easeInOut(duration: 0.25).delay(0.05)) { draggingItemID = nil } },
                            onCheckToggle: { toggleItemCompletion(item: flat.item) },
                            onSubmit: { handleSubmit(for: flat.item) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .onMove(perform: moveItems)
                    .animation(.easeInOut(duration: 0.25), value: visibleUncompletedItems.map { $0.id })
                    .animation(.easeInOut(duration: 0.25), value: draggingItemID)
                }

                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }

            // Completed section (only for trips, not templates)
            if !packingList.isTemplate && !completedItemsWithParents.isEmpty {
                Section("Completed") {
                    ForEach(completedItemsWithParents) { flat in
                        ChecklistRowView(
                            item: flat.item,
                            depth: flat.depth,
                            showCheckbox: true,
                            isInCompletedSection: true,
                            isImmutable: !isFullyCompleted(flat.item),
                            focusBinding: $focusedItemID,
                            onCheckToggle: { toggleItemCompletion(item: flat.item) }
                        )
                    }
                }
            }
        }
        .navigationTitle(packingList.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.25), value: draggingItemID)
        .onAppear {
            if startEditingName {
                // Delay to allow view to appear before focusing
                DispatchQueue.main.async { isNameFocused = true }
            }
        }
    }

    private func handleSubmit(for item: ChecklistItem) {
        let newItem = insertItem(after: item)
        focusedItemID = newItem.id
    }

    private func insertItem(after item: ChecklistItem) -> ChecklistItem {
        let parent = item.parent ?? packingList.rootItem
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

        modelContext.insert(newItem)
        rebalanceSortOrders(for: parent)
        try? modelContext.save()
        return newItem
    }

    private func addItem() {
        let rootItem = packingList.rootItem

        let maxOrder = rootItem.children.map { $0.sortOrder }.max() ?? -1
        let newItem = ChecklistItem(title: "", sortOrder: maxOrder + 1)
        newItem.parent = rootItem

        modelContext.insert(newItem)

        // Force save to update the relationship and trigger UI refresh
        try? modelContext.save()
        focusedItemID = newItem.id
    }

    // Toggle completion and handle children recursively
    private func toggleItemCompletion(item: ChecklistItem) {
        let newCompletionState = !item.isCompleted

        if newCompletionState {
            // Checking: set this item and all children to completed
            setCompletionRecursively(item: item, isCompleted: true)
        } else {
            // Unchecking: set this item and all children to uncompleted
            setCompletionRecursively(item: item, isCompleted: false)
            // Also uncheck all ancestors
            uncheckAncestors(item: item)
        }

        try? modelContext.save()
    }

    // Recursively set completion state for item and all children
    private func setCompletionRecursively(item: ChecklistItem, isCompleted: Bool) {
        item.isCompleted = isCompleted
        for child in item.children {
            setCompletionRecursively(item: child, isCompleted: isCompleted)
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

        let flat = flatItems
        let converted = flat.map { ChecklistReorderer.FlatItem(id: $0.id, item: $0.item, depth: $0.depth) }

        let moved = ChecklistReorderer.move(
            flat: converted,
            sourceVisible: sourceVisibleIndex,
            destinationVisible: destination,
            collapsingID: draggingItemID
        )

        ChecklistReorderer.apply(flatOrder: moved, to: packingList.rootItem)
        draggingItemID = nil
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

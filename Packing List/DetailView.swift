import Combine
import ObjectiveC
import SwiftData
import SwiftUI

// MARK: - Touch End Observer

/// Observes when touches begin using method swizzling on UIWindow.
/// Used to detect when user starts a new interaction after abandoning a drag.
extension Notification.Name {
    static let newTouchBegan = Notification.Name("newTouchBegan")
}

class TouchBeginObserver {
    static let shared = TouchBeginObserver()
    private var isInstalled = false

    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let originalSelector = #selector(UIWindow.sendEvent(_:))
        let swizzledSelector = #selector(UIWindow.swizzled_sendEvent_begin(_:))

        guard let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UIWindow {
    @objc func swizzled_sendEvent_begin(_ event: UIEvent) {
        // Call original implementation
        swizzled_sendEvent_begin(event)

        guard event.type == .touches, let allTouches = event.allTouches else { return }

        // Check for new touch beginning
        let hasBeganTouch = allTouches.contains { $0.phase == .began }
        if hasBeganTouch {
            NotificationCenter.default.post(name: .newTouchBegan, object: nil)
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @Bindable var packingList: PackingList
    var startEditingName: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var draggingItemID: UUID?
    @State private var dragStartTime: Date?
    @State private var dragCancellationTask: Task<Void, Never>?
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
                            onDragStart: { self.handleDragStart(itemID: flat.item.id) },
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
                            onDragStart: { self.handleDragStart(itemID: flat.item.id) },
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
        .onAppear {
            if self.startEditingName {
                // Delay to allow view to appear before focusing
                DispatchQueue.main.async { self.isNameFocused = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTouchBegan)) { _ in
            // When a new touch begins, if we have a pending drag state
            // (draggingItemID is set but onMove hasn't fired), reset it.
            // This handles the case where user abandons a drag by touching elsewhere.
            guard self.draggingItemID != nil else { return }

            // Ignore if this touch is too close to drag start (it's the drag touch itself)
            if let startTime = self.dragStartTime,
               Date().timeIntervalSince(startTime) < 0.5 {
                return
            }

            // Cancel the timeout task and reset immediately
            self.dragCancellationTask?.cancel()
            self.dragCancellationTask = nil

            withAnimation(.easeInOut(duration: 0.25)) {
                self.draggingItemID = nil
                self.dragStartTime = nil
            }
        }
    }

    private func handleDragStart(itemID: UUID) {
        // Cancel any existing cancellation task
        self.dragCancellationTask?.cancel()

        // Record when drag started
        self.dragStartTime = Date()

        // Collapse children immediately
        withAnimation(.easeInOut(duration: 0.2)) {
            self.draggingItemID = itemID
        }

        // Start a timeout task that will reset draggingItemID if onMove doesn't fire.
        // This handles the case where user holds for a long time without moving.
        // Most drags are cancelled by the newTouchBegan observer, but this is a fallback.
        let capturedID = itemID
        self.dragCancellationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds

            // If task was cancelled (by onMove) or draggingItemID changed, do nothing
            guard !Task.isCancelled, self.draggingItemID == capturedID else { return }

            // If we get here after 10 seconds and draggingItemID is still set,
            // it means onMove never fired. Reset the drag state.
            withAnimation(.easeInOut(duration: 0.25)) {
                self.draggingItemID = nil
                self.dragStartTime = nil
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

        // Cancel the cancellation task since we completed a real move
        self.dragCancellationTask?.cancel()
        self.dragCancellationTask = nil

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
        self.dragStartTime = nil
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

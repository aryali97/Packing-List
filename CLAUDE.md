# AGENTS: Project Guide

This document helps agents and contributors quickly understand the architecture, behaviors, and extension points of this SwiftUI + SwiftData app.

## What the app does

A packing list manager with hierarchical checklist items. Users can:
- Create templates (reusable lists) and trips (actual packing sessions).
- For trips, check/uncheck items; completed items move to a separate section.
- Reorder items (including whole subtrees) via drag-and-drop and adjust hierarchy via horizontal drags (indent/outdent).
- Edit item titles inline, add new items, and delete items with keyboard/backspace affordances.

The app persists data using SwiftData and models a single hidden root item per list to contain all user-visible items.

## Key modules and data model

- PackingList (@Model)
  - Fields: id, name, isTemplate, tripDate?, colorHex
  - rootItem: ChecklistItem (hidden container; deleteRule .cascade)
  - Templates have isTemplate == true; trips have isTemplate == false and usually a tripDate.

- ChecklistItem (@Model)
  - Fields: id, title, isCompleted, sortOrder
  - Relationships: children [ChecklistItem] (cascade), parent ChecklistItem?
  - Transferable for drag/drop; Codable used narrowly for ID transfer.

- ChecklistReorderer (pure Swift utility)
  - flatten(root:): Preorder traversal into a flat array with depth.
  - visibleIndices(flat:, collapsingID:): Collapses a subtree during drag to reduce visual complexity.
  - move(flat:, sourceVisible:, destinationVisible:, collapsingID:): Moves a contiguous subtree block, adjusts depth and insertion point.
  - apply(flatOrder:, to:): Applies a flattened order back into parent/child relationships and sortOrder.

## Main UI

- DetailView
  - Shows a PackingList’s details and its items.
  - For templates: shows all visible items without checkboxes.
  - For trips: shows only uncompleted items in the main section with checkboxes; completed items are shown in a “Completed” section with parent chain preserved.
  - Supports adding items, inline editing, focus management, drag-collapsing effects, and reordering.
  - Uses SwiftData @Query to react to changes/deletions.

- ChecklistRowView
  - A single row representing a ChecklistItem.
  - Features:
    - Drag handle (not shown in Completed section).
    - Checkbox (trips only, unless immutable in Completed section).
    - Inline text editing with a custom Backspace-aware UITextField wrapper:
      - Pressing Return triggers onSubmit to insert a new item after the current row.
      - Backspace on an empty title deletes the item and moves focus to the previous visible row.
    - Indent/outdent via horizontal drag gestures with thresholds.
    - Delete button appears in edit mode or when focused.
    - Focus management via FocusState binding.

- CreateTripView
  - Creates a new trip, optionally merging selected templates by deep-copying their items into the new trip’s root.

## Completion behavior (trips)

- Toggling completion on an item:
  - Checking sets the item and all descendants to completed.
  - Unchecking sets the item and all descendants to uncompleted, and also unchecks all ancestors.
- “Uncompleted” items (used to decide visibility in the main section) means: the item or any of its descendants is not completed.
- “Completed” section shows fully completed items (item and all descendants completed) with their ancestor chain preserved for context. Items that are ancestors of completed items but themselves not fully completed are shown as immutable entries in the Completed section.

## Reordering and visibility

- During a drag, the dragged item’s subtree is visually collapsed (children hidden) for clarity.
- Reordering logic:
  - DetailView converts ChecklistItems to ChecklistReorderer.FlatItem and delegates move calculations to ChecklistReorderer.
  - After move, apply(flatOrder:, to:) mutates parent relationships and sortOrder.
  - Sort orders are zero-based and contiguous within a parent after rebalancing.

- Indent/outdent (ChecklistRowView)
  - Horizontal drag to the right (> threshold) indents under the previous sibling.
  - Horizontal drag to the left (< -threshold) outdents to the parent’s parent, inserted right after the previous parent.
  - Rebalances sibling sortOrder after structural changes.

## Persistence

- SwiftData is used throughout with @Model types.
- Inserts, deletes, and structure changes are persisted via modelContext and explicit save calls where needed.
- rootItem is an invisible container node; user-visible items are its descendants.

## Keyboard and focus

- Pressing Return in a row commits text (removing newlines) and inserts a new item after the current row, focusing it.
- Backspace on an empty row deletes it and focuses the previous visible row (preorder), or the parent if no previous sibling exists (excluding the hidden root).
- DetailView can auto-focus the list name when startEditingName is true.

## Known edge cases and notes

- Transferable/drag: ChecklistItem conforms to Codable only for transferring IDs. If you need full object transfer across processes, consider ProxyRepresentation or a custom transferable struct carrying the UUID and look up the SwiftData object on drop.
- Completed section immutability: Ancestor rows shown for context may be immutable when not fully completed; they still present checkboxes for consistency but are visually subdued.
- Depth bounds: ChecklistReorderer.move clamps new base depth to at least 1 and at most previousDepth + 1 to prevent invalid structure.
- Rebalancing: Always ensure siblings have contiguous sortOrder after structural changes to keep flattening predictable.

## Extending the app

- Adding attributes to items (e.g., quantity, notes, tags):
  - Extend ChecklistItem and adjust ChecklistRowView to render/edit new fields.
  - Consider how completion should interact with quantities (e.g., partial completion).
- Multi-select operations:
  - Add edit mode tooling to bulk complete, delete, or indent/outdent.
- Search and filtering:
  - Add a searchable modifier and filter visibleItems accordingly.
- Sharing/export:
  - Provide export to text/JSON; import into a new template.
- iCloud sync:
  - Switch to a shared SwiftData container with iCloud support if needed.

## Testing ideas (Swift Testing)

- ChecklistReorderer unit tests for:
  - flatten order and depth
  - visibleIndices with/without collapsing
  - move with different subtree sizes and destinations
  - apply producing valid parent/sortOrder assignments
- Completion propagation:
  - Toggling completeness updates descendants and ancestors as expected.
- Insertion and deletion:
  - Inserting after an item rebalances sort orders correctly.
  - Deleting focuses previous visible row.

Example:

```swift
import Testing

@Suite("ChecklistReorderer")
struct ReordererTests {
    @Test("visibleIndices respects collapsingID")
    func visibleIndicesCollapsing() {
        // Build a small tree and flatten; assert collapsed indices match expectations.
        #expect(true) // Replace with real assertions when helpers are available.
    }
}

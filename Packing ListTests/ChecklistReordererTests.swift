@testable import Packing_List
import SwiftData
import XCTest

@MainActor
final class ChecklistReordererTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        self.modelContainer = try! ModelContainer(for: ChecklistItem.self, PackingList.self, configurations: config)
        self.modelContext = self.modelContainer.mainContext
    }

    override func tearDown() {
        self.modelContainer = nil
        self.modelContext = nil
        super.tearDown()
    }

    func testMoveBlockForwardKeepsChildrenTogether() {
        let root = self.makeRoot([
            ("A", 1),
            ("B", 1),
            ("C", 2),
            ("D", 1),
            ("E", 1),
        ])

        var flat = ChecklistReorderer.flatten(root: root)
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 1, // B (has child C)
            destinationVisible: 3, // after D
            collapsingID: flat[1].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(self.namesAndDepths(root), [
            NameDepth(name: "A", depth: 1),
            NameDepth(name: "D", depth: 1),
            NameDepth(name: "B", depth: 1),
            NameDepth(name: "C", depth: 2),
            NameDepth(name: "E", depth: 1),
        ])
    }

    func testMoveBlockBackwardKeepsChildrenTogether() {
        let root = self.makeRoot([
            ("A", 1),
            ("B", 1),
            ("C", 2),
            ("D", 1),
        ])

        var flat = ChecklistReorderer.flatten(root: root)
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 0, // A
            destinationVisible: 4, // after D
            collapsingID: flat[0].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(self.namesAndDepths(root), [
            NameDepth(name: "B", depth: 1),
            NameDepth(name: "C", depth: 2),
            NameDepth(name: "D", depth: 1),
            NameDepth(name: "A", depth: 1),
        ])
    }

    func testMoveWithinSameParentKeepsDepth() {
        let root = self.makeRoot([
            ("A", 1),
            ("B", 1),
            ("C", 1),
        ])

        var flat = ChecklistReorderer.flatten(root: root)
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 2, // C
            destinationVisible: 1, // before B
            collapsingID: flat[2].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(self.namesAndDepths(root), [
            NameDepth(name: "A", depth: 1),
            NameDepth(name: "C", depth: 1),
            NameDepth(name: "B", depth: 1),
        ])
    }

    // MARK: - New tests for first-item downward moves when dragging collapsed

    func testMoveFirstBlockAfterLastChild_InsertsAfter() {
        // A1, B2, C2, D1, E2, F2 — Move A after F
        let root = self.makeRoot([
            ("A", 1),
            ("B", 2),
            ("C", 2),
            ("D", 1),
            ("E", 2),
            ("F", 2),
        ])

        var flat = ChecklistReorderer.flatten(root: root)

        // Visible before with A collapsed: [A, D, E, F] => indices 0..3
        // Drop after F => destinationVisible = 4
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 0, // A (collapsed)
            destinationVisible: 4, // after F (end)
            collapsingID: flat[0].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(self.namesAndDepths(root), [
            NameDepth(name: "D", depth: 1),
            NameDepth(name: "E", depth: 2),
            NameDepth(name: "F", depth: 2),
            NameDepth(name: "A", depth: 1),
            NameDepth(name: "B", depth: 2),
            NameDepth(name: "C", depth: 2),
        ])
    }

    func testMoveFirstBlockAfterLastTopLevel_InsertsAfter() {
        // A1, B2, C2, D1, E2, F2, G1 — Move A after G
        let root = self.makeRoot([
            ("A", 1),
            ("B", 2),
            ("C", 2),
            ("D", 1),
            ("E", 2),
            ("F", 2),
            ("G", 1),
        ])

        var flat = ChecklistReorderer.flatten(root: root)

        // Visible before with A collapsed: [A, D, E, F, G] => indices 0..4
        // Drop after G => destinationVisible = 5
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 0, // A (collapsed)
            destinationVisible: 5, // after G (end)
            collapsingID: flat[0].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(self.namesAndDepths(root), [
            NameDepth(name: "D", depth: 1),
            NameDepth(name: "E", depth: 2),
            NameDepth(name: "F", depth: 2),
            NameDepth(name: "G", depth: 1),
            NameDepth(name: "A", depth: 1),
            NameDepth(name: "B", depth: 2),
            NameDepth(name: "C", depth: 2),
        ])
    }

    // MARK: - Helpers

    private func makeRoot(_ items: [(String, Int)]) -> ChecklistItem {
        let root = ChecklistItem(title: "root")
        self.modelContext.insert(root)

        var stack: [(ChecklistItem, Int)] = [(root, 0)]

        for (title, depth) in items {
            let node = ChecklistItem(title: title)
            self.modelContext.insert(node)

            while let last = stack.last, last.1 >= depth {
                stack.removeLast()
            }
            let parent = stack.last?.0 ?? root
            node.parent = parent
            node.sortOrder = parent.children.count
            stack.append((node, depth))
        }

        return root
    }

    private func namesAndDepths(_ root: ChecklistItem) -> [NameDepth] {
        ChecklistReorderer.flatten(root: root).map { NameDepth(name: $0.item.title, depth: $0.depth) }
    }
}

private struct NameDepth: Equatable {
    let name: String
    let depth: Int
}

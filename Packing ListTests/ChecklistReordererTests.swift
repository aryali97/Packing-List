import XCTest
@testable import Packing_List

@MainActor
final class ChecklistReordererTests: XCTestCase {

    func testMoveBlockForwardKeepsChildrenTogether() {
        let root = makeRoot([
            ("A", 1),
            ("B", 1),
            ("C", 2),
            ("D", 1),
            ("E", 1)
        ])

        var flat = ChecklistReorderer.flatten(root: root)
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 1, // B (has child C)
            destinationVisible: 3, // after D
            collapsingID: flat[1].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(namesAndDepths(root), [
            NameDepth(name: "A", depth: 1),
            NameDepth(name: "D", depth: 1),
            NameDepth(name: "B", depth: 1),
            NameDepth(name: "C", depth: 2),
            NameDepth(name: "E", depth: 1)
        ])
    }

    func testMoveBlockBackwardKeepsChildrenTogether() {
        let root = makeRoot([
            ("A", 1),
            ("B", 1),
            ("C", 2),
            ("D", 1)
        ])

        var flat = ChecklistReorderer.flatten(root: root)
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 0, // A
            destinationVisible: 3, // after D
            collapsingID: flat[0].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(namesAndDepths(root), [
            NameDepth(name: "B", depth: 1),
            NameDepth(name: "C", depth: 2),
            NameDepth(name: "D", depth: 1),
            NameDepth(name: "A", depth: 1)
        ])
    }

    func testMoveWithinSameParentKeepsDepth() {
        let root = makeRoot([
            ("A", 1),
            ("B", 1),
            ("C", 1)
        ])

        var flat = ChecklistReorderer.flatten(root: root)
        flat = ChecklistReorderer.move(
            flat: flat,
            sourceVisible: 2, // C
            destinationVisible: 1, // before B
            collapsingID: flat[2].id
        )
        ChecklistReorderer.apply(flatOrder: flat, to: root)

        XCTAssertEqual(namesAndDepths(root), [
            NameDepth(name: "A", depth: 1),
            NameDepth(name: "C", depth: 1),
            NameDepth(name: "B", depth: 1)
        ])
    }

    // MARK: - Helpers

    private func makeRoot(_ items: [(String, Int)]) -> ChecklistItem {
        let root = ChecklistItem(title: "root")
        var stack: [(ChecklistItem, Int)] = [(root, 0)]

        for (title, depth) in items {
            let node = ChecklistItem(title: title)
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

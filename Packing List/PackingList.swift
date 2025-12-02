import Foundation
import SwiftData

@Model
final class PackingList {
    var id: UUID
    var name: String
    var isTemplate: Bool
    var tripDate: Date?
    var colorHex: String

    // Single root item (invisible container for all items)
    @Relationship(deleteRule: .cascade)
    var rootItem: ChecklistItem

    init(name: String, isTemplate: Bool = false, tripDate: Date? = nil, colorHex: String = "#007AFF") {
        self.id = UUID()
        self.name = name
        self.isTemplate = isTemplate
        self.tripDate = tripDate
        self.colorHex = colorHex

        // Create invisible root item
        let root = ChecklistItem(title: "", sortOrder: 0)
        self.rootItem = root
    }
}

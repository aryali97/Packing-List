import Foundation
import SwiftData

@Model
final class PackingList {
    var id: UUID
    var name: String
    var isTemplate: Bool
    var tripDate: Date?
    var colorHex: String
    
    // Root items
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.packingList)
    var items: [ChecklistItem] = []
    
    init(name: String, isTemplate: Bool = false, tripDate: Date? = nil, colorHex: String = "#007AFF") {
        self.id = UUID()
        self.name = name
        self.isTemplate = isTemplate
        self.tripDate = tripDate
        self.colorHex = colorHex
    }
}

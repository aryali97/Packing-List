import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var isSkipped: Bool
    var sortOrder: Int
    
    // Recursive relationship
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.parent)
    var children: [ChecklistItem]?
    
    @Relationship
    var parent: ChecklistItem?
    
    var packingList: PackingList?
    
    init(title: String, isCompleted: Bool = false, isSkipped: Bool = false, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
        self.sortOrder = sortOrder
        self.children = []
    }
}

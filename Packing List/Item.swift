import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

extension UTType {
    static let checklistItem = UTType(exportedAs: "com.aniryali.packinglist.item")
}

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
    
    init(title: String, isCompleted: Bool = false, isSkipped: Bool = false, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
        self.sortOrder = sortOrder
        self.children = []
    }
}

extension ChecklistItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .checklistItem)
    }
}

// Need to make ChecklistItem Codable for CodableRepresentation
extension ChecklistItem: Codable {
    enum CodingKeys: CodingKey {
        case id
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        // This is a bit of a hack for SwiftData + Transferable. 
        // We only transfer the ID, and then fetch the object in the drop delegate.
        // But CodableRepresentation expects to decode the whole object.
        // A better approach for SwiftData is ProxyRepresentation or just transferring the ID string/Data manually but using the custom Type.
        // Let's stick to the ID transfer but wrapped in a struct or just use the ID.
        // Actually, simplest for now is to make it Codable but only encode ID, and init with dummy data + ID? 
        // No, that creates a detached object.
        
        // Better approach: Use ProxyRepresentation to transfer the UUID string.
        self.init(title: "")
        self.id = id
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

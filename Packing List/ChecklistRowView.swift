import SwiftUI
import SwiftData

struct ChecklistRowView: View {
    @Bindable var item: ChecklistItem
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded: Bool = true
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let children = item.children, !children.isEmpty {
                ForEach(children.sorted(by: { $0.title < $1.title })) { child in
                    ChecklistRowView(item: child)
                }
                .onDelete(perform: deleteChild)
            }
            
            Button(action: addChild) {
                Label("Add Sub-item", systemImage: "plus")
                    .font(.caption)
            }
            .padding(.leading)
        } label: {
            HStack {
                Toggle(isOn: $item.isCompleted) {
                    EmptyView()
                }
                .labelsHidden()
                
                TextField("Item Name", text: $item.title)
                    .strikethrough(item.isSkipped)
                    .opacity(item.isSkipped ? 0.5 : 1.0)
                
                Spacer()
                
                if item.isSkipped {
                    Image(systemName: "nosign")
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    deleteSelf()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                
                Button {
                    item.isSkipped.toggle()
                } label: {
                    Label(item.isSkipped ? "Unskip" : "Skip", systemImage: "nosign")
                }
            }
        }
    }
    
    private func addChild() {
        let newChild = ChecklistItem(title: "New Item")
        newChild.parent = item
        // item.children?.append(newChild) // Relationship managed by SwiftData, but setting parent is usually enough.
        // However, to update UI immediately, we might need to append if the relationship is not auto-updating the array in memory immediately.
        // Safest is to insert into context.
        modelContext.insert(newChild)
        // Ensure expansion
        isExpanded = true
    }
    
    private func deleteChild(offsets: IndexSet) {
        guard let children = item.children else { return }
        let sortedChildren = children.sorted(by: { $0.title < $1.title })
        for index in offsets {
            modelContext.delete(sortedChildren[index])
        }
    }
    
    private func deleteSelf() {
        modelContext.delete(item)
    }
}

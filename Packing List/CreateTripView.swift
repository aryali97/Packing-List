import SwiftUI
import SwiftData

struct CreateTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<PackingList> { $0.isTemplate == true }, sort: \PackingList.name)
    private var templates: [PackingList]
    
    @State private var tripName: String = ""
    @State private var tripDate: Date = Date()
    @State private var selectedTemplates: Set<PackingList> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Details") {
                    TextField("Trip Name", text: $tripName)
                    DatePicker("Date", selection: $tripDate, displayedComponents: .date)
                }
                
                Section("Select Templates") {
                    if templates.isEmpty {
                        Text("No templates available. Create one in the Templates tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(templates) { template in
                            HStack {
                                Text(template.name)
                                Spacer()
                                if selectedTemplates.contains(template) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedTemplates.contains(template) {
                                    selectedTemplates.remove(template)
                                } else {
                                    selectedTemplates.insert(template)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTrip()
                    }
                    .disabled(tripName.isEmpty)
                }
            }
        }
    }
    
    private func createTrip() {
        let newTrip = PackingList(name: tripName, isTemplate: false, tripDate: tripDate)
        
        // Deep copy items from selected templates
        for template in selectedTemplates {
            let templateRoot = template.rootItem
            let templateChildren = templateRoot.children
            guard !templateChildren.isEmpty else { continue }
            
            let newTripRoot = newTrip.rootItem
            
            for item in templateChildren {
                let copiedItem = deepCopy(item: item)
                copiedItem.parent = newTripRoot
            }
        }
        
        modelContext.insert(newTrip)
        dismiss()
    }
    
    // Recursive deep copy function
    private func deepCopy(item: ChecklistItem) -> ChecklistItem {
        let newItem = ChecklistItem(title: item.title, isCompleted: false, sortOrder: item.sortOrder)
        
        for child in item.children {
            let newChild = deepCopy(item: child)
            newChild.parent = newItem
        }
        
        return newItem
    }
}

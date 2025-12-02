import SwiftData
import SwiftUI

struct CreateTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<PackingList> { $0.isTemplate == true }, sort: \PackingList.name)
    private var templates: [PackingList]

    var onCreate: ((PackingList) -> Void)?

    @State private var tripName: String = ""
    @State private var tripDate: Date = .init()
    @State private var selectedTemplates: Set<PackingList> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Details") {
                    TextField("Trip Name", text: self.$tripName)
                    DatePicker("Date", selection: self.$tripDate, displayedComponents: .date)
                }

                Section("Select Templates") {
                    if self.templates.isEmpty {
                        Text("No templates available. Create one in the Templates tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(self.templates) { template in
                            HStack {
                                Text(template.name)
                                Spacer()
                                if self.selectedTemplates.contains(template) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if self.selectedTemplates.contains(template) {
                                    self.selectedTemplates.remove(template)
                                } else {
                                    self.selectedTemplates.insert(template)
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
                        self.dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        self.createTrip()
                    }
                    .disabled(self.tripName.isEmpty)
                }
            }
        }
    }

    private func createTrip() {
        let newTrip = PackingList(name: tripName, isTemplate: false, tripDate: tripDate)

        // Deep copy items from selected templates
        for template in self.selectedTemplates {
            let templateRoot = template.rootItem
            let templateChildren = templateRoot.children
            guard !templateChildren.isEmpty else { continue }

            let newTripRoot = newTrip.rootItem

            for item in templateChildren {
                let copiedItem = self.deepCopy(item: item)
                copiedItem.parent = newTripRoot
            }
        }

        self.modelContext.insert(newTrip)
        self.onCreate?(newTrip)
        self.dismiss()
    }

    // Recursive deep copy function
    private func deepCopy(item: ChecklistItem) -> ChecklistItem {
        let newItem = ChecklistItem(title: item.title, isCompleted: false, sortOrder: item.sortOrder)

        for child in item.children {
            let newChild = self.deepCopy(item: child)
            newChild.parent = newItem
        }

        return newItem
    }
}

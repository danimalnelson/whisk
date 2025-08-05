import SwiftUI

struct SettingsView: View {
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Measurement System") {
                    HStack {
                        Text("Use Metric System")
                        Spacer()
                        Toggle("", isOn: $dataManager.useMetricSystem)
                            .onChange(of: dataManager.useMetricSystem) { _ in
                                dataManager.toggleMetricSystem()
                            }
                    }
                }
                
                Section("Grocery Lists") {
                    ForEach(dataManager.groceryLists) { list in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(list.name)
                                    .font(.headline)
                                Text("\(list.ingredients.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if dataManager.currentList?.id == list.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dataManager.currentList = list
                        }
                    }
                    .onDelete(perform: deleteLists)
                }
                
                Section("Data Management") {
                    Button("Clear All Data") {
                        // TODO: Implement clear all data
                    }
                    .foregroundColor(.red)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func deleteLists(offsets: IndexSet) {
        for index in offsets {
            dataManager.deleteList(dataManager.groceryLists[index])
        }
    }
}

#Preview {
    SettingsView(dataManager: DataManager())
} 
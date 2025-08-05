import SwiftUI

struct GroceryListView: View {
    @ObservedObject var dataManager: DataManager
    @State private var showingCreateList = false
    @State private var showingSettings = false
    @State private var newListName = ""
    
    var body: some View {
        NavigationView {
            VStack {
                if dataManager.groceryLists.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Grocery Lists")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Create your first grocery list to get started")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Create New List") {
                            showingCreateList = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    // List of Grocery Lists
                    List {
                        ForEach(dataManager.groceryLists) { list in
                            NavigationLink(destination: GroceryListDetailView(dataManager: dataManager, list: list)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
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
                            }
                        }
                        .onDelete(perform: deleteLists)
                    }
                }
            }
            .navigationTitle("Grocery Lists")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreateList = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingCreateList) {
                CreateListView(dataManager: dataManager, isPresented: $showingCreateList)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(dataManager: dataManager)
            }
        }
    }
    
    private func deleteLists(offsets: IndexSet) {
        for index in offsets {
            dataManager.deleteList(dataManager.groceryLists[index])
        }
    }
}

struct CreateListView: View {
    @ObservedObject var dataManager: DataManager
    @Binding var isPresented: Bool
    @State private var listName = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create New List")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                TextField("List Name", text: $listName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button("Create List") {
                    if !listName.isEmpty {
                        dataManager.createNewList(name: listName)
                        isPresented = false
                    }
                }
                .disabled(listName.isEmpty)
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct GroceryListDetailView: View {
    @ObservedObject var dataManager: DataManager
    let list: GroceryList
    @State private var showingRecipeInput = false
    
    // Get the current version of this list from the DataManager
    private var currentList: GroceryList? {
        let found = dataManager.groceryLists.first { $0.id == list.id }
        print("🔍 GroceryListDetailView: Looking for list '\(list.name)' (ID: \(list.id))")
        print("🔍 Found list: \(found?.name ?? "nil") with \(found?.ingredients.count ?? 0) ingredients")
        return found
    }
    
    var body: some View {
        VStack {
            if let currentList = currentList, currentList.ingredients.isEmpty {
                // Empty List State
                VStack(spacing: 20) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("Empty List")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Add some recipes to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Add Recipes") {
                        showingRecipeInput = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let currentList = currentList {
                // Grocery List Content
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(GroceryCategory.allCases, id: \.self) { category in
                            if let ingredients = currentList.ingredientsByCategory[category],
                               !ingredients.isEmpty {
                                CategorySection(
                                    category: category,
                                    ingredients: ingredients,
                                    dataManager: dataManager
                                )
                            }
                        }
                    }
                    .padding()
                }
                
                // Bottom Action Bar
                Button(action: { showingRecipeInput = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Recipes")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
            } else {
                // Fallback: Show empty state if currentList is nil
                VStack(spacing: 20) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("List Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("This list may have been deleted or is unavailable")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Go Back") {
                        // This will be handled by navigation
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .navigationTitle(currentList?.name ?? list.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingRecipeInput) {
            RecipeInputView(dataManager: dataManager, targetList: currentList)
        }
    }
}

struct CategorySection: View {
    let category: GroceryCategory
    let ingredients: [Ingredient]
    let dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(.blue)
                
                Text(category.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(ingredients.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVStack(spacing: 4) {
                ForEach(ingredients) { ingredient in
                    IngredientRow(
                        ingredient: ingredient,
                        dataManager: dataManager
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct IngredientRow: View {
    let ingredient: Ingredient
    let dataManager: DataManager
    
    var body: some View {
        HStack {
            Button(action: {
                dataManager.toggleIngredientChecked(ingredient)
            }) {
                Image(systemName: ingredient.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(ingredient.isChecked ? .green : .gray)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(.body)
                    .strikethrough(ingredient.isChecked)
                    .foregroundColor(ingredient.isChecked ? .secondary : .primary)
                
                Text("\(String(format: "%.1f", ingredient.amount)) \(ingredient.unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                dataManager.removeIngredient(ingredient)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GroceryListView(dataManager: DataManager())
} 
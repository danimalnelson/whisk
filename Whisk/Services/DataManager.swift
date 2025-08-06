import Foundation
import SwiftUI

class DataManager: ObservableObject {
    @Published var groceryLists: [GroceryList] = []
    @Published var currentList: GroceryList?
    private let userDefaults = UserDefaults.standard
    private let groceryListsKey = "groceryLists"
    private let currentListKey = "currentList"
    
    init() {
        loadData()
    }
    
    // MARK: - Grocery Lists Management
    
    func createNewList(name: String) -> GroceryList {
        let newList = GroceryList(name: name)
        groceryLists.append(newList)
        currentList = newList
        saveData()
        return newList
    }
    
    func updateCurrentList(_ list: GroceryList) {
        if let index = groceryLists.firstIndex(where: { $0.id == list.id }) {
            groceryLists[index] = list
            currentList = list
            saveData()
        } else {
            print("❌ Could not find list with ID: \(list.id)")
        }
    }
    
    func deleteList(_ list: GroceryList) {
        groceryLists.removeAll { $0.id == list.id }
        if currentList?.id == list.id {
            currentList = groceryLists.first
        }
        saveData()
    }
    
    // MARK: - Ingredients Management
    
    func addIngredientsToCurrentList(_ ingredients: [Ingredient]) {
        // Create a default list if none exists
        if currentList == nil {
            createNewList(name: "Shopping List")
        }
        
        guard var list = currentList else { 
            print("❌ Failed to get current list after creation")
            return 
        }
        
        // Merge ingredients with existing ones
        for newIngredient in ingredients {
            if let existingIndex = list.ingredients.firstIndex(where: { 
                $0.name.lowercased() == newIngredient.name.lowercased() && 
                $0.category == newIngredient.category 
            }) {
                // Combine amounts if same ingredient
                list.ingredients[existingIndex].amount += newIngredient.amount
            } else {
                list.ingredients.append(newIngredient)
            }
        }
        
        updateCurrentList(list)
    }
    
    func addIngredientsToList(_ ingredients: [Ingredient], list: GroceryList) {
        print("🛒 Adding \(ingredients.count) ingredients to specific list: \(list.name)")
        print("🛒 List ingredients count before: \(list.ingredients.count)")
        
        guard let listIndex = groceryLists.firstIndex(where: { $0.id == list.id }) else {
            print("❌ Could not find list with ID: \(list.id)")
            return
        }
        
        var updatedList = groceryLists[listIndex]
        
        // Merge ingredients with existing ones
        for newIngredient in ingredients {
            print("🛒 Processing ingredient: \(newIngredient.name) - \(newIngredient.amount) \(newIngredient.unit)")
            
            if let existingIndex = updatedList.ingredients.firstIndex(where: { 
                $0.name.lowercased() == newIngredient.name.lowercased() && 
                $0.category == newIngredient.category 
            }) {
                // Combine amounts if same ingredient
                updatedList.ingredients[existingIndex].amount += newIngredient.amount
                print("🛒 Combined with existing ingredient")
            } else {
                updatedList.ingredients.append(newIngredient)
                print("🛒 Added new ingredient")
            }
        }
        
        print("🛒 Final ingredients count: \(updatedList.ingredients.count)")
        print("🛒 List name: \(updatedList.name)")
        print("🛒 List ID: \(updatedList.id)")
        
        // Update the list in the array
        groceryLists[listIndex] = updatedList
        
        // If this is the current list, update it too
        if currentList?.id == list.id {
            currentList = updatedList
        }
        
        saveData()
        print("🛒 After update - list ingredients: \(updatedList.ingredients.count)")
    }
    
    func toggleIngredientChecked(_ ingredient: Ingredient) {
        guard var list = currentList,
              let index = list.ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        
        list.ingredients[index].isChecked.toggle()
        updateCurrentList(list)
    }
    
    func toggleIngredientChecked(_ ingredient: Ingredient, in list: GroceryList) {
        guard let listIndex = groceryLists.firstIndex(where: { $0.id == list.id }),
              let ingredientIndex = groceryLists[listIndex].ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        
        groceryLists[listIndex].ingredients[ingredientIndex].isChecked.toggle()
        saveData()
    }
    
    func removeIngredient(_ ingredient: Ingredient) {
        guard var list = currentList,
              let index = list.ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        
        list.ingredients.remove(at: index)
        updateCurrentList(list)
    }
    
    func restoreIngredient(_ ingredient: Ingredient) {
        guard var list = currentList,
              let index = list.ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        
        list.ingredients[index].isRemoved = false
        updateCurrentList(list)
    }
    
    // MARK: - Data Persistence
    
    private func saveData() {
        print("💾 Saving data...")
        print("💾 Total lists: \(groceryLists.count)")
        for list in groceryLists {
            print("💾 List '\(list.name)': \(list.ingredients.count) ingredients")
        }
        print("💾 Current list: \(currentList?.name ?? "nil") with \(currentList?.ingredients.count ?? 0) ingredients")
        
        do {
            let listsData = try JSONEncoder().encode(groceryLists)
            userDefaults.set(listsData, forKey: groceryListsKey)
            print("💾 Saved grocery lists data")
            
            if let currentList = currentList {
                let currentListData = try JSONEncoder().encode(currentList)
                userDefaults.set(currentListData, forKey: currentListKey)
                print("💾 Saved current list data")
            } else {
                print("💾 No current list to save")
            }
            print("💾 Data saved successfully")
        } catch {
            print("❌ Error saving data: \(error)")
        }
    }
    
    private func loadData() {
        print("📱 Loading data...")
        
        // Load grocery lists
        if let listsData = userDefaults.data(forKey: groceryListsKey) {
            do {
                groceryLists = try JSONDecoder().decode([GroceryList].self, from: listsData)
                print("📱 Loaded \(groceryLists.count) grocery lists")
                for list in groceryLists {
                    print("📱 List: \(list.name) with \(list.ingredients.count) ingredients")
                }
            } catch {
                print("❌ Error loading grocery lists: \(error)")
            }
        } else {
            print("📱 No saved grocery lists found")
        }
        
        // Load current list and ensure it references the same list in groceryLists
        if let currentListData = userDefaults.data(forKey: currentListKey) {
            do {
                let loadedCurrentList = try JSONDecoder().decode(GroceryList.self, from: currentListData)
                print("📱 Loaded current list: \(loadedCurrentList.name) (ID: \(loadedCurrentList.id))")
                print("📱 Current list has \(loadedCurrentList.ingredients.count) ingredients")
                
                // Find the same list in groceryLists array by name (more reliable than ID)
                if let index = groceryLists.firstIndex(where: { $0.name == loadedCurrentList.name }) {
                    currentList = groceryLists[index]
                    print("📱 Found matching list by name: \(currentList?.name ?? "nil")")
                } else if let index = groceryLists.firstIndex(where: { $0.id == loadedCurrentList.id }) {
                    currentList = groceryLists[index]
                    print("📱 Found matching list by ID: \(currentList?.name ?? "nil")")
                } else {
                    // If not found, use the first list or create a default one
                    if groceryLists.isEmpty {
                        print("📱 No lists found, creating default list")
                        createNewList(name: "Shopping List")
                    } else {
                        currentList = groceryLists.first
                        print("📱 Using first list as current: \(currentList?.name ?? "nil")")
                    }
                }
            } catch {
                print("❌ Error loading current list: \(error)")
                if groceryLists.isEmpty {
                    print("📱 Creating default list after error")
                    createNewList(name: "Shopping List")
                } else {
                    currentList = groceryLists.first
                }
            }
        } else {
            print("📱 No saved current list found")
            if groceryLists.isEmpty {
                print("📱 Creating default list")
                createNewList(name: "Shopping List")
            } else {
                currentList = groceryLists.first
                print("📱 Using first list as current: \(currentList?.name ?? "nil")")
            }
        }
        
        print("📱 Data loading complete. Current list: \(currentList?.name ?? "nil") with \(currentList?.ingredients.count ?? 0) ingredients")
    }
} 
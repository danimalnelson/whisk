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
        
        // Filter out water and other common household items
        let filteredIngredients = ingredients.filter { ingredient in
            let lowercasedName = ingredient.name.lowercased()
            let excludedItems = ["water", "tap water", "filtered water", "distilled water"]
            return !excludedItems.contains(lowercasedName)
        }
        
        print("🛒 Filtered out \(ingredients.count - filteredIngredients.count) common household items")
        
        // Smart ingredient consolidation
        for newIngredient in filteredIngredients {
            if let existingIndex = findConsolidatableIngredient(newIngredient, in: list.ingredients) {
                // Combine amounts with unit conversion if needed
                let consolidatedAmount = consolidateAmounts(
                    existing: list.ingredients[existingIndex].amount,
                    existingUnit: list.ingredients[existingIndex].unit,
                    new: newIngredient.amount,
                    newUnit: newIngredient.unit
                )
                
                list.ingredients[existingIndex].amount = consolidatedAmount.amount
                list.ingredients[existingIndex].unit = consolidatedAmount.unit
                
                print("🛒 Consolidated: \(newIngredient.name) (\(newIngredient.amount) \(newIngredient.unit)) + existing → \(consolidatedAmount.amount) \(consolidatedAmount.unit)")
            } else {
                list.ingredients.append(newIngredient)
                print("🛒 Added new ingredient: \(newIngredient.name)")
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
        
        // Filter out water and other common household items
        let filteredIngredients = ingredients.filter { ingredient in
            let lowercasedName = ingredient.name.lowercased()
            let excludedItems = ["water", "tap water", "filtered water", "distilled water"]
            return !excludedItems.contains(lowercasedName)
        }
        
        print("🛒 Filtered out \(ingredients.count - filteredIngredients.count) common household items")
        
        // Smart ingredient consolidation
        for newIngredient in filteredIngredients {
            print("🛒 Processing ingredient: \(newIngredient.name) - \(newIngredient.amount) \(newIngredient.unit)")
            
            if let existingIndex = findConsolidatableIngredient(newIngredient, in: updatedList.ingredients) {
                // Combine amounts with unit conversion if needed
                let consolidatedAmount = consolidateAmounts(
                    existing: updatedList.ingredients[existingIndex].amount,
                    existingUnit: updatedList.ingredients[existingIndex].unit,
                    new: newIngredient.amount,
                    newUnit: newIngredient.unit
                )
                
                updatedList.ingredients[existingIndex].amount = consolidatedAmount.amount
                updatedList.ingredients[existingIndex].unit = consolidatedAmount.unit
                
                print("🛒 Consolidated: \(newIngredient.name) (\(newIngredient.amount) \(newIngredient.unit)) + existing → \(consolidatedAmount.amount) \(consolidatedAmount.unit)")
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
    
    // MARK: - Ingredient Consolidation
    
    private func findConsolidatableIngredient(_ newIngredient: Ingredient, in existingIngredients: [Ingredient]) -> Int? {
        let lowercasedNewName = newIngredient.name.lowercased()
        
        for (index, existing) in existingIngredients.enumerated() {
            let lowercasedExistingName = existing.name.lowercased()
            
            // Exact name match (highest priority)
            if lowercasedNewName == lowercasedExistingName && newIngredient.category == existing.category {
                return index
            }
            
            // Similar name match (e.g., "tomato" vs "tomatoes")
            if areSimilarIngredients(lowercasedNewName, lowercasedExistingName) && newIngredient.category == existing.category {
                return index
            }
        }
        
        return nil
    }
    
    private func areSimilarIngredients(_ name1: String, _ name2: String) -> Bool {
        // Handle plural/singular variations
        let singular1 = name1.replacingOccurrences(of: "s$", with: "", options: .regularExpression)
        let singular2 = name2.replacingOccurrences(of: "s$", with: "", options: .regularExpression)
        
        if singular1 == singular2 {
            return true
        }
        
        // Handle common variations
        let variations: [String: Set<String>] = [
            "tomato": ["tomatoes", "tomato"],
            "onion": ["onions", "onion"],
            "garlic": ["garlic", "garlic clove", "garlic cloves"],
            "bell pepper": ["bell peppers", "pepper", "peppers"],
            "potato": ["potatoes", "potato"],
            "carrot": ["carrots", "carrot"]
        ]
        
        for (base, variants) in variations {
            if variants.contains(name1) && variants.contains(name2) {
                return true
            }
        }
        
        return false
    }
    
    private func consolidateAmounts(existing: Double, existingUnit: String, new: Double, newUnit: String) -> (amount: Double, unit: String) {
        // If units are the same, simple addition
        if existingUnit.lowercased() == newUnit.lowercased() {
            return (existing + new, existingUnit)
        }
        
        // Convert to common units for consolidation
        let existingInGrams = convertToGrams(amount: existing, unit: existingUnit)
        let newInGrams = convertToGrams(amount: new, unit: newUnit)
        
        if existingInGrams > 0 && newInGrams > 0 {
            let totalGrams = existingInGrams + newInGrams
            return convertFromGrams(grams: totalGrams, preferredUnit: existingUnit)
        }
        
        // If conversion failed, keep existing unit and add amounts
        return (existing + new, existingUnit)
    }
    
    private func convertToGrams(amount: Double, unit: String) -> Double {
        let lowercasedUnit = unit.lowercased()
        
        // Weight conversions
        switch lowercasedUnit {
        case "ounces", "ounce", "oz":
            return amount * 28.35
        case "pounds", "pound", "lb", "lbs":
            return amount * 453.59
        case "grams", "gram", "g":
            return amount
        case "kilograms", "kilogram", "kg":
            return amount * 1000
        default:
            return 0 // Can't convert volume to weight
        }
    }
    
    private func convertFromGrams(grams: Double, preferredUnit: String) -> (amount: Double, unit: String) {
        let lowercasedPreferred = preferredUnit.lowercased()
        
        // Convert back to preferred unit
        switch lowercasedPreferred {
        case "ounces", "ounce", "oz":
            return (grams / 28.35, "ounces")
        case "pounds", "pound", "lb", "lbs":
            return (grams / 453.59, "pounds")
        case "grams", "gram", "g":
            return (grams, "grams")
        case "kilograms", "kilogram", "kg":
            return (grams / 1000, "kilograms")
        default:
            return (grams, "grams") // Default to grams
        }
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
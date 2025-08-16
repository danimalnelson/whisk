import Foundation

struct GroceryList: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var ingredients: [Ingredient]
    var createdAt: Date
    var isActive: Bool = true
    
    init(name: String, ingredients: [Ingredient] = []) {
        self.id = UUID()
        self.name = name
        self.ingredients = ingredients
        self.createdAt = Date()
    }
    
    var ingredientsByCategory: [GroceryCategory: [Ingredient]] {
        Dictionary(grouping: ingredients.filter { !$0.isRemoved }) { $0.category }
            .mapValues { group in
                group.sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }
    
    var checkedIngredients: [Ingredient] {
        ingredients.filter { $0.isChecked && !$0.isRemoved }
    }
    
    var uncheckedIngredients: [Ingredient] {
        ingredients.filter { !$0.isChecked && !$0.isRemoved }
    }
    
    var removedIngredients: [Ingredient] {
        ingredients.filter { $0.isRemoved }
    }
} 
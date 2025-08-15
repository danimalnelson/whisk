import Foundation

struct Ingredient: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var unit: String
    var category: GroceryCategory
    var isChecked: Bool = false
    var isRemoved: Bool = false
    
    init(name: String, amount: Double, unit: String, category: GroceryCategory) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.category = category
    }
}

enum GroceryCategory: String, CaseIterable, Codable {
    case produce = "Produce"
    case meatAndSeafood = "Meat & Seafood"
    case deli = "Deli"
    case bakery = "Bakery"
    case frozen = "Frozen"
    case pantry = "Pantry"
    case dairy = "Dairy"
    case beverages = "Beverages"
    
    var displayName: String {
        return rawValue
    }
    
    var icon: String {
        switch self {
        case .produce: return "leaf.fill"
        case .meatAndSeafood: return "fish.fill"
        case .deli: return "fork.knife"
        case .bakery: return "birthday.cake.fill"
        case .frozen: return "snowflake"
        case .pantry: return "cabinet.fill"
        case .dairy: return "drop.fill"
        case .beverages: return "cup.and.saucer.fill"
        }
    }
} 
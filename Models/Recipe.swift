import Foundation

struct Recipe: Identifiable, Codable {
    let id: UUID
    var url: String
    var name: String?
    var ingredients: [Ingredient]
    var isParsed: Bool = false
    var parsingError: String?
    
    init(url: String) {
        self.id = UUID()
        self.url = url
        self.ingredients = []
    }
}

struct RecipeParsingResult {
    let recipe: Recipe
    let success: Bool
    let error: String?
} 
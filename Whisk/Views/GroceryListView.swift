import SwiftUI

// MARK: - Ingredient Image Helpers
private func ingredientImageURL(for name: String) -> URL? {
    IngredientImageService.shared.url(for: name)
}

struct GroceryListView: View {
    @ObservedObject var dataManager: DataManager
    
    var body: some View {
        // Launch directly into the single list detail view within a navigation stack for a visible title
        NavigationStack {
            Group {
                if let current = dataManager.currentList {
                    GroceryListDetailView(
                        dataManager: dataManager,
                        list: current
                    )
                } else {
                    // Avoid creating/saving a new empty list during body evaluation.
                    // Ensure default list once on appear instead.
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing list…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background()
                    .onAppear {
                        _ = dataManager.createNewList(name: "Ingredients")
                    }
                }
            }
        }
    }
}

// Single-list flow: consolidated into GroceryListView and GroceryListDetailView only

struct GroceryListDetailView: View {
    @ObservedObject var dataManager: DataManager
    let list: GroceryList
    @State private var showingRecipeInput = false
    @State private var showingClearConfirm = false
    // Single-list flow: no rename/back state
    private let imageService = IngredientImageService.shared
    
    // Single-list flow: always use DataManager's current list
    private var currentList: GroceryList? { dataManager.currentList }
    
    var body: some View {
        VStack(spacing: 0) {
            if let currentList = currentList, currentList.ingredients.isEmpty {
                // Empty List State
                VStack(spacing: 20) {
                    Button(action: { showingRecipeInput = true }) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text("Empty List")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Add some recipes to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    

                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
            } else if let currentList = currentList {
                // Grocery List Content
                List {
                    ForEach(GroceryCategory.allCases, id: \.self) { category in
                        if let ingredients = currentList.ingredientsByCategory[category],
                           !ingredients.isEmpty {
                            Section(header: CategoryHeader(category: category, ingredients: ingredients)) {
                                ForEach(ingredients) { ingredient in
                                    IngredientRow(
                                        ingredient: ingredient,
                                        dataManager: dataManager,
                                        list: currentList
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            dataManager.removeIngredient(ingredient)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .onAppear {
                    // Prefetch images for this list to smooth scroll experience
                    let names = currentList.ingredients.map { $0.name }
                    imageService.prefetch(ingredientNames: names)
                }
            } else {
                // Fallback: Show empty state if currentList is nil
                VStack(spacing: 20) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("List Not Found")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("This list may have been deleted or is unavailable")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
            }
            
            // Bottom Bar (hidden when empty list)
            if let currentList = currentList, !currentList.ingredients.isEmpty {
                HStack {
                    Spacer()
                    let remaining = currentList.ingredients.filter { !$0.isChecked }.count
                    Text(remaining == 1 ? "1 item remaining" : "\(remaining) items remaining")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(.separator)),
                    alignment: .top
                )
                .confirmationDialog(
                    "",
                    isPresented: $showingClearConfirm,
                    titleVisibility: .hidden
                ) {
                    Button("Remove all ingredients?", role: .destructive) {
                        dataManager.clearAllIngredients()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .navigationTitle((currentList?.ingredients.isEmpty ?? true) ? "" : "Ingredients")
        .navigationBarTitleDisplayMode((currentList?.ingredients.isEmpty ?? true) ? .inline : .large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingRecipeInput = true
                    } label: {
                        Label("Add recipes", systemImage: "plus")
                    }
                        ShareLink(item: shareText) {
                            Label("Share list", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label("Remove all ingredients", systemImage: "eraser")
                        }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingRecipeInput) {
            RecipeInputView(dataManager: dataManager, targetList: currentList)
        }
    }
}

private extension GroceryListDetailView {
    var shareText: String {
        guard let list = currentList else { return "Ingredients" }
        var lines: [String] = ["Ingredients"]
        for ing in list.ingredients {
            let amountPart: String = ing.amount > 0 ? String(format: ing.amount.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f", ing.amount) : ""
            let unitPart: String = ing.unit.isEmpty ? "" : "\(ing.unit)"
            let amt: String
            if amountPart.isEmpty && unitPart.isEmpty {
                amt = ""
            } else if amountPart.isEmpty { // unit only
                amt = " \(unitPart)"
            } else if unitPart.isEmpty { // amount only
                amt = " \(amountPart)"
            } else { // amount + unit
                amt = " \(amountPart) \(unitPart)"
            }
            lines.append("- \(ing.name.capitalized)\(amt)")
        }
        return lines.joined(separator: "\n")
    }
}

struct CategoryHeader: View {
    let category: GroceryCategory
    let ingredients: [Ingredient]
    
    private var remainingCount: Int {
        ingredients.filter { !$0.isChecked }.count
    }
    
    private var remainingText: String {
        remainingCount == 1 ? "1 item remaining" : "\(remainingCount) items remaining"
    }
    
    var body: some View {
        HStack {
            Text(category.displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(remainingText)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
        .frame(height: 44)
    }
}

struct IngredientRow: View {
    let ingredient: Ingredient
    let dataManager: DataManager
    let list: GroceryList
    
    // MARK: - Unit Formatting Constants
    
    // Non-measurable words that should not be displayed as units
    private let nonMeasurableWords: Set<String> = [
        "piece", "pieces", "count", "individual", "item", "items",
        "stalk", "stalks", "leaf", "leaves",
        "medium", "large", "small", "extra large", "xl",
        "raw", "thin", "thick", "fresh", "frozen", "dried",
        "ripe", "unripe", "organic", "whole", "sliced", "diced",
        "minced", "chopped", "grated", "peeled", "seeded"
    ]
    
    // Unit display mappings (for UI display only)
    private let unitDisplayMappings: [String: String] = [
        "tbsp": "tablespoon", "tbs": "tablespoon", 
        "tsp": "teaspoon",
        "oz": "ounce", "lb": "pound", "lbs": "pound",
        "c": "cup", "pt": "pint", "qt": "quart",
        "gal": "gallon", "ml": "milliliter", "l": "liter",
        "g": "gram", "kg": "kilogram",
        "slice": "slice", "can": "can", "jar": "jar",
        "bottle": "bottle", "package": "package",
        "bag": "bag", "bunch": "bunch", "head": "head"
    ]
    
    // Singular form mappings for display
    private let singularMappings: [String: String] = [
        "tablespoons": "tablespoon", "teaspoons": "teaspoon",
        "ounces": "ounce", "pounds": "pound", "cups": "cup",
        "pints": "pint", "quarts": "quart", "gallons": "gallon",
        "milliliters": "milliliter", "liters": "liter",
        "grams": "gram", "kilograms": "kilogram",
        "slices": "slice", "cans": "can", "jars": "jar",
        "bottles": "bottle", "packages": "package",
        "bags": "bag", "bunches": "bunch", "heads": "head"
    ]
    
    // MARK: - Unit Formatting Methods
    
    private func formatAmountAndUnit(amount: Double, unit: String) -> String {
        // Convert decimal to fraction for common fractions
        let wholePart = Int(amount)
        let decimalPart = amount - Double(wholePart)
        
        var fractionString = ""
        if decimalPart > 0 {
            // Common fraction mappings
            let fractionMappings: [Double: String] = [
                0.25: "¼", 0.33: "⅓", 0.5: "½", 0.67: "⅔",
                0.75: "¾", 0.125: "⅛", 0.375: "⅜",
                0.625: "⅝", 0.875: "⅞"
            ]
            
            // Find the closest fraction
            let closestFraction = fractionMappings.min { abs($0.key - decimalPart) < abs($1.key - decimalPart) }
            if let (fraction, symbol) = closestFraction, abs(fraction - decimalPart) < 0.1 {
                fractionString = symbol
            } else {
                // If no close fraction, use decimal but round to 1 decimal place
                fractionString = String(format: "%.1f", decimalPart).replacingOccurrences(of: "0.", with: "")
            }
        }
        
        let amountString = wholePart > 0 ? "\(wholePart)" : ""
        let combinedAmount = amountString + fractionString
        
        // Ensure unit is properly spelled out
        let spelledOutUnit = spellOutUnit(unit)
        
        // If no unit text (individual items), just return the amount
        if spelledOutUnit.isEmpty {
            return combinedAmount
        }
        
        // Handle singular vs plural forms
        let finalUnit = formatUnitForAmount(unit: spelledOutUnit, amount: amount)
        
        // If amount is empty, return only unit (no leading space)
        if combinedAmount.isEmpty {
            return finalUnit
        }
        return "\(combinedAmount) \(finalUnit)"
    }
    
    private func spellOutUnit(_ unit: String) -> String {
        let lowercasedUnit = unit.lowercased()
        
        // If it's a non-measurable word, return empty string (just show the number)
        if nonMeasurableWords.contains(lowercasedUnit) {
            return ""
        }
        
        // Preserve preferred casing for special display units
        if lowercasedUnit == "to taste" { return "To taste" }
        
        // Return the display mapping or the original unit
        return unitDisplayMappings[lowercasedUnit] ?? lowercasedUnit
    }
    
    private func formatUnitForAmount(unit: String, amount: Double) -> String {
        // If amount is 1 or less, use singular form
        if amount <= 1.0 {
            return singularMappings[unit] ?? unit
        }
        
        // For amounts greater than 1, keep plural form
        return unit
    }
    
    private func shouldPluralizeIngredient(_ ingredientName: String, amount: Double) -> Bool {
        // Ingredients that should be pluralized when amount > 1
        let pluralizableIngredients: Set<String> = [
            "shallot", "shallots", "tomato", "tomatoes", "avocado", "avocados",
            "onion", "onions", "pepper", "peppers"
        ]
        
        let lowercasedName = ingredientName.lowercased()
        return pluralizableIngredients.contains(lowercasedName) && amount > 1.0
    }
    
    private func formatIngredientName(_ name: String, amount: Double) -> String {
        var formattedName = name.capitalized
        
        // Handle special cases for ingredient names
        let specialCases: [String: String] = [
            "tomato slices": "tomatoes",
            "onion rings": "onion rings",
            "hass avocados": "hass avocados",
            "red bell peppers": "red bell peppers",
            "grape tomatoes": "grape tomatoes"
        ]
        
        let lowercasedName = name.lowercased()
        if let specialCase = specialCases[lowercasedName] {
            formattedName = specialCase.capitalized
        }
        
        // Handle pluralization for individual items
        if shouldPluralizeIngredient(name, amount: amount) {
            // Add 's' if it doesn't already end with 's'
            if !formattedName.lowercased().hasSuffix("s") {
                formattedName += "s"
            }
        }
        
        return formattedName
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail on the left
            AsyncImage(url: ingredientImageURL(for: ingredient.name)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 30, height: 45)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 45)
                        .clipped()
                        .cornerRadius(6)
                        .transition(.opacity.combined(with: .scale))
                case .failure:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                        .overlay(
                            Image(systemName: "leaf")
                                .foregroundColor(.secondary)
                        )
                        .frame(width: 30, height: 45)
                @unknown default:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 30, height: 45)
                }
            }
            .accessibilityLabel(Text("\(formatIngredientName(ingredient.name, amount: ingredient.amount)) image"))
            .opacity(ingredient.isChecked ? 0.75 : 1.0)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(formatIngredientName(ingredient.name, amount: ingredient.amount))
                    .font(.system(size: 16, weight: .regular))
                    .strikethrough(ingredient.isChecked)
                    .foregroundColor(ingredient.isChecked ? .secondary : .primary)

                Text(formatAmountAndUnit(amount: ingredient.amount, unit: ingredient.unit))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Checkbox moved to the right
            Button(action: {
                dataManager.toggleIngredientChecked(ingredient, in: list)
            }) {
                Image(systemName: ingredient.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(ingredient.isChecked ? .white : .gray)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text(ingredient.isChecked ? "Uncheck" : "Check"))
            .accessibilityHint(Text("Marks ingredient as completed"))
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    GroceryListView(dataManager: DataManager())
} 
import SwiftUI

// Title-case helper for ingredient names that keeps small words like "and"/"or" lowercased (except at start)
private let lowercaseSmallWords: Set<String> = ["and", "or", "of", "with", "in", "on", "for", "to", "from"]

private func titleCaseIngredientName(_ name: String) -> String {
    // Preserve spacing between words
    let parts = name.split(separator: " ", omittingEmptySubsequences: false)
    guard !parts.isEmpty else { return name }

    func capSegment(_ s: String) -> String {
        guard let first = s.first else { return s }
        // Special case: leading apostrophe should not force lowercasing the next letter
        if first == "'" || first == "’" {
            let after = s.index(after: s.startIndex)
            guard after < s.endIndex else { return String(first) }
            let second = String(s[after]).uppercased()
            let rest = s.index(after, offsetBy: 1, limitedBy: s.endIndex).map { String(s[$0...]).lowercased() } ?? ""
            return String(first) + second + rest
        }
        return String(first).uppercased() + s.dropFirst().lowercased()
    }

    func capitalizeWord(_ word: String) -> String {
        // Handle hyphenated tokens by capitalizing each segment
        if word.contains("-") {
            return word.split(separator: "-").map { segment in
                capSegment(String(segment))
            }.joined(separator: "-")
        }
        return capSegment(word)
    }

    var rebuilt: [String] = []
    for (index, p) in parts.enumerated() {
        let token = String(p)
        if token.isEmpty {
            rebuilt.append(token)
            continue
        }
        // Keep small words lowercased when not at the beginning
        if index > 0 && lowercaseSmallWords.contains(token.lowercased()) {
            rebuilt.append(token.lowercased())
        } else {
            rebuilt.append(capitalizeWord(token))
        }
    }
    return rebuilt.joined(separator: " ")
}

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
            lines.append("- \(titleCaseIngredientName(ing.name))\(amt)")
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
        "stalk", "stalks",
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
        // Descriptor-only units should not show a numeric amount
        let unitLc = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if unitLc == "for serving" { return "For serving" }
        if unitLc == "to taste" { return "To taste" }

        // Hide zero amounts entirely when there is no meaningful unit
        if amount == 0 {
            let su = spellOutUnit(unit)
            return su.isEmpty ? "" : su
        }

        // Convert decimal to fraction for common fractions, with sensible rounding for near-integers
        let wholePart = Int(amount)
        let decimalPart = amount - Double(wholePart)

        // If very close to an integer, display as an integer (handles 4.999986 → 5)
        if abs(amount - round(amount)) < 0.01 {
            let rounded = Int(round(amount))
            let spelledOutUnit = spellOutUnit(unit)
            if spelledOutUnit.isEmpty { return "\(rounded)" }
            let finalUnit = formatUnitForAmount(unit: spelledOutUnit, amount: Double(rounded))
            if let parenthetical = parentheticalUnitDisplay(from: finalUnit) {
                return "\(rounded) \(parenthetical)"
            }
            return "\(rounded) \(finalUnit)"
        }

        var amountDisplay = ""
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
                // Combine whole number and fraction glyph without a separator (e.g., 1½)
                let wholeString = wholePart > 0 ? "\(wholePart)" : ""
                amountDisplay = wholeString + symbol
            } else {
                // Fallback: show one decimal place for the entire amount (e.g., 4.1)
                amountDisplay = String(format: "%.1f", amount)
            }
        } else {
            amountDisplay = "\(wholePart)"
        }

        // Ensure unit is properly spelled out
        let spelledOutUnit = spellOutUnit(unit)

        // If no unit text (individual items), just return the amount
        if spelledOutUnit.isEmpty { return amountDisplay }

        // Handle singular vs plural forms based on the numeric amount
        let finalUnit = formatUnitForAmount(unit: spelledOutUnit, amount: amount)

        // Parenthetical style for measured size units preceding a noun
        if !amountDisplay.isEmpty, let parenthetical = parentheticalUnitDisplay(from: finalUnit) {
            return "\(amountDisplay) \(parenthetical)"
        }

        // If amount is empty, return only unit (no leading space)
        if amountDisplay.isEmpty { return finalUnit }
        return "\(amountDisplay) \(finalUnit)"
    }
    
    // Extracts a size descriptor at the start of the unit and wraps it in parentheses, preserving any trailing unit noun
    private func parentheticalUnitDisplay(from unit: String) -> String? {
        // Match patterns like:
        //  - 4-pound
        //  - 13.5-ounce can
        //  - 6-7-ounce fillets
        //  - 1-inch piece
        let pattern = "(?i)^\\s*([0-9]+(?:\\.[0-9]+)?(?:\\s*-\\s*(?:to\\s*)?[0-9]+(?:\\.[0-9]+)?)?\\s*(?:ounce|ounces|oz|pound|pounds|lb|lbs|inch|inches))\\b(?:\\s+(.*))?$"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
        let r = NSRange(unit.startIndex..., in: unit)
        guard let m = rx.firstMatch(in: unit, options: [], range: r) else { return nil }
        guard m.numberOfRanges >= 2, let sr = Range(m.range(at: 1), in: unit) else { return nil }
        let size = String(unit[sr]).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let noun: String = {
            if m.numberOfRanges >= 3, let nr = Range(m.range(at: 2), in: unit), !nr.isEmpty {
                return String(unit[nr]).trimmingCharacters(in: .whitespaces)
            }
            return ""
        }()
        return noun.isEmpty ? "(\(size))" : "(\(size)) \(noun)"
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
        var formattedName = titleCaseIngredientName(name)
        
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
            formattedName = titleCaseIngredientName(specialCase)
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
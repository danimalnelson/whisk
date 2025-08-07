import SwiftUI

// MARK: - Shimmer Effect
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.8),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: -200 + (phase * 400))
                .animation(
                    Animation.linear(duration: 1.4),
                    value: phase
                )
                .blendMode(.overlay)
            )
            .onAppear {
                phase = 1
            }
    }
}

extension View {
    func shimmer(_ isActive: Bool = true) -> some View {
        if isActive {
            return AnyView(modifier(ShimmerEffect()))
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - Ingredient Image Helpers
private func ingredientImageURL(for name: String) -> URL? {
    IngredientImageService.shared.url(for: name)
}

struct GroceryListView: View {
    @ObservedObject var dataManager: DataManager
    @State private var showingCreateList = false
    @State private var newListName = ""
    @State private var navigateToNewList: GroceryList?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if dataManager.groceryLists.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // List of Grocery Lists
                    List {
                        ForEach(dataManager.groceryLists) { list in
                            Button(action: {
                                navigateToNewList = list
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(list.name)
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundColor(.primary)
                                        
                                        Text("\(list.ingredients.filter { !$0.isChecked }.count) items remaining")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .onDelete(perform: deleteLists)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .overlay(
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingCreateList = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            )
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.large)
            .background()
            .sheet(isPresented: $showingCreateList) {
                CreateListView(dataManager: dataManager, isPresented: $showingCreateList, onListCreated: { newList in
                    navigateToNewList = newList
                })
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToNewList != nil },
                set: { if !$0 { navigateToNewList = nil } }
            )) {
                if let list = navigateToNewList {
                    GroceryListDetailView(dataManager: dataManager, list: list)
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

struct CreateListView: View {
    @ObservedObject var dataManager: DataManager
    @Binding var isPresented: Bool
    let onListCreated: (GroceryList) -> Void
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
                        let newList = dataManager.createNewList(name: listName)
                        onListCreated(newList)
                        isPresented = false
                    }
                }
                .disabled(listName.isEmpty)
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .background()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

struct RenameListView: View {
    @ObservedObject var dataManager: DataManager
    let list: GroceryList?
    @Binding var isPresented: Bool
    @State private var listName = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Rename")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("List Name", text: $listName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button("Rename") {
                    if !listName.isEmpty, let list = list {
                        dataManager.renameList(list, newName: listName)
                        isPresented = false
                    }
                }
                .disabled(listName.isEmpty)
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .background()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.blue)
                }
            }
            .onAppear {
                listName = list?.name ?? ""
            }
        }
    }
}

struct GroceryListDetailView: View {
    @ObservedObject var dataManager: DataManager
    let list: GroceryList
    @State private var showingRecipeInput = false
    @State private var showingRenameList = false
    @Environment(\.dismiss) private var dismiss
    private let imageService = IngredientImageService.shared
    
    // Get the current version of this list from the DataManager
    private var currentList: GroceryList? {
        let found = dataManager.groceryLists.first { $0.id == list.id }
        print("🔍 GroceryListDetailView: Looking for list '\(list.name)' (ID: \(list.id))")
        print("🔍 Found list: \(found?.name ?? "nil") with \(found?.ingredients.count ?? 0) ingredients")
        return found
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let currentList = currentList, currentList.ingredients.isEmpty {
                // Empty List State
                VStack(spacing: 20) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
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
                    
                    Button("Go Back") {
                        // This will be handled by navigation
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
            }
            
            // Bottom Bar
            HStack {
                if let currentList = currentList {
                    Text("\(currentList.ingredients.filter { !$0.isChecked }.count) items remaining")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingRecipeInput = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.separator)),
                alignment: .top
            )
        }
        .navigationTitle(currentList?.name ?? list.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Lists")
                            .font(.system(size: 17))
                    }
                    .foregroundColor(.blue)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        showingRenameList = true
                    }) {
                        HStack {
                            Text("Rename")
                            Spacer()
                            Image(systemName: "pencil")
                        }
                    }
                    
                    Button(role: .destructive, action: {
                        if let currentList = currentList {
                            dataManager.deleteList(currentList)
                            dismiss()
                        }
                    }) {
                        HStack {
                            Text("Delete")
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showingRecipeInput) {
            RecipeInputView(dataManager: dataManager, targetList: currentList)
        }
        .sheet(isPresented: $showingRenameList) {
            RenameListView(dataManager: dataManager, list: currentList, isPresented: $showingRenameList)
        }
    }
}

struct CategoryHeader: View {
    let category: GroceryCategory
    let ingredients: [Ingredient]
    
    private var remainingCount: Int {
        ingredients.filter { !$0.isChecked }.count
    }
    
    var body: some View {
        HStack {
            Text(category.displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(remainingCount) items remaining")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
                .shimmer(remainingCount == 0)
        }
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
        
        return "\(combinedAmount) \(finalUnit)"
    }
    
    private func spellOutUnit(_ unit: String) -> String {
        let lowercasedUnit = unit.lowercased()
        
        // If it's a non-measurable word, return empty string (just show the number)
        if nonMeasurableWords.contains(lowercasedUnit) {
            return ""
        }
        
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
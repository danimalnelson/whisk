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
        // Enforce a single default list named "Ingredients"
        if let current = currentList {
            return current
        }
        let newList = GroceryList(name: "Ingredients")
        groceryLists = [newList]
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
    
    func renameList(_ list: GroceryList, newName: String) {
        if let index = groceryLists.firstIndex(where: { $0.id == list.id }) {
            groceryLists[index].name = newName
            if currentList?.id == list.id {
                currentList = groceryLists[index]
            }
            saveData()
        } else {
            print("❌ Could not find list with ID: \(list.id) for renaming")
        }
    }
    
    // MARK: - Ingredients Management
    
    func addIngredientsToCurrentList(_ ingredients: [Ingredient]) {
        // Create a default list if none exists
        if currentList == nil {
            _ = createNewList(name: "Ingredients")
        }
        
        guard var list = currentList else { 
            print("❌ Failed to get current list after creation")
            return 
        }
        
        // Filter out water and other common household items
        let filteredIngredients = ingredients.filter { ingredient in
            let lowercasedName = ingredient.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let excludedItems = [
                "water", "tap water", "filtered water", "distilled water",
                "ice water", "cold water", "warm water", "hot water", "lukewarm water"
            ]
            if excludedItems.contains(lowercasedName) { return false }
            // Exclude generic water phrases or names that end with "water" with no leading flavor (e.g., "4 quarts water")
            if lowercasedName.range(of: #"^(?:ice|cold|warm|hot|lukewarm)?\s*water$"#, options: .regularExpression) != nil { return false }
            if lowercasedName.hasSuffix(" water") {
                // Allow flavored waters like "rose water" or "orange blossom water"
                let allowedFlavored = ["rose water", "orange blossom water", "floral water", "coconut water"]
                if !allowedFlavored.contains(lowercasedName) { return false }
            }
            return true
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
                    newUnit: newIngredient.unit,
                    ingredientName: newIngredient.name
                )
                
                list.ingredients[existingIndex].amount = consolidatedAmount.amount
                list.ingredients[existingIndex].unit = consolidatedAmount.unit
                
                print("🛒 Consolidated: \(newIngredient.name) (\(newIngredient.amount) \(newIngredient.unit), \(newIngredient.category)) + existing → \(consolidatedAmount.amount) \(consolidatedAmount.unit) [\(list.ingredients[existingIndex].category)]")
            } else {
                list.ingredients.append(newIngredient)
                print("🛒 Added new ingredient: \(newIngredient.name) — \(newIngredient.amount) \(newIngredient.unit) [\(newIngredient.category)]")
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
            let lowercasedName = ingredient.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let excludedItems = [
                "water", "tap water", "filtered water", "distilled water",
                "ice water", "cold water", "warm water", "hot water", "lukewarm water"
            ]
            if excludedItems.contains(lowercasedName) { return false }
            // Exclude generic water phrases or names that end with "water" with no leading flavor (e.g., "4 quarts water")
            if lowercasedName.range(of: #"^(?:ice|cold|warm|hot|lukewarm)?\s*water$"#, options: .regularExpression) != nil { return false }
            if lowercasedName.hasSuffix(" water") {
                let allowedFlavored = ["rose water", "orange blossom water", "floral water", "coconut water"]
                if !allowedFlavored.contains(lowercasedName) { return false }
            }
            return true
        }
        
        print("🛒 Filtered out \(ingredients.count - filteredIngredients.count) common household items")
        
        // Smart ingredient consolidation
        for newIngredient in filteredIngredients {
            print("🛒 Processing ingredient: \(newIngredient.name) - \(newIngredient.amount) \(newIngredient.unit) [\(newIngredient.category)]")
            
            if let existingIndex = findConsolidatableIngredient(newIngredient, in: updatedList.ingredients) {
                // Combine amounts with unit conversion if needed
                let consolidatedAmount = consolidateAmounts(
                    existing: updatedList.ingredients[existingIndex].amount,
                    existingUnit: updatedList.ingredients[existingIndex].unit,
                    new: newIngredient.amount,
                    newUnit: newIngredient.unit,
                    ingredientName: newIngredient.name
                )
                
                updatedList.ingredients[existingIndex].amount = consolidatedAmount.amount
                updatedList.ingredients[existingIndex].unit = consolidatedAmount.unit
                
                print("🛒 Consolidated: \(newIngredient.name) (\(newIngredient.amount) \(newIngredient.unit), \(newIngredient.category)) + existing → \(consolidatedAmount.amount) \(consolidatedAmount.unit) [\(updatedList.ingredients[existingIndex].category)]")
            } else {
                updatedList.ingredients.append(newIngredient)
                print("🛒 Added new ingredient: \(newIngredient.name) — \(newIngredient.amount) \(newIngredient.unit) [\(newIngredient.category)]")
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
        // Route to single-list toggle
        toggleIngredientChecked(ingredient)
    }
    
    func removeIngredient(_ ingredient: Ingredient) {
        guard var list = currentList,
              let index = list.ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        
        list.ingredients.remove(at: index)
        updateCurrentList(list)
    }
    
    func clearAllIngredients() {
        guard var list = currentList else { return }
        list.ingredients.removeAll()
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
        // Consolidation policy:
        // - Exact name match (case-insensitive)
        // - Same category
        // - Units are identical OR compatible (both volume, both weight) OR either is "To taste"
        // - Count-like units consolidate only when the unit text matches (e.g., cloves+cloves)

        let newName = newIngredient.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newUnit = newIngredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for (index, existing) in existingIngredients.enumerated() {
            let existingName = existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let existingUnit = existing.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Require same category first
            guard existing.category == newIngredient.category else { continue }
            // Names must match exactly OR be garlic-equivalent ("garlic" vs "garlic cloves")
            let namesEqual = (existingName == newName)
            let garlicEquivalent = isGarlicName(existingName) && isGarlicName(newName)
            if !namesEqual && !garlicEquivalent { continue }

            // Treat range-like and count-like mixtures as consolidatable (actual merge logic handled in consolidateAmounts)
            let isRangeLike: (String) -> Bool = { u in
                let t = u.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if t.hasPrefix("to ") { return true }
                if let rx = try? NSRegularExpression(pattern: "(?i)^([\\d\\.]+)\\s*[-–]\\s*([\\d\\.]+)(?:\\s+[a-z]+)?$") {
                    return rx.firstMatch(in: t, options: [], range: NSRange(t.startIndex..., in: t)) != nil
                }
                return false
            }
            let countLikeMix = (isCountUnit(existingUnit) || isRangeLike(existingUnit)) || (isCountUnit(newUnit) || isRangeLike(newUnit))
            if countLikeMix {
                print("🔎 Consolidation match (count/range): \(existing.name) [\(existingUnit)]  +  \(newIngredient.name) [\(newUnit)]")
                return index
            }

            // Unify zero-like items (e.g., "To taste" / "For serving")
            if isZeroLikeUnit(existingUnit) || isZeroLikeUnit(newUnit) {
                print("🔎 Consolidation match (zero-like): \(existing.name) [\(existingUnit)]  +  \(newIngredient.name) [\(newUnit)]")
                return index
            }

            // Same unit → consolidate
            if existingUnit == newUnit {
                print("🔎 Consolidation match (same unit): \(existing.name) [\(existingUnit)]  +  \(newIngredient.name) [\(newUnit)]")
                return index
            }

            // Both volume → consolidate with conversion
            if isVolumeUnit(existingUnit) && isVolumeUnit(newUnit) {
                print("🔎 Consolidation match (volume-volume): \(existing.name) [\(existingUnit)]  +  \(newIngredient.name) [\(newUnit)]")
                return index
            }

            // Both weight → consolidate with conversion
            if isWeightUnit(existingUnit) && isWeightUnit(newUnit) {
                print("🔎 Consolidation match (weight-weight): \(existing.name) [\(existingUnit)]  +  \(newIngredient.name) [\(newUnit)]")
                return index
            }

            // Count-like units only consolidate when the unit tokens match
            if isCountUnit(existingUnit) && isCountUnit(newUnit) && existingUnit == newUnit { return index }

            // Garlic special-case: allow count↔volume consolidation (cloves ↔ tsp/tbsp)
            let isGarlic = garlicEquivalent
            if isGarlic {
                let countVsVol = (isCountUnit(existingUnit) && isVolumeUnit(newUnit)) || (isVolumeUnit(existingUnit) && isCountUnit(newUnit))
                if countVsVol {
                    print("🔎 Consolidation match (garlic count↔volume): \(existing.name) [\(existingUnit)]  +  \(newIngredient.name) [\(newUnit)]")
                    return index
                }
            }
        }
        return nil
    }

    private func isGarlicName(_ s: String) -> Bool {
        let lc = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Match exactly "garlic" or "garlic clove(s)"
        return lc.range(of: #"^(?:garlic(?:\s+cloves?)?)$"#, options: .regularExpression) != nil
    }
    
    private func areSimilarIngredients(_ name1: String, _ name2: String) -> Bool {
        // Similarity-based consolidation is disabled under the strict policy.
        // Keep items separate unless they match exactly (name/category/unit/amount).
        return false
    }
    
    private func consolidateAmounts(existing: Double, existingUnit: String, new: Double, newUnit: String, ingredientName: String) -> (amount: Double, unit: String) {
        let u1 = existingUnit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let u2 = newUnit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Helper: parse range-like units (e.g., "to 15 cloves", "12-15") into [min,max] with base unit
        func parseRange(amount: Double, unit: String, fallbackBase: String) -> (min: Double, max: Double, base: String) {
            let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Pattern: "to X [base]"
            if let rx = try? NSRegularExpression(pattern: "(?i)^to\\s+([\\d\\.]+)(?:\\s+([a-z]+))?$"),
               let m = rx.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges >= 2 {
                let maxStr = (Range(m.range(at: 1), in: trimmed)).map { String(trimmed[$0]) } ?? "0"
                let maxVal = Double(maxStr) ?? amount
                let base = (Range(m.range(at: 2), in: trimmed)).map { String(trimmed[$0]) } ?? fallbackBase
                return (min: amount, max: maxVal, base: base.isEmpty ? fallbackBase : base)
            }
            // Pattern: "min-max" (legacy)
            if let rx = try? NSRegularExpression(pattern: "(?i)^([\\d\\.]+)\\s*[-–]\\s*([\\d\\.]+)$"),
               let m = rx.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges >= 3 {
                let minStr = (Range(m.range(at: 1), in: trimmed)).map { String(trimmed[$0]) } ?? String(amount)
                let maxStr = (Range(m.range(at: 2), in: trimmed)).map { String(trimmed[$0]) } ?? minStr
                let minVal = Double(minStr) ?? amount
                let maxVal = Double(maxStr) ?? minVal
                return (min: minVal, max: maxVal, base: fallbackBase)
            }
            return (min: amount, max: amount, base: fallbackBase)
        }

        // Zero-like units (e.g., "To taste" / "For serving"): treat as amount 0.
        let u1Zero = isZeroLikeUnit(u1)
        let u2Zero = isZeroLikeUnit(u2)
        if u1Zero && u2Zero {
            // Both are zero-like → keep as zero-like, prefer existing label
            return (0.0, existingUnit.isEmpty ? newUnit : existingUnit)
        } else if u1Zero && !u2Zero {
            // Existing is zero-like, new is measured → adopt measured
            return (new, newUnit)
        } else if !u1Zero && u2Zero {
            // Existing is measured, new is zero-like → keep measured
            return (existing, existingUnit)
        }

        // Count-like consolidation with range support (sums ranges element-wise)
        do {
            // Determine if this is a count-like scenario
            let base1: String = isCountUnit(u1) ? u1 : (u1.hasPrefix("to ") ? "pieces" : u1)
            let base2: String = isCountUnit(u2) ? u2 : (u2.hasPrefix("to ") ? "pieces" : u2)
            // Normalize garlic base to cloves
            let isGarlic = ingredientName.lowercased().contains("garlic")
            let normalizedBase1 = isGarlic ? (base1.isEmpty || base1 == "pieces" ? "cloves" : base1) : base1
            let normalizedBase2 = isGarlic ? (base2.isEmpty || base2 == "pieces" ? "cloves" : base2) : base2

            let countLike1 = isCountUnit(normalizedBase1) || u1.hasPrefix("to ")
            let countLike2 = isCountUnit(normalizedBase2) || u2.hasPrefix("to ")
            if countLike1 && countLike2 {
                var r1 = parseRange(amount: existing, unit: u1, fallbackBase: normalizedBase1.isEmpty ? "pieces" : normalizedBase1)
                var r2 = parseRange(amount: new, unit: u2, fallbackBase: normalizedBase2.isEmpty ? "pieces" : normalizedBase2)
                // If garlic and one side is volume, convert to cloves (heuristic: 1 clove ≈ 1 tsp; 1 tbsp = 3 tsp)
                let volToCloves: (Double, String) -> Double? = { amt, unit in
                    switch unit {
                    case "teaspoon", "teaspoons", "tsp": return amt
                    case "tablespoon", "tablespoons", "tbsp": return amt * 3.0
                    default: return nil
                    }
                }
                if isGarlic {
                    if isVolumeUnit(u1), let cloves = volToCloves(existing, u1) {
                        r1 = (min: cloves, max: cloves, base: "cloves")
                    }
                    if isVolumeUnit(u2), let cloves = volToCloves(new, u2) {
                        r2 = (min: cloves, max: cloves, base: "cloves")
                    }
                }
                // Require same base or allow empty → pick non-empty
                let base = r1.base.isEmpty ? r2.base : (r2.base.isEmpty ? r1.base : r1.base)
                let sumMin = r1.min + r2.min
                let sumMax = r1.max + r2.max
                if abs(sumMin - sumMax) < 1e-6 {
                    return (sumMin, base)
                } else {
                    // Represent as "min to max [base]" (omit base when not helpful)
                    let unitText = base.isEmpty ? String(format: "to %.0f", sumMax) : String(format: "to %.0f %@", sumMax, base)
                    return (sumMin, unitText)
                }
            }
        }

        // Same unit → simple addition
        if u1 == u2 { return (existing + new, existingUnit) }

        // Garlic special-case: merge cloves and tsp using a heuristic mapping.
        if ingredientName.lowercased().contains("garlic") {
            let clovesPerTeaspoon = 1.0 // heuristic: 1 medium clove ≈ 1 tsp grated
            // u1 is existing unit; u2 is new unit. Convert both to teaspoons if possible, then sum.
            var totalTeaspoons: Double = 0
            var couldMapAll = true
            let mapToTeaspoons: (Double, String) -> Double? = { amt, unit in
                switch unit {
                case "teaspoon", "teaspoons", "tsp": return amt
                case "tablespoon", "tablespoons", "tbsp": return amt * 3.0
                case "clove", "cloves": return amt * clovesPerTeaspoon
                default: return nil
                }
            }
            if let t1 = mapToTeaspoons(existing, u1) { totalTeaspoons += t1 } else { couldMapAll = false }
            if let t2 = mapToTeaspoons(new, u2) { totalTeaspoons += t2 } else { couldMapAll = false }
            if couldMapAll {
                // Prefer teaspoons; promote to tbsp when divisible by 3
                if abs(round(totalTeaspoons) - totalTeaspoons) < 1e-6, Int(round(totalTeaspoons)) % 3 == 0 {
                    return (Double(Int(round(totalTeaspoons)) / 3), "tablespoons")
                } else {
                    return (totalTeaspoons, "teaspoons")
                }
            }
        }

        // Volume consolidation
        if isVolumeUnit(u1) && isVolumeUnit(u2) {
            let m1 = convertToMilliliters(amount: existing, unit: u1)
            let m2 = convertToMilliliters(amount: new, unit: u2)
            if m1 > 0 && m2 > 0 {
                return convertFromMilliliters(ml: m1 + m2, preferredUnit: existingUnit)
            }
        }

        // Weight consolidation (grams)
        if isWeightUnit(u1) && isWeightUnit(u2) {
            let g1 = convertToGrams(amount: existing, unit: u1)
            let g2 = convertToGrams(amount: new, unit: u2)
            if g1 > 0 && g2 > 0 {
                return convertFromGrams(grams: g1 + g2, preferredUnit: existingUnit)
            }
        }

        // Count-like units: only consolidate when units match (handled by early return). Otherwise, keep separate.
        // If we somehow reach here, fall back to keeping existing unit and amount, adding new amount only when units match (already handled).
        return (existing, existingUnit)
    }

    // MARK: - Unit Kind Helpers
    private func isZeroLikeUnit(_ unit: String) -> Bool {
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Treat empty unit as zero-like to allow consolidation with measured entries
        return u.isEmpty || u == "to taste" || u == "for serving"
    }

    private func isVolumeUnit(_ unit: String) -> Bool {
        let u = unit.lowercased()
        let volumeUnits: Set<String> = [
            "teaspoon", "teaspoons", "tsp",
            "tablespoon", "tablespoons", "tbsp",
            "cup", "cups",
            "pint", "pints",
            "quart", "quarts",
            "gallon", "gallons",
            "milliliter", "milliliters", "ml",
            "liter", "liters", "l"
        ]
        return volumeUnits.contains(u)
    }

    private func isWeightUnit(_ unit: String) -> Bool {
        let u = unit.lowercased()
        let weightUnits: Set<String> = [
            "ounce", "ounces", "oz",
            "pound", "pounds", "lb", "lbs",
            "gram", "grams", "g",
            "kilogram", "kilograms", "kg"
        ]
        return weightUnits.contains(u)
    }

    private func isCountUnit(_ unit: String) -> Bool {
        let u = unit.lowercased()
        let countUnits: Set<String> = [
            "piece", "pieces",
            "clove", "cloves",
            "sprig", "sprigs",
            "leaf", "leaves",
            "head", "heads",
            "bunch", "bunches",
            "small", "medium", "large",
            "serving", "servings"
        ]
        return countUnits.contains(u)
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

    private func convertToMilliliters(amount: Double, unit: String) -> Double {
        let u = unit.lowercased()
        switch u {
        case "teaspoon", "teaspoons", "tsp":
            return amount * 4.92892
        case "tablespoon", "tablespoons", "tbsp":
            return amount * 14.7868
        case "cup", "cups":
            return amount * 236.588
        case "pint", "pints":
            return amount * 473.176
        case "quart", "quarts":
            return amount * 946.353
        case "gallon", "gallons":
            return amount * 3785.41
        case "milliliter", "milliliters", "ml":
            return amount
        case "liter", "liters", "l":
            return amount * 1000
        default:
            return 0
        }
    }

    private func convertFromMilliliters(ml: Double, preferredUnit: String) -> (amount: Double, unit: String) {
        let u = preferredUnit.lowercased()
        switch u {
        case "teaspoon", "teaspoons", "tsp":
            return (ml / 4.92892, "teaspoons")
        case "tablespoon", "tablespoons", "tbsp":
            return (ml / 14.7868, "tablespoons")
        case "cup", "cups":
            return (ml / 236.588, "cups")
        case "pint", "pints":
            return (ml / 473.176, "pints")
        case "quart", "quarts":
            return (ml / 946.353, "quarts")
        case "gallon", "gallons":
            return (ml / 3785.41, "gallons")
        case "milliliter", "milliliters", "ml":
            return (ml, "milliliters")
        case "liter", "liters", "l":
            return (ml / 1000, "liters")
        default:
            // Default to tablespoons for reasonable display if preferred is unknown volume
            return (ml / 14.7868, "tablespoons")
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
                        _ = createNewList(name: "Ingredients")
                    } else {
                        currentList = groceryLists.first
                        print("📱 Using first list as current: \(currentList?.name ?? "nil")")
                    }
                }
            } catch {
                print("❌ Error loading current list: \(error)")
                if groceryLists.isEmpty {
                    print("📱 Creating default list after error")
                    _ = createNewList(name: "Ingredients")
                } else {
                    currentList = groceryLists.first
                }
            }
        } else {
            print("📱 No saved current list found")
            if groceryLists.isEmpty {
                print("📱 Creating default list")
                _ = createNewList(name: "Ingredients")
            } else {
                currentList = groceryLists.first
                print("📱 Using first list as current: \(currentList?.name ?? "nil")")
            }
        }
        
        print("📱 Data loading complete. Current list: \(currentList?.name ?? "nil") with \(currentList?.ingredients.count ?? 0) ingredients")
    }
} 
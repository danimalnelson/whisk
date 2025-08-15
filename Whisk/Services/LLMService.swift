import Foundation

class LLMService: ObservableObject {
    private let baseURL = "https://whisk-server-git-new-recipe-adder-dannelson.vercel.app/api/call-openai"
    // Basic allow/deny lists to quickly gate obvious non-recipe domains
    private let recipeDomainAllowList: Set<String> = [
        "allrecipes.com", "bonappetit.com", "seriouseats.com", "foodnetwork.com",
        "epicurious.com", "foodandwine.com", "thekitchn.com", "bbcgoodfood.com",
        "cooking.nytimes.com", "simplyrecipes.com", "smittenkitchen.com",
        "delish.com", "loveandlemons.com", "taste.com.au", "nytimes.com"
    ]
    private let nonRecipeDomainDenyList: Set<String> = [
        "espn.com", "cnn.com", "bbc.com", "bloomberg.com",
        "wsj.com", "foxnews.com", "theverge.com", "techcrunch.com"
    ]
    
    // 🚀 NEW: Simple in-memory cache for parsed recipes
    private var recipeCache: [String: RecipeParsingResult] = [:]
    private let cacheQueue = DispatchQueue(label: "recipeCache", attributes: .concurrent)
    
    // 🚀 NEW: Performance tracking
    private var performanceStats = PerformanceStats()
    
    init() {
    }

    enum LLMServiceError: Error {
        case invalidURL
        case invalidResponse
        case apiError
        case parsingError
    }
    
    // 🚀 NEW: Performance statistics
    struct PerformanceStats {
        var cacheHits: Int = 0
        var structuredDataSuccess: Int = 0
        var regexSuccess: Int = 0
        var llmSuccess: Int = 0
        var totalRequests: Int = 0
        
        var cacheHitRate: Double {
            return totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0
        }
        
        var structuredDataRate: Double {
            return totalRequests > 0 ? Double(structuredDataSuccess) / Double(totalRequests) : 0
        }
        
        var regexRate: Double {
            return totalRequests > 0 ? Double(regexSuccess) / Double(totalRequests) : 0
        }
        
        var llmRate: Double {
            return totalRequests > 0 ? Double(llmSuccess) / Double(totalRequests) : 0
        }
        
        mutating func recordCacheHit() {
            cacheHits += 1
            totalRequests += 1
        }
        
        mutating func recordStructuredDataSuccess() {
            structuredDataSuccess += 1
            totalRequests += 1
        }
        
        mutating func recordRegexSuccess() {
            regexSuccess += 1
            totalRequests += 1
        }
        
        mutating func recordLLMSuccess() {
            llmSuccess += 1
            totalRequests += 1
        }
        
        func printStats() {
            print("📊 Performance Stats:")
            print("   Total requests: \(totalRequests)")
            print("   Cache hit rate: \(String(format: "%.1f", cacheHitRate * 100))%")
            print("   Structured data success: \(String(format: "%.1f", structuredDataRate * 100))%")
            print("   Regex parsing success: \(String(format: "%.1f", regexRate * 100))%")
            print("   LLM fallback: \(String(format: "%.1f", llmRate * 100))%")
        }
    }
    
    // MARK: - Unit mappings for normalization
    private let unitMappings: [String: String] = [
        // Volume
        "t": "teaspoon", "ts": "teaspoon", "tsp": "teaspoon", "teaspoon": "teaspoons", "teaspoons": "teaspoons",
        "tb": "tablespoon", "tbsp": "tablespoon", "tbs": "tablespoon", "tablespoon": "tablespoons", "tablespoons": "tablespoons",
        "c": "cup", "cup": "cups", "cups": "cups",
        "pt": "pint", "pint": "pints", "pints": "pints",
        "qt": "quart", "quart": "quarts", "quarts": "quarts",
        "gal": "gallon", "gallon": "gallons", "gallons": "gallons",
        "ml": "milliliters", "milliliter": "milliliters", "milliliters": "milliliters",
        "l": "liters", "liter": "liters", "liters": "liters",
        
        // Weight
        "oz": "ounces", "ounce": "ounces", "ounces": "ounces",
        "lb": "pounds", "lbs": "pounds", "pound": "pounds", "pounds": "pounds",
        "g": "grams", "gram": "grams", "grams": "grams",
        "kg": "kilograms", "kilogram": "kilograms", "kilograms": "kilograms",
        
        // Count-like
        "clove": "cloves", "cloves": "cloves",
        "slice": "slices", "slices": "slices",
        "can": "cans", "cans": "cans",
        "jar": "jars", "jars": "jars",
        "bottle": "bottles", "bottles": "bottles",
        "package": "packages", "packages": "packages",
        "bag": "bags", "bags": "bags",
        "bunch": "bunches", "bunches": "bunches",
        "head": "heads", "heads": "heads",
        "piece": "pieces", "pieces": "pieces",
        "leaf": "leaves", "leaves": "leaves",
        "sprig": "sprigs", "sprigs": "sprigs"
    ]

    // MARK: - Category keyword hints (broad heuristics; overrides take precedence)
    private let categoryKeywords: [GroceryCategory: [String]] = [
        .produce: ["apple", "banana", "lemon", "lime", "orange", "grapefruit", "lettuce", "onion", "garlic", "tomato", "pepper", "cucumber", "spinach", "kale", "zest", "juice", "parsley", "mint", "chives", "basil", "cilantro"],
        .meatAndSeafood: ["beef", "pork", "chicken", "shrimp", "salmon", "tuna", "squid", "crab"],
        .deli: ["ham", "salami", "prosciutto", "nduja", "'nduja"],
        .bakery: ["bread", "baguette", "bun"],
        .frozen: ["frozen"],
        .pantry: ["flour", "sugar", "salt", "pepper", "oil", "vinegar", "rice", "pasta", "noodles", "stock", "broth", "spice", "spices"],
        .dairy: ["milk", "butter", "cream", "cheese", "yogurt"],
        .beverages: ["wine", "beer", "soda", "cocktail"]
    ]
    
    @MainActor
    func parseRecipe(from url: String) async throws -> RecipeParsingResult {
        print("⏱️ === Recipe Parsing Start ===")
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        
        // 🚀 NEW: Check cache first
        if let cachedResult = getCachedResult(for: url) {
            print("✅ Found cached result for \(url)")
            performanceStats.recordCacheHit()
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
            print("⏱️ Total time (cached): \(String(format: "%.2f", totalTime))s")
            print("⏱️ === Recipe Parsing End ===")
            performanceStats.printStats()
            return cachedResult
        }
        
        // Fetch and process webpage
        let webpageContent = try await fetchWebpageContent(from: url)

        // 🛡️ Gate: skip non-recipe pages early
        if !isLikelyRecipePage(urlString: url, html: webpageContent) {
            print("🚫 Skipping non-recipe URL: \(url)")
            let result = RecipeParsingResult(recipe: Recipe(url: url), success: false, error: "This URL doesn't look like a recipe page.")
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
            print("⏱️ Total time (non-recipe): \(String(format: "%.2f", totalTime))s")
            print("⏱️ === Recipe Parsing End ===")
            performanceStats.printStats()
            return result
        }
        
        // 🚀 NEW: Try structured data extraction first (fastest path)
        if let structuredData = extractStructuredData(from: webpageContent),
           let recipeFromStructured = parseStructuredData(structuredData, originalURL: url) {
            print("✅ Successfully parsed from structured data - skipping LLM call!")
            performanceStats.recordStructuredDataSuccess()
            let result = RecipeParsingResult(recipe: recipeFromStructured, success: true, error: nil)
            
            // Cache the result
            cacheResult(result, for: url)
            
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
            print("⏱️ Total time (structured data): \(String(format: "%.2f", totalTime))s")
            print("⏱️ === Recipe Parsing End ===")
            performanceStats.printStats()
            return result
        }
        
        // Extract ingredient section and try deterministic parsing paths first
        var ingredientSection = extractIngredientSection(from: webpageContent)

        // HTML list extraction: prefer <li> items near an Ingredients marker when available
        do {
            let html = webpageContent
            let listPatterns = [#"<ul[^>]*>([\s\S]*?)</ul>"#, #"<ol[^>]*>([\s\S]*?)</ol>"#]
            var bestItems: [String] = []
            for pattern in listPatterns {
                if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let matches = rx.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                    for m in matches {
                        guard m.numberOfRanges >= 2, let inner = Range(m.range(at: 1), in: html) else { continue }
                        // proximity check
                        let fullRange = m.range(at: 0)
                        var isNearIngredients = false
                        if let fr = Range(fullRange, in: html) {
                            let preEnd = fr.lowerBound
                            let preStart = html.index(preEnd, offsetBy: -1500, limitedBy: html.startIndex) ?? html.startIndex
                            let pre = html[preStart..<preEnd].lowercased()
                            if pre.contains("ingredients") || pre.contains("ingredient") { isNearIngredients = true }
                        }
                        // extract <li>
                        let listContent = String(html[inner])
                        if let liRx = try? NSRegularExpression(pattern: #"<li[^>]*>([\s\S]*?)</li>"#, options: [.caseInsensitive]) {
                            let liMatches = liRx.matches(in: listContent, options: [], range: NSRange(listContent.startIndex..., in: listContent))
                            var items: [String] = []
                            for lm in liMatches {
                                if lm.numberOfRanges >= 2, let lr = Range(lm.range(at: 1), in: listContent) {
                                    let item = String(listContent[lr])
                                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    if item.isEmpty { continue }
                                    items.append(item)
                                }
                            }
                            if !items.isEmpty {
                                // require most items have measurement or count for acceptance
                                var withMeasureOrCount = 0
                                let countRx = try? NSRegularExpression(pattern: "(?i)^(?:one|two|three|four|five|six|seven|eight|nine|ten|a|an|\\d|[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])")
                                for i in items {
                                    let hasCount = (countRx?.firstMatch(in: i, options: [], range: NSRange(i.startIndex..., in: i)) != nil)
                                    if hasMeasurementPattern(i) || hasCount { withMeasureOrCount += 1 }
                                }
                                // Accept lists near an Ingredients heading.
                                // For small lists (<= 3 items), require that ALL items look like ingredients.
                                // For larger lists, require that at least half (and at least 3) look like ingredients.
                                let acceptSmallList = items.count <= 3 && withMeasureOrCount >= items.count
                                let acceptLargeList = withMeasureOrCount >= max(3, Int(Double(items.count) * 0.5))
                                let accept = isNearIngredients && (acceptSmallList || acceptLargeList)
                                if accept && items.count > bestItems.count { bestItems = items }
                            }
                        }
                    }
                }
            }
            if !bestItems.isEmpty {
                ingredientSection = bestItems.joined(separator: "\n")
                print("📋 Using HTML list ingredients (\(bestItems.count) items)")
            }
        }

        // 🚀 QUICK PATH: Parse each line individually (robust against formatting) before regex/LLM
        let quickLines = ingredientSection
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                // HTML/DOM tokens should never be considered ingredients
                if lower.range(of: #"[<>]"#, options: .regularExpression) != nil { return false }
                if lower.range(of: #"</?\w+[\s>]|href=|src=|<script|</script|<style|</style|<!doctype|<meta|<link"#, options: .regularExpression) != nil { return false }
                if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") { return false }
                // Avoid CSS/JS/noise lines for quick parsing
                let cssJsNoise = ["display:", "position:", "width:", "height:", "margin:", "padding:", "background:", "color:", "font:", "@media", "function", "var(", "document.", "window.", "onetrust", "data-"]
                if cssJsNoise.contains(where: { lower.contains($0) }) { return false }
                // Exclude obvious instruction/direction lines
                let instructionTokens = [
                    "add ", "cook ", "stir ", "simmer", "boil", "bake", "roast", "grill", "melt ", "transfer ", "return ", "set aside",
                    "until ", "over medium", "over high", "over low", "; cook", "; stir"
                ]
                if instructionTokens.contains(where: { lower.contains($0) }) { return false }
                // Exclude timing lines like "about 12 minutes" or "2 minutes"
                if lower.range(of: #"\b(?:about\s+)?\d+\s+(minutes?|seconds?)\b"#, options: .regularExpression) != nil { return false }
                // Require measurement or count or strong ingredient heuristic
                return hasMeasurementPattern(line) || isLikelyIngredientLine(line)
            }
        var quickIngredients: [Ingredient] = []
        for line in quickLines {
            if let ing = parseIngredientFromString(line) {
                quickIngredients.append(ing)
            }
        }
        // Keep track of a deterministic fallback set if LLM fails
        var lastDeterministicIngredients: [Ingredient] = quickIngredients
        // Only skip LLM on quick path when we clearly have full coverage
        let quickMultiSection = ingredientSection.range(of: #"(?i)\bfor\s+the\b"#, options: .regularExpression) != nil
        // Require more coverage before skipping augmentation; use 12 as threshold even for smaller lists
        let quickMinToSkip = quickMultiSection ? 12 : 12
        if quickIngredients.count >= quickMinToSkip {
            print("✅ Successfully parsed \(quickIngredients.count) ingredients via quick line parser - skipping LLM call!")
            performanceStats.recordRegexSuccess()
            var recipe = Recipe(url: url)
            recipe.ingredients = sanitizeIngredientList(quickIngredients)
            recipe.isParsed = true
            recipe.name = extractRecipeTitle(from: webpageContent)
            let result = RecipeParsingResult(recipe: recipe, success: true, error: nil)
            cacheResult(result, for: url)
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
            print("⏱️ Total time (quick parsing): \(String(format: "%.2f", totalTime))s")
            print("⏱️ === Recipe Parsing End ===")
            performanceStats.printStats()
            return result
        }

        // Short-list optimization: for small ingredient sets, prefer quick path and augment with regex coverage
        if quickIngredients.count > 0 && quickIngredients.count <= 12 {
            print("✅ Small recipe (\(quickIngredients.count) items) via quick parser - skipping LLM call!")
            var merged = quickIngredients
            if let regexAugment = await parseIngredientsWithRegex(ingredientSection) {
                // Merge conservatively: prefer quick items; skip regex items whose base name matches an existing quick item
                let normalize: (String) -> String = { s in
                    var out = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    // Canonicalize common variants
                    out = out.replacingOccurrences(of: #"(?i)\bgarlic\s+cloves?\b"#, with: "garlic", options: .regularExpression)
                    return out
                }
                let existingNames = Set(merged.map { normalize($0.name) })
                let existingKeys = Set(merged.map { "\($0.name.lowercased())|\($0.unit.lowercased())|\(String(format: "%.4f", $0.amount))" })
                for ing in regexAugment {
                    if existingNames.contains(normalize(ing.name)) { continue }
                    let key = "\(ing.name.lowercased())|\(ing.unit.lowercased())|\(String(format: "%.4f", ing.amount))"
                    if !existingKeys.contains(key) { merged.append(ing) }
                }
            }
            performanceStats.recordRegexSuccess()
            var recipe = Recipe(url: url)
            recipe.ingredients = sanitizeIngredientList(merged)
            recipe.isParsed = true
            recipe.name = extractRecipeTitle(from: webpageContent)
            let result = RecipeParsingResult(recipe: recipe, success: true, error: nil)
            cacheResult(result, for: url)
            let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
            print("⏱️ Total time (quick small): \(String(format: "%.2f", totalTime))s")
            print("⏱️ === Recipe Parsing End ===")
            performanceStats.printStats()
            return result
        }

        // 🚀 NEW: Try regex-based parsing as deterministic fallback (fast, no LLM cost)
        if let regexParsedIngredients = await parseIngredientsWithRegex(ingredientSection) {
            // Only skip LLM when we clearly have full coverage and most items have measurements
            let minCountToSkip = 12
            let measuredCount = regexParsedIngredients.filter { !$0.unit.isEmpty || $0.amount > 0 }.count
            let measuredCoverageOK = measuredCount >= max(3, Int(Double(regexParsedIngredients.count) * 0.5))
            if regexParsedIngredients.count >= minCountToSkip && measuredCoverageOK {
                print("✅ Successfully parsed \(regexParsedIngredients.count) ingredients with regex - skipping LLM call!")
                performanceStats.recordRegexSuccess()
                var recipe = Recipe(url: url)
                recipe.ingredients = sanitizeIngredientList(regexParsedIngredients)
                recipe.isParsed = true
                // Extract recipe title
                recipe.name = extractRecipeTitle(from: webpageContent)
                let result = RecipeParsingResult(recipe: recipe, success: true, error: nil)
                // Cache the result
                cacheResult(result, for: url)
                let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
                print("⏱️ Total time (regex parsing): \(String(format: "%.2f", totalTime))s")
                print("⏱️ === Recipe Parsing End ===")
                performanceStats.printStats()
                return result
            } else {
                print("⚠️ Regex parsed only \(regexParsedIngredients.count) ingredients (measured: \(measuredCount)); falling back to LLM for completeness")
                // Update deterministic fallback
                if !regexParsedIngredients.isEmpty { lastDeterministicIngredients = regexParsedIngredients }
            }
        }
        
        // 🚀 NEW: Estimate token usage and truncate if needed
        let estimatedTokens = estimateTokenCount(ingredientSection)
        // Lower token target to reduce server processing time
        let maxTokens = 1600
        let truncatedContent = estimatedTokens > maxTokens ? truncateContent(ingredientSection, targetTokens: maxTokens) : ingredientSection
        
        let prompt = createRecipeParsingPrompt(ingredientContent: truncatedContent)
        
        // Call LLM
        let llmStartTime = CFAbsoluteTimeGetCurrent()
        let response: String
        do {
            response = try await callLLM(prompt: prompt)
        } catch {
            // Graceful fallback to deterministic results if LLM aborts or times out
            if !lastDeterministicIngredients.isEmpty {
                print("❌ LLM call failed (\(error.localizedDescription)); returning deterministic parsed ingredients instead")
                var recipe = Recipe(url: url)
                recipe.ingredients = sanitizeIngredientList(lastDeterministicIngredients)
                recipe.isParsed = true
                recipe.name = extractRecipeTitle(from: webpageContent)
                let result = RecipeParsingResult(recipe: recipe, success: true, error: nil)
                cacheResult(result, for: url)
                let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
                print("⏱️ Total time (fallback deterministic): \(String(format: "%.2f", totalTime))s")
                print("⏱️ === Recipe Parsing End ===")
                performanceStats.printStats()
                return result
            } else {
                throw error
            }
        }
        let llmTime = CFAbsoluteTimeGetCurrent() - llmStartTime
        print("⏱️ LLM processing: \(String(format: "%.2f", llmTime))s")
        
        // Parse response
        let result = parseLLMResponse(response, originalURL: url, originalContent: webpageContent)
        
        // Cache the result (even if it failed, to avoid repeated failures)
        cacheResult(result, for: url)
        
        // Record LLM success if parsing succeeded
        if result.success {
            performanceStats.recordLLMSuccess()
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - totalStartTime
        print("⏱️ Total time: \(String(format: "%.2f", totalTime))s")
        print("⏱️ === Recipe Parsing End ===")
        performanceStats.printStats()
        
        return result
    }

    // Lightweight URL validation to determine if a page is likely a recipe before parsing
    func validateIsLikelyRecipe(url: String) async -> Bool {
        do {
            let html = try await fetchWebpageContent(from: url)
            return isLikelyRecipePage(urlString: url, html: html)
        } catch {
            return false
        }
    }
    
    // 🚀 NEW: Cache management methods
    func getCachedResult(for url: String) -> RecipeParsingResult? {
        return cacheQueue.sync {
            return recipeCache[url]
        }
    }
    
    func cacheResult(_ result: RecipeParsingResult, for url: String) {
        cacheQueue.async(flags: .barrier) {
            self.recipeCache[url] = result
            
            // Keep cache size manageable (max 50 entries)
            if self.recipeCache.count > 50 {
                // Remove oldest entries (simple FIFO)
                let keysToRemove = Array(self.recipeCache.keys.prefix(10))
                for key in keysToRemove {
                    self.recipeCache.removeValue(forKey: key)
                }
            }
        }
    }
    
    // 🚀 NEW: Clear cache method (useful for testing)
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.recipeCache.removeAll()
        }
    }
    
    // 🚀 NEW: Get performance stats for debugging
    func getPerformanceStats() -> PerformanceStats {
        return performanceStats
    }
    
    // 🚀 NEW: Reset performance stats
    func resetPerformanceStats() {
        performanceStats = PerformanceStats()
    }
    
    // 🚀 NEW: Parse structured data (JSON-LD) from HTML
    @MainActor
    func parseStructuredData(_ jsonString: String, originalURL: String) -> Recipe? {
        print("🔍 Parsing structured data...")
        
        do {
            guard let jsonData = jsonString.data(using: .utf8) else {
                print("❌ Failed to convert JSON string to data")
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let json = json else {
                print("❌ Failed to parse JSON")
                return nil
            }
            
            // Handle both single recipe and array of recipes
            var recipeData: [String: Any]?
            if let recipes = json["@graph"] as? [[String: Any]] {
                // Find the recipe object in the graph
                recipeData = recipes.first { recipe in
                    recipe["@type"] as? String == "Recipe"
                }
            } else if json["@type"] as? String == "Recipe" {
                recipeData = json
            }
            
            guard let recipeData = recipeData else {
                print("❌ No recipe data found in structured data")
                return nil
            }
            
            var recipe = Recipe(url: originalURL)
            
            // Extract recipe name
            if let name = recipeData["name"] as? String {
                recipe.name = name
                print("📝 Recipe name: \(name)")
            }
            
            // Extract ingredients
            var ingredients: [Ingredient] = []
            
            // Try different ingredient field names
            let ingredientFields = ["recipeIngredient", "ingredients", "ingredient"]
            var ingredientList: [String] = []
            
            for field in ingredientFields {
                if let fieldData = recipeData[field] {
                    if let stringList = fieldData as? [String] {
                        ingredientList = stringList
                        break
                    } else if let dictList = fieldData as? [[String: Any]] {
                        // Handle structured ingredient objects
                        for ingredientDict in dictList {
                            if let name = ingredientDict["name"] as? String {
                                ingredientList.append(name)
                            }
                        }
                        break
                    }
                }
            }
            
            print("📋 Found \(ingredientList.count) ingredients in structured data")
            
            // Parse each ingredient string
            for ingredientString in ingredientList {
                if let ingredient = parseIngredientFromString(ingredientString) {
                    ingredients.append(ingredient)
                }
            }
            
            if ingredients.count >= 3 {
                recipe.ingredients = ingredients
                recipe.isParsed = true
                print("✅ Successfully parsed \(ingredients.count) ingredients from structured data")
                return recipe
            } else {
                print("❌ Not enough ingredients parsed from structured data (\(ingredients.count))")
                return nil
            }
            
        } catch {
            print("❌ Error parsing structured data: \(error)")
            return nil
        }
    }
    
    // 🚀 NEW: Regex-based ingredient parsing (fast fallback)
    @MainActor
    func parseIngredientsWithRegex(_ content: String) -> [Ingredient]? {
        print("🔍 Attempting regex-based ingredient parsing...")
        
        let lines = content.components(separatedBy: .newlines)
        var ingredients: [Ingredient] = []
        
        // Pattern A: measurement-based (amount + optional parenthetical size + unit + name). Includes containers and size units.
        // Use a non-capturing group for the parenthetical so capture indices remain stable.
        let ingredientPattern = #"(?i)^\s*(\d+[\d\/\s\.]*)\s*(?:\([^)]*\)\s*)?(cups?|tablespoons?|tbsp|teaspoons?|tsp|ounces?|oz|pounds?|lb|lbs|grams?|g(?![a-z])|kg|milliliters?|ml|liters?|l(?![a-z])|pint|pints|quart|quarts|gallon|gallons|small|medium|large|extra\s*large|xl|cloves?|sprigs?|bunches?|heads?|leaves?|pieces?|cans?|jars?|bottles?|containers?|packages?|bags?)\s+([^,\.]+?)(?:\s*,\s*[^,]*)?$"#
        // Pattern B: count-based (amount + name without explicit unit): e.g., "8 scallions", "3 star anise", "1 cinnamon stick"
        let countPattern = #"(?i)^(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|a|an|\d+[\d\/\s\.]*)\s+([^,\.]+?)(?:\s*\([^)]*\))?(?:\s*,\s*[^,]*)?$"#
        
        guard let regex = try? NSRegularExpression(pattern: ingredientPattern, options: [.caseInsensitive]),
              let countRegex = try? NSRegularExpression(pattern: countPattern, options: [.caseInsensitive]) else {
            print("❌ Failed to create regex pattern")
            return nil
        }
        
        // Keywords that indicate this is NOT an ingredient (true instructions/context only)
        // Descriptor words like "chopped", "drained", "halved", etc. are handled by cleaning, not filtered here.
        let nonIngredientKeywords = [
            "minute", "minutes", "second", "seconds", "hour", "hours",
            "cook", "cooking", "heat", "heated", "simmer", "boil", "fry", "bake", "roast", "grill",
            "stir", "mix", "blend", "whisk",
            "until", "until just", "until lightly", "until golden", "until tender", "until cooked",
            "over medium", "over high", "over low", "in a", "in the", "on a", "on the",
            "carefully", "gently", "slowly", "quickly", "immediately", "transfer", "serve",
            // treat pure adverb-only fragments as non-ingredients
            "very thinly", "thinly", "finely", "roughly", "coarsely"
        ]
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Normalize unicode vulgar fractions to ASCII (e.g., ½ → 1/2) so regex can match amounts
            let normalizedLine: String = {
                var s = trimmedLine
                if let rx = try? NSRegularExpression(pattern: "(?i)([0-9])([¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])") {
                    s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1 $2")
                }
                let map: [Character: String] = [
                    "¼": "1/4", "½": "1/2", "¾": "3/4",
                    "⅐": "1/7", "⅑": "1/9", "⅒": "1/10",
                    "⅓": "1/3", "⅔": "2/3",
                    "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5",
                    "⅙": "1/6", "⅚": "5/6",
                    "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
                ]
                var out = ""
                for ch in s { out.append(map[ch] ?? String(ch)) }
                return out
            }()
            if trimmedLine.isEmpty { continue }
            
            var handled = false

            // 🍋 Citrus juice and zest processing (run BEFORE generic measurement parsing)
            do {
                // Pattern 1: "6 tablespoons fresh juice from 3 whole lemons" → "Lemon Juice, 6 tablespoons"
                let citrusJuicePattern = #"(?i)^\s*(\d+[\d\/\s\.]*)\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\s+(?:fresh(?:ly)?\s+)?juice\s+from\s+(?:\d+[\d\/\s\.]*\s+)?(?:whole\s+)?(lemon|lemons|lime|limes|orange|oranges|grapefruit|grapefruits)\b"#
                if let juiceRegex = try? NSRegularExpression(pattern: citrusJuicePattern, options: []) {
                    let r = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                    if let m = juiceRegex.firstMatch(in: trimmedLine, options: [], range: r), m.numberOfRanges >= 4,
                       let amountR = Range(m.range(at: 1), in: trimmedLine),
                       let unitR = Range(m.range(at: 2), in: trimmedLine),
                       let fruitR = Range(m.range(at: 3), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountR]))
                        let unit = standardizeUnit(String(trimmedLine[unitR]))
                        let fruit = String(trimmedLine[fruitR]).lowercased().replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                        let ingredientName = "\(fruit.capitalized) Juice"
                        let ingredient = Ingredient(name: ingredientName, amount: amount, unit: unit, category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus juice): \(ingredientName) - \(amount) \(unit) (Produce)")
                        handled = true
                    }
                }
                if handled { continue }
                // Pattern 2: measured fruit zest → "Lemon Zest, 1 tablespoon"
                let zestWithMeasurementPattern = #"(?i)^\s*(\d+[\d\/\s\.]*)\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\s+(lemon|lime|orange|grapefruit)\s+zest\b"#
                if let rx = try? NSRegularExpression(pattern: zestWithMeasurementPattern, options: []) {
                    let r = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                    if let m = rx.firstMatch(in: trimmedLine, options: [], range: r), m.numberOfRanges >= 4,
                       let amountR = Range(m.range(at: 1), in: trimmedLine),
                       let unitR = Range(m.range(at: 2), in: trimmedLine),
                       let fruitR = Range(m.range(at: 3), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountR]))
                        let unit = standardizeUnit(String(trimmedLine[unitR]))
                        let fruit = String(trimmedLine[fruitR]).capitalized
                        let ingredientName = "\(fruit) Zest"
                        let ingredient = Ingredient(name: ingredientName, amount: amount, unit: unit, category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus zest measured): \(ingredientName) - \(amount) \(unit) (Produce)")
                        handled = true
                    }
                }
                if handled { continue }
                // Pattern 3: "Zest of 1 whole lemon" → "Lemon Zest, 1 Lemon"
                let citrusZestOfPattern = #"(?i)^\s*zest\s+of\s+(\d+[\d\/\s\.]*)\s+(?:whole\s+)?(lemon|lemons|lime|limes|orange|oranges|grapefruit|grapefruits)\b"#
                if let rx = try? NSRegularExpression(pattern: citrusZestOfPattern, options: []) {
                    let r = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                    if let m = rx.firstMatch(in: trimmedLine, options: [], range: r), m.numberOfRanges >= 3,
                       let amountR = Range(m.range(at: 1), in: trimmedLine),
                       let fruitR = Range(m.range(at: 2), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountR]))
                        let fruit = String(trimmedLine[fruitR]).lowercased().replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                        let ingredientName = "\(fruit.capitalized) Zest"
                        let unit = amount == 1 ? fruit.capitalized : "\(fruit.capitalized)s"
                        let ingredient = Ingredient(name: ingredientName, amount: amount, unit: unit, category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus zest): \(ingredientName) - \(amount) \(unit) (Produce)")
                        handled = true
                    }
                }
                if handled { continue }
                // Pattern 4: bare fruit zest → name only
                let zestOnlyPattern = #"(?i)^\s*(lemon|lime|orange|grapefruit)\s+zest\b"#
                if let rx = try? NSRegularExpression(pattern: zestOnlyPattern, options: []) {
                    let r = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                    if let m = rx.firstMatch(in: trimmedLine, options: [], range: r), m.numberOfRanges >= 2,
                       let fruitR = Range(m.range(at: 1), in: trimmedLine) {
                        let fruit = String(trimmedLine[fruitR]).capitalized
                        let ingredientName = "\(fruit) Zest"
                        let ingredient = Ingredient(name: ingredientName, amount: 0.0, unit: "", category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus zest only): \(ingredientName) - 0 (Produce)")
                        handled = true
                    }
                }
                if handled { continue }
            }

            // Herb count pattern: e.g., "10 fresh large mint leaves, very thinly sliced"
            do {
                let herbAlt = #"(?:basil|mint|parsley|cilantro|coriander|tarragon|dill|thyme|rosemary|sage|oregano|chives)"#
                // Variant A: amount first
                let patternA = #"(?i)^\s*(one|two|three|four|five|six|seven|eight|nine|ten|a|an|\d+[\d\/\s\.]*)\s+(?:fresh(?:ly)?\s+)?(?:small|medium|large|extra\s*large|xl\s+)?\b(\#(herbAlt))\b(?:\s+leaves?|\s+sprigs?)?(?:\s*,[\s\S]*)?$"#
                // Variant B: 'fresh' before amount (e.g., "fresh 10 large mint leaves")
                let patternB = #"(?i)^\s*(?:fresh(?:ly)?\s+)(one|two|three|four|five|six|seven|eight|nine|ten|a|an|\d+[\d\/\s\.]*)\s+(?:small|medium|large|extra\s*large|xl\s+)?\b(\#(herbAlt))\b(?:\s+leaves?|\s+sprigs?)?(?:\s*,[\s\S]*)?$"#
                for pattern in [patternA, patternB] {
                    guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
                    let r = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                    if let m = rx.firstMatch(in: trimmedLine, options: [], range: r), m.numberOfRanges >= 3,
                       let amountR = Range(m.range(at: 1), in: trimmedLine),
                       let herbR = Range(m.range(at: 2), in: trimmedLine) {
                        let amountString = String(trimmedLine[amountR])
                        let herb = String(trimmedLine[herbR]).lowercased()
                        let amount = parseAmount(amountString)
                        if amount > 0 {
                            // If the text explicitly says "sprigs", prefer sprigs; otherwise default to leaves
                            let unit: String
                            if trimmedLine.range(of: #"(?i)\bsprigs?\b"#, options: .regularExpression) != nil { unit = "sprigs" }
                            else { unit = "leaves" }
                            let ing = Ingredient(name: herb, amount: amount, unit: unit, category: .produce)
                            ingredients.append(ing)
                            print("📋 Regex parsed (herb-count): \(herb) - \(amount) \(unit) (Produce)")
                            handled = true
                            break
                        }
                    }
                }
            }
            if handled { continue }
            // Try measurement-based first; if no match, try count-based
            let matches = regex.matches(in: normalizedLine, options: [], range: NSRange(normalizedLine.startIndex..., in: normalizedLine))
            
            for match in matches {
                if match.numberOfRanges >= 4 {
                    let amountRange = match.range(at: 1)
                    let unitRange = match.range(at: 2)
                    let nameRange = match.range(at: 3)
                    
                    if let amountString = Range(amountRange, in: normalizedLine).map({ String(normalizedLine[$0]) }),
                       let nameString = Range(nameRange, in: normalizedLine).map({ String(normalizedLine[$0]) }) {
                        
                        // Clean first (strip prep/state descriptors), then filter using instruction keywords
                        var cleanName = nameString.trimmingCharacters(in: .whitespacesAndNewlines)
                        cleanName = cleanIngredientName(cleanName)
                        var lowercasedName = cleanName.lowercased()

                        // Herb salvage: if the cleaned name became non-ingredient (e.g., adverb-only), but the raw line contains a known herb,
                        // restore herb name and prefer leaves/sprigs as unit
                        do {
                            let herbAlt = ["basil","mint","parsley","cilantro","coriander","tarragon","dill","thyme","rosemary","sage","oregano","chives"]
                            let rawLower = trimmedLine.lowercased()
                            let adverbNoise: Set<String> = ["very thinly","thinly","finely","roughly","coarsely"]
                            if adverbNoise.contains(lowercasedName) || lowercasedName.isEmpty {
                                if let herb = herbAlt.first(where: { rawLower.contains($0) }) {
                                    cleanName = herb
                                    lowercasedName = herb
                                }
                            }
                        }
                        
                        // Skip if it contains non-ingredient keywords
                        var isNonIngredient = false
                        for keyword in nonIngredientKeywords {
                            if lowercasedName.contains(keyword.lowercased()) {
                                isNonIngredient = true
                                print("🚫 Skipping non-ingredient: \(cleanName) (contains '\(keyword)')")
                                break
                            }
                        }
                        
                        if isNonIngredient {
                            continue
                        }
                        
                        // Additional validation: ingredient names should be reasonable length
                        if cleanName.count < 3 || cleanName.count > 50 {
                            print("🚫 Skipping invalid ingredient name length: \(cleanName)")
                            continue
                        }
                        
                        // Skip if it looks like a cooking instruction (keep only strong instruction verbs)
                        // exclude only strong instruction verbs; allow descriptive words like "mixed"
                        let cookingVerbs = ["cook", "heat", "simmer", "boil", "bake", "roast", "grill"]
                        for verb in cookingVerbs {
                            if lowercasedName.contains(verb) {
                                print("🚫 Skipping cooking instruction: \(cleanName) (contains '\(verb)')")
                                isNonIngredient = true
                                break
                            }
                        }
                        
                        if isNonIngredient {
                            continue
                        }
                        
                        // Parse amount (handle fractions)
                        var amount = parseAmount(amountString)
                        
                        // Parse unit (attach parenthetical size if present between amount and unit)
                        var unit: String
                        if unitRange.location != NSNotFound,
                           let unitRangeSwift = Range(unitRange, in: normalizedLine) {
                            let unitRaw = String(normalizedLine[unitRangeSwift])
                            // Guard against false-positive single-letter units (g/l) leaking from words like garlic/large
                            if unitRaw.count == 1 {
                                let nextIndex = unitRangeSwift.upperBound
                                if nextIndex < trimmedLine.endIndex, trimmedLine[nextIndex].isLetter {
                                    print("🛡️ Skipping 1-letter unit leak (\(unitRaw)) in: \(trimmedLine)")
                                    // Skip this measurement match so count-based parsing can handle it
                                    continue
                                }
                            }
                            unit = standardizeUnit(unitRaw)
                            // Look back between amount and unit for a parenthetical size and include it in the unit
                            if let amountR = Range(amountRange, in: normalizedLine) {
                                let between = normalizedLine[amountR.upperBound..<unitRangeSwift.lowerBound]
                                if let sizeMatch = between.range(of: #"\(([^)]*?)\)"#, options: .regularExpression) {
                                    let sizeText = String(between[sizeMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                                    if !sizeText.isEmpty {
                                        // normalize: "9 ounce" → "9-ounce"
                                        let normalizedSize = sizeText.replacingOccurrences(of: #"(?i)\b(ounce|ounces)\b"#, with: "ounce", options: .regularExpression)
                                            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
                                            .lowercased()
                                        unit = "\(normalizedSize) \(unit)"
                                    }
                                }
                            }
                        } else {
                            unit = "piece"
                        }

                        // If we salvaged an herb, normalize unit to leaves/sprigs when appropriate
                        do {
                            let rawLower = trimmedLine.lowercased()
                            let isHerb = ["basil","mint","parsley","cilantro","coriander","tarragon","dill","thyme","rosemary","sage","oregano","chives"].contains(where: { cleanName.lowercased() == $0 })
                            if isHerb {
                                if rawLower.range(of: #"(?i)\bsprigs?\b"#, options: .regularExpression) != nil {
                                    unit = "sprigs"
                                } else {
                                    unit = "leaves"
                                }
                            }
                        }
                        
                        // Prefer weight in grams for salt only (canonicalize amount)
                        if lowercasedName.contains("salt"),
                           let gramsMatch = try? NSRegularExpression(pattern: "(?i)\\((?:[^)]*?)(\\d+(?:\\.\\d+)?)\\s*(?:g|grams)\\b[^^(]*\\)"),
                           let mm = gramsMatch.firstMatch(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
                           mm.numberOfRanges >= 2,
                           let rr = Range(mm.range(at: 1), in: trimmedLine),
                           let gramsVal = Double(String(trimmedLine[rr])) {
                            amount = gramsVal
                            unit = "grams"
                        } else {
                        // Combine additional volumes like "+ 2 teaspoons" or "plus 2 tsp" and "1 cup plus 2 tablespoons"
                            let plusPattern = "(?i)\\b(?:\\+|plus)\\s*(\\d+[\\d\\/\\s\\.]*)\\s*(cups?|tablespoons?|tbsp|teaspoons?|tsp)\\b"
                            if let plusRegex = try? NSRegularExpression(pattern: plusPattern) {
                                let r = NSRange(cleanName.startIndex..., in: cleanName)
                            let matches = plusRegex.matches(in: cleanName, options: [], range: r)
                            if !matches.isEmpty {
                                // Convert to teaspoons, then normalize
                                func toTeaspoons(_ amt: Double, _ u: String) -> Double {
                                    switch u {
                                    case "teaspoon", "teaspoons", "tsp": return amt
                                    case "tablespoon", "tablespoons", "tbsp": return amt * 3.0
                                    case "cup", "cups": return amt * 48.0
                                    default: return 0
                                    }
                                }
                                var totalTsp = toTeaspoons(amount, unit.lowercased())
                                for m in matches {
                                    if m.numberOfRanges >= 3,
                                       let ar = Range(m.range(at: 1), in: cleanName),
                                       let ur = Range(m.range(at: 2), in: cleanName) {
                                        let addAmount = parseAmount(String(cleanName[ar]))
                                        let addUnitRaw = String(cleanName[ur]).lowercased()
                                        totalTsp += toTeaspoons(addAmount, addUnitRaw)
                                    }
                                }
                                if totalTsp > 0 {
                                    if abs(totalTsp.rounded() - totalTsp) < 1e-6, Int(totalTsp) % 48 == 0 {
                                        amount = roundToPlaces(totalTsp / 48.0, places: 2)
                                        unit = "cups"
                                    } else if Int(totalTsp) % 3 == 0 {
                                        amount = roundToPlaces(totalTsp / 3.0, places: 2)
                                        unit = "tablespoons"
                                    } else {
                                        amount = roundToPlaces(totalTsp, places: 2)
                                        unit = "teaspoons"
                                    }
                                }
                                }
                            }
                        }
                        
                        // Clean ingredient name - remove measurement units and parentheses (but allow compound multi-ingredient lines to fall through later)
                        var cleanIngredientName = cleanIngredientName(cleanName)
                        // Extract size descriptors like "2-inch" into unit if none provided
                        if unit.isEmpty, let sizeText = extractSizeDescriptor(from: nameString) {
                            unit = sizeText
                        }
                        
                        // Remove measurement units in parentheses like "(30 g)", "(20 g)", etc.
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                        
                        // Remove measurement units that might be at the start
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"^[^a-zA-Z]*"#, with: "", options: .regularExpression)
                        
                        // Remove trailing measurement units
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
                        
                        // Remove tool/prep descriptors from the tail of names
                            let tailNoise = [
                            #"(?i)\bon\s+the\s+medium\s+holes\s+of\s+a\s+box\s+grater\b"#,
                            #"(?i)\bgrated\b"#,
                            #"(?i)\bminced\b"#,
                                #"(?i)\bdiced\b"#,
                            #"(?i)\bsliced\b"#,
                            #"(?i)\bthinly\s+sliced\b"#,
                            #"(?i)\bfinely\s+sliced\b"#,
                            #"(?i)\bvery\s+thinly\b"#,
                            #"(?i)\bthinly\b"#,
                            #"(?i)\bfinely\b"#,
                            #"(?i)\broughly\b"#,
                            #"(?i)\bcoarsely\b"#,
                            #"(?i)\broughly\s+sliced\b"#,
                            #"(?i)\btorn\s+into\s+(?:small\s+)?bite[-\s]?size(?:d)?\s+pieces\b"#,
                            #"(?i)\btorn\s+into\s+small\s+pieces\b"#,
                            #"(?i)\btorn\s+into\s+pieces\b"#,
                            #"(?i)\binto\s+(?:small\s+)?bite[-\s]?size(?:d)?\s+pieces\b"#,
                            #"(?i)\binto\s+small\s+pieces\b"#,
                            #"(?i)\binto\s+pieces\b"#,
                            #"(?i)\bdrained\b"#,
                            #"(?i)\brinsed\b"#,
                            #"(?i)\bpatted\s+dry\b"#,
                            #"(?i)\bhalved\b"#,
                            #"(?i)\bquartered\b"#,
                            #"(?i)\bsoaked\s+in\s+cold\s+water\b"#,
                            #"(?i)\bsee\s+note\b"#,
                            #"(?i)\bfor\s+serving\b"#
                        ]
                        for pattern in tailNoise {
                            cleanIngredientName = cleanIngredientName.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                        }
                        
                        // If comma descriptors exist, prefer concrete suggestion after "such as/like/e.g." if present; otherwise, trim after comma
                        if let commaIndex = firstTopLevelCommaIndex(in: cleanIngredientName) {
                            let before = String(cleanIngredientName[..<commaIndex])
                            let after = String(cleanIngredientName[cleanIngredientName.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let rx = try? NSRegularExpression(pattern: "(?i)\\b(?:such\\s+as|like|e\\.g\\.)\\b\\s*([^,;]+)"),
                               let m = rx.firstMatch(in: after, options: [], range: NSRange(after.startIndex..., in: after)),
                               m.numberOfRanges >= 2,
                               let r = Range(m.range(at: 1), in: after) {
                                cleanIngredientName = String(after[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                            } else {
                                cleanIngredientName = before
                            }
                        }
                        // If the unit is sprig/sprigs, fold it into the name and clear the unit
                        if unit.lowercased().contains("sprig") {
                            let sprigWord = (amount == 1.0 ? "sprig" : "sprigs")
                            if !cleanIngredientName.lowercased().contains("sprig") {
                                cleanIngredientName = (cleanIngredientName + " " + sprigWord).trimmingCharacters(in: .whitespaces)
                            }
                            unit = ""
                        }

                        // Clean up extra whitespace
                        cleanIngredientName = cleanIngredientName.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Determine category
                        let category = determineCategory(cleanIngredientName)

                        // Rounding rule for countable produce in regex path
                        var finalAmount = amount
                        var finalUnit = unit
                        let countUnits: Set<String> = ["", "piece", "pieces", "small", "medium", "large", "extra large", "heads", "head", "bunch", "bunches", "clove", "cloves", "sprig", "sprigs", "leaf", "leaves"]
                        if category == .produce && countUnits.contains(finalUnit.lowercased()) {
                            if finalAmount > 0 && finalAmount < 1 {
                                finalAmount = 1.0
                                if finalUnit.isEmpty { finalUnit = "piece" }
                            }
                        }

                        // Singularize count-like units when amount is exactly 1 (preserve any leading size descriptor)
                        if abs(finalAmount - 1.0) < 0.0001 {
                            let pluralToSingular: [String: String] = [
                                "pieces": "piece",
                                "cloves": "clove",
                                "slices": "slice",
                                "heads": "head",
                                "bunches": "bunch",
                                "cans": "can",
                                "jars": "jar",
                                "bottles": "bottle",
                                "packages": "package",
                                "containers": "container",
                                "bags": "bag",
                                "leaves": "leaf",
                                "sprigs": "sprig"
                            ]
                            let trimmedUnit = finalUnit.trimmingCharacters(in: .whitespaces)
                            if !trimmedUnit.isEmpty {
                                var parts = trimmedUnit.split(separator: " ").map(String.init)
                                if let last = parts.last?.lowercased(), let singular = pluralToSingular[last] {
                                    parts.removeLast()
                                    parts.append(singular)
                                    finalUnit = parts.joined(separator: " ")
                                }
                            }
                        }
                        let ingredient = Ingredient(name: cleanIngredientName, amount: finalAmount, unit: finalUnit, category: category)
                        ingredients.append(ingredient)
                        
                        print("📋 Regex parsed: \(cleanIngredientName) - \(finalAmount) \(finalUnit) (\(category))")
                        handled = true
                    }
                }

            // If not handled yet, attempt count-based pattern
            if !handled {
                let cmatches = countRegex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
                if let m = cmatches.first, m.numberOfRanges >= 3 {
                    let amountRange = m.range(at: 1)
                    let nameRange = m.range(at: 2)
                    if let amountString = Range(amountRange, in: trimmedLine).map({ String(trimmedLine[$0]) }),
                       let nameString = Range(nameRange, in: trimmedLine).map({ String(trimmedLine[$0]) }) {
                        var cleanName = nameString.trimmingCharacters(in: .whitespacesAndNewlines)
                        cleanName = cleanIngredientName(cleanName)
                        var lowercasedName = cleanName.lowercased()
                        // Herb salvage for count-based lines: if name collapses to adverb-only, but raw contains herb, restore herb
                        do {
                            let adverbNoise: Set<String> = ["very thinly","thinly","finely","roughly","coarsely"]
                            if adverbNoise.contains(lowercasedName) || lowercasedName.isEmpty {
                                let herbAlt = ["basil","mint","parsley","cilantro","coriander","tarragon","dill","thyme","rosemary","sage","oregano","chives"]
                                let rawLower = trimmedLine.lowercased()
                                if let herb = herbAlt.first(where: { rawLower.contains($0) }) {
                                    cleanName = herb
                                    lowercasedName = herb
                                }
                            }
                        }
                        var isNonIngredient = false
                        for keyword in nonIngredientKeywords {
                            if lowercasedName.contains(keyword.lowercased()) { isNonIngredient = true; break }
                        }
                        if !isNonIngredient && cleanName.count >= 3 && cleanName.count <= 50 {
                            let amount = parseAmount(amountString)
                            var unit = ""
                            var cleanIngredientName = cleanIngredientName(cleanName)
                            // Container-first names with optional size: move container to unit and attach size
                            if let rx = try? NSRegularExpression(pattern: #"(?i)^\s*(?:\(([^)]*)\)\s*)?(can|cans|package|packages|jar|jars|container|containers|bag|bags|bottle|bottles)\s+(.+)$"#),
                               let m2 = rx.firstMatch(in: cleanIngredientName, options: [], range: NSRange(cleanIngredientName.startIndex..., in: cleanIngredientName)),
                               m2.numberOfRanges >= 4 {
                                let sizeText = (Range(m2.range(at: 1), in: cleanIngredientName).map { String(cleanIngredientName[$0]).trimmingCharacters(in: .whitespaces) })
                                let container = Range(m2.range(at: 2), in: cleanIngredientName).map { String(cleanIngredientName[$0]).lowercased() } ?? "package"
                                if let restR = Range(m2.range(at: 3), in: cleanIngredientName) {
                                    cleanIngredientName = String(cleanIngredientName[restR]).trimmingCharacters(in: .whitespaces)
                                }
                                if let size = sizeText, !size.isEmpty {
                                    let normalizedSize = size.replacingOccurrences(of: #"(?i)\b(ounce|ounces)\b"#, with: "ounce", options: .regularExpression)
                                        .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
                                        .lowercased()
                                    unit = "\(normalizedSize) \(standardizeUnit(container))"
                                } else {
                                    unit = standardizeUnit(container)
                                }
                            }
                            // If name starts with optional size in parentheses then 'piece(s)', move that to unit
                            if let rx = try? NSRegularExpression(pattern: #"(?i)^\s*(?:\(([^)]*)\)\s*)?(piece|pieces)\s+(.+)$"#),
                               let m2 = rx.firstMatch(in: cleanIngredientName, options: [], range: NSRange(cleanIngredientName.startIndex..., in: cleanIngredientName)),
                               m2.numberOfRanges >= 4 {
                                let sizeText = (Range(m2.range(at: 1), in: cleanIngredientName).map { String(cleanIngredientName[$0]).lowercased() })
                                let pieceWord = Range(m2.range(at: 2), in: cleanIngredientName).map { String(cleanIngredientName[$0]).lowercased() } ?? "pieces"
                                if let restR = Range(m2.range(at: 3), in: cleanIngredientName) {
                                    cleanIngredientName = String(cleanIngredientName[restR])
                                }
                                if let size = sizeText, !size.isEmpty {
                                    unit = "\(size) \(pieceWord)"
                                } else {
                                    unit = pieceWord
                                }
                            }
                            // If this is a known herb, normalize unit to leaves/sprigs when present or default to leaves
                            do {
                                let herbAlt = ["basil","mint","parsley","cilantro","coriander","tarragon","dill","thyme","rosemary","sage","oregano","chives"]
                                if herbAlt.contains(cleanIngredientName.lowercased()) {
                                    if trimmedLine.range(of: #"(?i)\bsprigs?\b"#, options: .regularExpression) != nil {
                                        unit = "sprigs"
                                    } else {
                                        unit = "leaves"
                                    }
                                }
                            }
                            // Append size descriptor as parenthetical if present in the raw text (but not for salt/pepper)
                            if !cleanIngredientName.lowercased().contains("salt") && !cleanIngredientName.lowercased().contains("pepper"),
                               let sizeText = extractSizeDescriptor(from: nameString) {
                                if !cleanIngredientName.contains("(") {
                                    cleanIngredientName = "\(cleanIngredientName) (\(sizeText))"
                                }
                            }
                            // Prefer concrete examples after comma if present
                            if let commaIndex = firstTopLevelCommaIndex(in: cleanIngredientName) {
                                let before = String(cleanIngredientName[..<commaIndex])
                                let after = String(cleanIngredientName[cleanIngredientName.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if let rx = try? NSRegularExpression(pattern: "(?i)\\b(?:such\\s+as|like|e\\.g\\.)\\b\\s*([^,;]+)"),
                                   let m = rx.firstMatch(in: after, options: [], range: NSRange(after.startIndex..., in: after)),
                                   m.numberOfRanges >= 2,
                                   let r = Range(m.range(at: 1), in: after) {
                                    cleanIngredientName = String(after[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                                } else {
                                    cleanIngredientName = before
                                }
                            }
                            cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                            cleanIngredientName = cleanIngredientName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let category = determineCategory(cleanIngredientName)
                            let ingredient = Ingredient(name: cleanIngredientName, amount: amount, unit: unit, category: category)
                            ingredients.append(ingredient)
                            print("📋 Regex parsed (count): \(cleanIngredientName) - \(amount) \(unit) (\(category))")
                            handled = true
                        }
                    }
                }
            }
            }

            // Fallback: herb pattern like "3 sprigs tarragon, leaves finely minced"
            if !handled {
                let herbPattern = #"(?i)^\s*(\d+[\d\/\s\.]*)\s*(sprig|sprigs|leaf|leaves|stalk|stalks)\s+(?:of\s+)?([^,\.]+)"#
                if let herbRegex = try? NSRegularExpression(pattern: herbPattern, options: []) {
                    let herbMatches = herbRegex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
                    if let m = herbMatches.first, m.numberOfRanges >= 4,
                       let amountRange = Range(m.range(at: 1), in: trimmedLine),
                       let unitRange = Range(m.range(at: 2), in: trimmedLine),
                       let nameRange = Range(m.range(at: 3), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountRange]))
                        var unit = String(trimmedLine[unitRange])
                        var name = String(trimmedLine[nameRange])
                        // strip anything after comma in name
                        if let commaIndex = name.firstIndex(of: ",") { name = String(name[..<commaIndex]) }
                        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        var cleaned = cleanIngredientName(name)
                        if unit.lowercased().contains("sprig") { cleaned = (cleaned + " " + (amount == 1 ? "sprig" : "sprigs")).trimmingCharacters(in: .whitespaces) ; unit = "" }
                        if unit.lowercased().contains("leaf") { cleaned = (cleaned + " " + (amount == 1 ? "leaf" : "leaves")).trimmingCharacters(in: .whitespaces) ; unit = "" }
                        if unit.lowercased().contains("stalk") { cleaned = (cleaned + " " + (amount == 1 ? "stalk" : "stalks")).trimmingCharacters(in: .whitespaces) ; unit = "" }
                        let category = determineCategory(cleaned)

                        // Rounding rule for countable produce in regex path
                        var finalAmount = amount
                        var finalUnit = unit
                        let countUnits: Set<String> = ["", "piece", "pieces", "small", "medium", "large", "extra large", "heads", "head", "bunch", "bunches", "clove", "cloves", "sprig", "sprigs", "leaf", "leaves"]
                        if category == .produce && countUnits.contains(finalUnit.lowercased()) {
                            if finalAmount > 0 && finalAmount < 1 {
                                finalAmount = 1.0
                                if finalUnit.isEmpty { finalUnit = "piece" }
                            }
                        }

                        // Singularize count-like units when amount is exactly 1 (preserve any leading size descriptor)
                        if abs(finalAmount - 1.0) < 0.0001 {
                            let pluralToSingular: [String: String] = [
                                "pieces": "piece",
                                "cloves": "clove",
                                "slices": "slice",
                                "heads": "head",
                                "bunches": "bunch",
                                "cans": "can",
                                "jars": "jar",
                                "bottles": "bottle",
                                "packages": "package",
                                "containers": "container",
                                "bags": "bag",
                                "leaves": "leaf",
                                "sprigs": "sprig"
                            ]
                            let trimmedUnit = finalUnit.trimmingCharacters(in: .whitespaces)
                            if !trimmedUnit.isEmpty {
                                var parts = trimmedUnit.split(separator: " ").map(String.init)
                                if let last = parts.last?.lowercased(), let singular = pluralToSingular[last] {
                                    parts.removeLast()
                                    parts.append(singular)
                                    finalUnit = parts.joined(separator: " ")
                                }
                            }
                        }
                        let ingredient = Ingredient(name: cleaned, amount: finalAmount, unit: finalUnit, category: category)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (herb): \(cleaned) - \(finalAmount) \(finalUnit) (\(category))")
                        handled = true
                    }
                }
            }

            // 🍋 NEW: Citrus juice and zest processing
            if !handled {
                // Pattern 1: "6 tablespoons fresh juice from 3 whole lemons" → "Lemon Juice, 6 tablespoons"
                let citrusJuicePattern = #"(?i)^\s*(\d+[\d\/\s\.]*)\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\s+(?:fresh(?:ly)?\s+)?juice\s+from\s+(?:\d+[\d\/\s\.]*\s+)?(?:whole\s+)?(lemon|lemons|lime|limes|orange|oranges|grapefruit|grapefruits)\b"#
                if let juiceRegex = try? NSRegularExpression(pattern: citrusJuicePattern, options: []) {
                    let juiceMatches = juiceRegex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
                    if let m = juiceMatches.first, m.numberOfRanges >= 4,
                       let amountRange = Range(m.range(at: 1), in: trimmedLine),
                       let unitRange = Range(m.range(at: 2), in: trimmedLine),
                       let fruitRange = Range(m.range(at: 3), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountRange]))
                        let unit = standardizeUnit(String(trimmedLine[unitRange]))
                        let fruit = String(trimmedLine[fruitRange]).lowercased()
                        
                        // Standardize fruit name (remove plural)
                        let fruitName = fruit.replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                        let ingredientName = "\(fruitName.capitalized) Juice"
                        
                        let ingredient = Ingredient(name: ingredientName, amount: amount, unit: unit, category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus juice): \(ingredientName) - \(amount) \(unit) (Produce)")
                        handled = true
                    }
                }
                
                // Pattern 2: "Zest of 1 whole lemon" → "Lemon Zest, 1 Lemon"
                let citrusZestPattern = #"(?i)^\s*zest\s+of\s+(\d+[\d\/\s\.]*)\s+(?:whole\s+)?(lemon|lemons|lime|limes|orange|oranges|grapefruit|grapefruits)\b"#
                if let zestRegex = try? NSRegularExpression(pattern: citrusZestPattern, options: []) {
                    let zestMatches = zestRegex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
                    if let m = zestMatches.first, m.numberOfRanges >= 3,
                       let amountRange = Range(m.range(at: 1), in: trimmedLine),
                       let fruitRange = Range(m.range(at: 2), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountRange]))
                        let fruit = String(trimmedLine[fruitRange]).lowercased()
                        
                        // Standardize fruit name (remove plural)
                        let fruitName = fruit.replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                        let ingredientName = "\(fruitName.capitalized) Zest"
                        let unit = amount == 1 ? fruitName.capitalized : "\(fruitName.capitalized)s" // Use the specific fruit name
                        
                        let ingredient = Ingredient(name: ingredientName, amount: amount, unit: unit, category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus zest): \(ingredientName) - \(amount) \(unit) (Produce)")
                        handled = true
                    }
                }
                
                // Pattern 3: "1 tablespoon lemon zest" → "Lemon Zest, 1 tablespoon"
                let zestWithMeasurementPattern = #"(?i)^\s*(\d+[\d\/\s\.]*)\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\s+(lemon|lime|orange|grapefruit)\s+zest\b"#
                if let zestMeasRegex = try? NSRegularExpression(pattern: zestWithMeasurementPattern, options: []) {
                    let zestMeasMatches = zestMeasRegex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
                    if let m = zestMeasMatches.first, m.numberOfRanges >= 4,
                       let amountRange = Range(m.range(at: 1), in: trimmedLine),
                       let unitRange = Range(m.range(at: 2), in: trimmedLine),
                       let fruitRange = Range(m.range(at: 3), in: trimmedLine) {
                        let amount = parseAmount(String(trimmedLine[amountRange]))
                        let unit = standardizeUnit(String(trimmedLine[unitRange]))
                        let fruit = String(trimmedLine[fruitRange]).capitalized
                        
                        let ingredientName = "\(fruit) Zest"
                        
                        let ingredient = Ingredient(name: ingredientName, amount: amount, unit: unit, category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus zest measured): \(ingredientName) - \(amount) \(unit) (Produce)")
                        handled = true
                    }
                }
                
                // Pattern 4: "lemon zest" (no measurement) → "Lemon Zest"
                let zestOnlyPattern = #"(?i)^\s*(lemon|lime|orange|grapefruit)\s+zest\b"#
                if let zestOnlyRegex = try? NSRegularExpression(pattern: zestOnlyPattern, options: []) {
                    let zestOnlyMatches = zestOnlyRegex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
                    if let m = zestOnlyMatches.first, m.numberOfRanges >= 2,
                       let fruitRange = Range(m.range(at: 1), in: trimmedLine) {
                        let fruit = String(trimmedLine[fruitRange]).capitalized
                        
                        let ingredientName = "\(fruit) Zest"
                        
                        let ingredient = Ingredient(name: ingredientName, amount: 0.0, unit: "", category: .produce)
                        ingredients.append(ingredient)
                        print("📋 Regex parsed (citrus zest only): \(ingredientName) - 0 (Produce)")
                        handled = true
                    }
                }
            }
        }
        
        if ingredients.count >= 2 {
            print("✅ Regex parsing successful: \(ingredients.count) ingredients")
            return ingredients
        } else {
            print("❌ Regex parsing failed: only \(ingredients.count) ingredients found")
            return nil
        }
    }

    // 🚀 NEW: Parse amount from string (handles fractions)
    func parseAmount(_ amountString: String) -> Double {
        let cleanAmount = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle fractions
        if cleanAmount.contains("/") {
            let parts = cleanAmount.components(separatedBy: "/")
            if parts.count == 2,
               let numerator = Double(parts[0]),
               let denominator = Double(parts[1]),
               denominator != 0 {
                return numerator / denominator
            }
        }
        
        // Handle mixed numbers (e.g., "1 1/2")
        if cleanAmount.contains(" ") {
            let parts = cleanAmount.components(separatedBy: " ")
            if parts.count == 2,
               let wholePart = Double(parts[0]),
               parts[1].contains("/") {
                let fractionParts = parts[1].components(separatedBy: "/")
                if fractionParts.count == 2,
                   let numerator = Double(fractionParts[0]),
                   let denominator = Double(fractionParts[1]),
                   denominator != 0 {
                    return wholePart + (numerator / denominator)
                }
            }
        }
        
        // Default to parsing as double
        return Double(cleanAmount) ?? 1.0
    }

    // Precision rounding helper function (file-scope)
    private func roundToPlaces(_ value: Double, places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (value * divisor).rounded() / divisor
    }
    
    // 🚀 NEW: Determine ingredient category from name
    private func determineCategory(_ name: String) -> GroceryCategory {
        let lowercasedName = name.lowercased()
        
        // Check category overrides first
        for (keyword, category) in categoryOverrides {
            if lowercasedName.contains(keyword) {
                return category
            }
        }
        
        // Check category keywords (force 'frozen' to Frozen category first),
        // only when 'frozen' refers to the ingredient state, not a product name like "frozen yogurt".
        if lowercasedName.contains("frozen") {
            // If it already includes another explicit category word like 'yogurt' (dairy) or 'drink' (beverages),
            // allow the normal keyword logic below to decide; otherwise force Frozen.
            let otherCategoryHints = ["yogurt", "milk", "cream", "juice", "drink", "beverage", "broth", "stock"]
            let hasOtherHint = otherCategoryHints.contains { lowercasedName.contains($0) }
            if !hasOtherHint { return .frozen }
        }
        
        // Check category keywords
        let categoryKeywords = self.categoryKeywords
        for (category, keywords) in categoryKeywords {
            for keyword in keywords {
                if lowercasedName.contains(keyword) {
                    return category
                }
            }
        }
        
        // Default to pantry
        return .pantry
    }
    
    // 🚀 NEW: Extract recipe title from HTML
    func extractRecipeTitle(from html: String) -> String? {
        print("🔍 Extracting recipe title...")
        
        // Try JSON-LD first
        if let structuredData = extractStructuredData(from: html),
           let jsonData = structuredData.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            
            // Handle both single recipe and array of recipes
            var recipeData: [String: Any]?
            if let recipes = json["@graph"] as? [[String: Any]] {
                recipeData = recipes.first { recipe in
                    recipe["@type"] as? String == "Recipe"
                }
            } else if json["@type"] as? String == "Recipe" {
                recipeData = json
            }
            
            if let recipeData = recipeData,
               let name = recipeData["name"] as? String {
                print("✅ Found title in JSON-LD: \(name)")
                return name
            }
        }
        
        // Try HTML title tag
        let titlePattern = #"<title[^>]*>(.*?)</title>"#
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let title = String(html[range])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !title.isEmpty && title.count < 100 {
                print("✅ Found title in HTML: \(title)")
                return title
            }
        }
        
        // Try h1 tag
        let h1Pattern = #"<h1[^>]*>(.*?)</h1>"#
        if let regex = try? NSRegularExpression(pattern: h1Pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let title = String(html[range])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !title.isEmpty && title.count < 100 {
                print("✅ Found title in H1: \(title)")
                return title
            }
        }
        
        print("❌ No recipe title found")
        return nil
    }
    
    // 🚀 NEW: Estimate token count for content
    func estimateTokenCount(_ content: String) -> Int {
        // Rough estimation: 1 token ≈ 4 characters for English text
        let estimatedTokens = content.count / 4
        print("📊 Estimated tokens: \(estimatedTokens)")
        return estimatedTokens
    }
    
    // 🚀 NEW: Truncate content to target token count
    func truncateContent(_ content: String, targetTokens: Int) -> String {
        let targetChars = targetTokens * 4 // Rough conversion back to characters
        let truncated = String(content.prefix(targetChars))
        print("✂️ Truncated content from \(content.count) to \(truncated.count) characters")
        return truncated
    }
    
    // 🚀 NEW: Parse ingredient from string (for structured data)
    // TEMP DEBUG removed
    @MainActor
    func parseIngredientFromString(_ ingredientString: String) -> Ingredient? {
        // TEMP DEBUG removed
        var cleanString = ingredientString.trimmingCharacters(in: .whitespacesAndNewlines)
        var isCannedOrJarredItem: Bool = false

        // 🍋 Citrus normalization (quick parser): juice and zest
        do {
            let line = cleanString
            // Pattern A: amount + unit + fresh? juice from N whole fruits
            // e.g., "6 tablespoons fresh juice from 3 whole lemons"
            if let rx = try? NSRegularExpression(pattern: "(?i)^\\s*(\\d+[\\d\\/\\s\\.]*)\\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\\s+(?:fresh(?:ly)?\\s+)?juice\\s+from\\s+(?:\\d+[\\d\\/\\s\\.]*\\s+)?(?:whole\\s+)?(lemon|lemons|lime|limes|orange|oranges|grapefruit|grapefruits)\\b") {
                let r = NSRange(line.startIndex..., in: line)
                if let m = rx.firstMatch(in: line, options: [], range: r), m.numberOfRanges >= 4,
                   let amountR = Range(m.range(at: 1), in: line),
                   let unitR = Range(m.range(at: 2), in: line),
                   let fruitR = Range(m.range(at: 3), in: line) {
                    let amount = parseAmount(String(line[amountR]))
                    let unit = standardizeUnit(String(line[unitR]))
                    let fruit = String(line[fruitR]).lowercased().replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                    let name = "\(fruit.capitalized) Juice"
                    return Ingredient(name: name, amount: amount, unit: unit, category: .produce)
                }
            }
            // Pattern B: amount + unit + fruit juice (direct)
            // e.g., "1/4 cup lemon juice"
            if let rx = try? NSRegularExpression(pattern: "(?i)^\\s*(\\d+[\\d\\/\\s\\.]*)\\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\\s*(lemon|lime|orange|grapefruit)\\s+juice\\b") {
                let r = NSRange(line.startIndex..., in: line)
                if let m = rx.firstMatch(in: line, options: [], range: r), m.numberOfRanges >= 4,
                   let amountR = Range(m.range(at: 1), in: line),
                   let unitR = Range(m.range(at: 2), in: line),
                   let fruitR = Range(m.range(at: 3), in: line) {
                    let amount = parseAmount(String(line[amountR]))
                    let unit = standardizeUnit(String(line[unitR]))
                    let fruit = String(line[fruitR]).capitalized
                    let name = "\(fruit) Juice"
                    return Ingredient(name: name, amount: amount, unit: unit, category: .produce)
                }
            }
            // Pattern C: Zest of N whole fruits → "Lemon Zest, N Lemon(s)"
            if let rx = try? NSRegularExpression(pattern: "(?i)^\\s*zest\\s+of\\s+(\\d+[\\d\\/\\s\\.]*)\\s+(?:whole\\s+)?(lemon|lemons|lime|limes|orange|oranges|grapefruit|grapefruits)\\b") {
                let r = NSRange(line.startIndex..., in: line)
                if let m = rx.firstMatch(in: line, options: [], range: r), m.numberOfRanges >= 3,
                   let amountR = Range(m.range(at: 1), in: line),
                   let fruitR = Range(m.range(at: 2), in: line) {
                    let amount = parseAmount(String(line[amountR]))
                    let fruitLc = String(line[fruitR]).lowercased().replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                    let fruit = fruitLc.capitalized
                    let name = "\(fruit) Zest"
                    let unit = amount == 1 ? fruit : "\(fruit)s"
                    return Ingredient(name: name, amount: amount, unit: unit, category: .produce)
                }
            }
            // Pattern D: measured fruit zest (e.g., "1 tablespoon lemon zest")
            if let rx = try? NSRegularExpression(pattern: "(?i)^\\s*(\\d+[\\d\\/\\s\\.]*)\\s*(tablespoons?|tbsp|teaspoons?|tsp|cups?|ounces?|oz|milliliters?|ml|liters?|l)\\s+(lemon|lime|orange|grapefruit)\\s+zest\\b") {
                let r = NSRange(line.startIndex..., in: line)
                if let m = rx.firstMatch(in: line, options: [], range: r), m.numberOfRanges >= 4,
                   let amountR = Range(m.range(at: 1), in: line),
                   let unitR = Range(m.range(at: 2), in: line),
                   let fruitR = Range(m.range(at: 3), in: line) {
                    let amount = parseAmount(String(line[amountR]))
                    let unit = standardizeUnit(String(line[unitR]))
                    let fruit = String(line[fruitR]).capitalized
                    let name = "\(fruit) Zest"
                    return Ingredient(name: name, amount: amount, unit: unit, category: .produce)
                }
            }
            // Pattern E: bare fruit zest → name only
            if let rx = try? NSRegularExpression(pattern: "(?i)^\\s*(lemon|lime|orange|grapefruit)\\s+zest\\b") {
                let r = NSRange(line.startIndex..., in: line)
                if let m = rx.firstMatch(in: line, options: [], range: r), m.numberOfRanges >= 2,
                   let fruitR = Range(m.range(at: 1), in: line) {
                    let fruit = String(line[fruitR]).capitalized
                    let name = "\(fruit) Zest"
                    return Ingredient(name: name, amount: 0.0, unit: "", category: .produce)
                }
            }
        }
		// Normalize unicode vulgar fractions to ASCII equivalents; also separate attached forms like "1½" → "1 1/2"
		do {
			let fractionMap: [Character: String] = [
				"¼": "1/4", "½": "1/2", "¾": "3/4",
				"⅐": "1/7", "⅑": "1/9", "⅒": "1/10",
				"⅓": "1/3", "⅔": "2/3",
				"⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5",
				"⅙": "1/6", "⅚": "5/6",
				"⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
			]
			// Insert a space between a digit and an attached fraction glyph
			if let rx = try? NSRegularExpression(pattern: "(?i)([0-9])([¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])") {
				cleanString = rx.stringByReplacingMatches(in: cleanString, options: [], range: NSRange(cleanString.startIndex..., in: cleanString), withTemplate: "$1 $2")
			}
			// Replace all fraction glyphs with ASCII equivalents
			var normalized: String = ""
			for ch in cleanString {
				if let rep = fractionMap[ch] {
					normalized.append(rep)
				} else {
					normalized.append(ch)
				}
			}
			cleanString = normalized
		}
        // Remove leading numeric list enumerators like "1 Thinly sliced fresh chives" only when the token
        // after the number is a preparation descriptor (not regular produce like "1 red pepper")
        do {
            let hasUnitToken = cleanString.range(of: #"(?i)\b(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|ounce|ounces|pound|pounds|gram|grams|g|kg|ml|l|clove|cloves|leaf|leaves|sprig|sprigs|piece|pieces|package|packages|jar|jars|bottle|bottles|bag|bags|bunch|bunches|head|heads|slice|slices)\b"#, options: .regularExpression) != nil
            let descriptorAfterNumber = cleanString.range(of: #"(?i)^\s*\d+\s+(thinly|finely|roughly|coarsely|fresh(?:ly)?|minced|sliced|chopped|diced|grated|shaved|torn|rinsed|drained|peeled|zested)\b"#, options: .regularExpression) != nil
            if !hasUnitToken && descriptorAfterNumber,
               let rx = try? NSRegularExpression(pattern: #"^\s*\d+\s+"#) {
                cleanString = rx.stringByReplacingMatches(in: cleanString, options: [], range: NSRange(cleanString.startIndex..., in: cleanString), withTemplate: "")
            }
        }

        // TEMP DEBUG removed

        // Herb pre-parse (high priority): capture lines like
        // "10 fresh large mint leaves, very thinly sliced" or "fresh 10 large mint leaves, very thinly sliced"
        do {
            let herbAlt = #"(?:basil|mint|parsley|cilantro|coriander|tarragon|dill|thyme|rosemary|sage|oregano|chives)"#
            let amountAlt = #"(one|two|three|four|five|six|seven|eight|nine|ten|a|an|\d+[\d\/\s\.]*)"#
            let tailAlt = #"(?:,\s*(?:very\s+thinly|thinly|finely|roughly|coarsely)\s+(?:sliced|minced|chopped|zested))?"#
            // amount-first
            let pA = #"(?i)^\s*\#(amountAlt)\s+(?:fresh(?:ly)?\s+)?(?:small|medium|large|extra\s*large|xl\s+)?\b(\#(herbAlt))\b(?:\s+leaves?|\s+sprigs?)?\s*\#(tailAlt)\s*$"#
            // fresh-first
            let pB = #"(?i)^\s*(?:fresh(?:ly)?\s+)\#(amountAlt)\s+(?:small|medium|large|extra\s*large|xl\s+)?\b(\#(herbAlt))\b(?:\s+leaves?|\s+sprigs?)?\s*\#(tailAlt)\s*$"#
            for pattern in [pA, pB] {
                if let rx = try? NSRegularExpression(pattern: pattern) {
                    let r = NSRange(cleanString.startIndex..., in: cleanString)
                    if let m = rx.firstMatch(in: cleanString, options: [], range: r), m.numberOfRanges >= 3,
                       let ar = Range(m.range(at: 1), in: cleanString),
                       let hr = Range(m.range(at: 2), in: cleanString) {
                        let amt = parseAmount(String(cleanString[ar]))
                        let herb = String(cleanString[hr]).lowercased()
                        if amt > 0 {
                            let unit = (cleanString.range(of: #"(?i)\bsprigs?\b"#, options: .regularExpression) != nil) ? "sprigs" : "leaves"
                            return Ingredient(name: herb, amount: amt, unit: unit, category: .produce)
                        }
                    }
                }
            }
        }

        // Simple herb fallback: leading amount + any herb + "leaves" anywhere
        do {
            let lower = cleanString.lowercased()
            let herbs = ["basil","mint","parsley","cilantro","coriander","tarragon","dill","thyme","rosemary","sage","oregano","chives"]
            if let herb = herbs.first(where: { lower.contains($0) && (lower.contains(" leaves") || lower.contains(" leaf")) }) {
                if let rxAmt = try? NSRegularExpression(pattern: #"(?i)^\s*(\d+[\d\/\s\.]*)\b"#),
                   let m = rxAmt.firstMatch(in: cleanString, options: [], range: NSRange(cleanString.startIndex..., in: cleanString)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: cleanString) {
                    let amt = parseAmount(String(cleanString[r]))
                    if amt > 0 {
                        return Ingredient(name: herb, amount: amt, unit: "leaves", category: .produce)
                    }
                }
            }
        }
        let lower = cleanString.lowercased()
        // Guard: skip lines that are likely directions/instructions
        let instructionTokens = [
            "add ", "cook ", "stir ", "simmer", "boil", "bake", "roast", "grill", "melt ", "transfer ", "return ", "set aside",
            "until ", "over medium", "over high", "over low", "; cook", "; stir"
        ]
        if instructionTokens.contains(where: { lower.contains($0) }) { return nil }
        if lower.range(of: #"\b(?:about\s+)?\d+\s+(minutes?|seconds?)\b"#, options: .regularExpression) != nil { return nil }
        
        // Try to extract amount and unit using regex (include full words to prevent leakage into name)
        let pattern = #"(?i)(\d+[\d\/\s\.]*)\s*(cup|cups|teaspoon|teaspoons|tsp|tablespoon|tablespoons|tbsp|oz|ounce|ounces|pound|pounds|grams?|g(?![a-z])|ml|milliliter|milliliters|liter|liters|l(?![a-z])|clove|cloves|leaf|leaves|sprig|sprigs|piece|pieces|pinch|pinches|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches|head|heads|slice|slices|small|medium|large|extra\s*large|xl)?\s*(.*)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: cleanString, options: [], range: NSRange(cleanString.startIndex..., in: cleanString)),
              match.numberOfRanges >= 4 else {
            // If no measurement found, treat as single item
            var cleanName = cleanIngredientName(cleanString)
            
            // Remove measurement units in parentheses like "(30 g)", "(20 g)", etc.
            cleanName = cleanName.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            
            // Remove measurement units that might be at the start
            cleanName = cleanName.replacingOccurrences(of: #"^[^a-zA-Z]*"#, with: "", options: .regularExpression)
            
            // Remove trailing measurement units
            cleanName = cleanName.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            
            // Prefer concrete examples after comma (such as/like/e.g.)
            // Otherwise, choose the segment that looks like a real ingredient (produce beats pantry),
            // falling back to the longer segment.
            if let commaIndex = cleanName.firstIndex(of: ",") {
                let before = String(cleanName[..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let after = String(cleanName[cleanName.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Prefer LHS when RHS is just a prep/adverb tail (e.g., "very thinly sliced")
                if after.range(of: #"(?i)^(?:very\s+thinly|thinly|finely|roughly|coarsely)(?:\s+(?:sliced|minced|chopped|zested))?.*$"#, options: .regularExpression) != nil {
                    cleanName = before
                } else
                if let rx = try? NSRegularExpression(pattern: #"(?i)\b(?:such\s+as|like|e\.g\.)\b\s*([^,;]+)"#),
                   let m = rx.firstMatch(in: after, options: [], range: NSRange(after.startIndex..., in: after)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: after) {
                    cleanName = String(after[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                // If the trailing clause looks like a note (e.g., "divided", "plus more"), ignore it
                if after.range(of: #"(?i)^(?:divided|plus\s+more|plus\s+extra|to\s+taste|as\s+needed|or\s+.+)$"#, options: .regularExpression) != nil {
                        cleanName = before
                    } else {
                        // Prefer the ingredient-y side using category signal and descriptor-only heuristic
                        let beforeCat = determineCategory(before)
                        let afterCat = determineCategory(after)
                        let descriptorOnly = before.range(of: #"(?i)^(?:fresh|ripe|best(?:-|\s*)quality|quality|summer|peak(?:-|\s*)season|small|medium|large|extra\s*large|xl)\b"#, options: .regularExpression) != nil
                        if (afterCat != .pantry && beforeCat == .pantry) || afterCat == .produce || descriptorOnly {
                            cleanName = after
                        } else {
                            cleanName = before
                        }
                    }
                }
            }

            // Clean up extra whitespace
            cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines)

            // Local amount/unit defaults for this no-explicit-measurement branch
            var unit = ""
            var amount = 0.0

            // Final name/unit normalization
            let category = determineCategory(cleanName)
            // Lowercase conjunctions inside name
            do {
                let lowercaseTokens: Set<String> = ["and", "or", "of", "with", "in", "on", "for", "to", "from"]
                let parts = cleanName.split(separator: " ", omittingEmptySubsequences: false)
                if parts.count > 1 {
                    var rebuilt: [String] = []
                    for (idx, p) in parts.enumerated() {
                        let token = String(p)
                        if idx > 0 && lowercaseTokens.contains(token.lowercased()) {
                            rebuilt.append(token.lowercased())
                        } else {
                            rebuilt.append(token)
                        }
                    }
                    cleanName = rebuilt.joined(separator: " ")
                }
            }
            return Ingredient(name: cleanName, amount: amount, unit: unit, category: category)
        }
        
        let amountRange = match.range(at: 1)
        let unitRange = match.range(at: 2)
        let nameRange = match.range(at: 3)
        
        guard let amountString = Range(amountRange, in: cleanString).map({ String(cleanString[$0]) }),
              let nameString = Range(nameRange, in: cleanString).map({ String(cleanString[$0]) }) else {
            return nil
        }
        
        var amount = parseAmount(amountString)
        
        var unit: String
        if unitRange.location != NSNotFound,
           let unitRangeSwift = Range(unitRange, in: cleanString) {
            let unitRaw = String(cleanString[unitRangeSwift])
            if unitRaw.count == 1 {
                let nextIndex = unitRangeSwift.upperBound
                if nextIndex < cleanString.endIndex, cleanString[nextIndex].isLetter {
                    // Let count-based or name cleanup handle; avoid stealing 'g' from 'garlic'
                    unit = ""
                } else {
                    unit = standardizeUnit(unitRaw)
                }
            } else {
                unit = standardizeUnit(unitRaw)
            }
        } else {
            unit = ""
        }
        
        // Pre-clean: lift leading container words (can/package/jar/bottle/bag/bunch/head/slice/clove/piece)
        var rawName = nameString.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize patterns like "5 garlic cloves" or "5 medium cloves of garlic" → name: garlic, unit: (size) cloves
        do {
            let sizeGroup = "(small|medium|large|extra\\s*large)"
            if let m = try? NSRegularExpression(pattern: "(?i)^\\s*fresh\\s+garlic\\s+" + sizeGroup + "?\\s*cloves?\\b.*")
                .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)), m.numberOfRanges >= 1 {
                // Extract size if present
                if let sm = try? NSRegularExpression(pattern: "(?i)" + sizeGroup)
                    .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)),
                   sm.numberOfRanges >= 2, let r = Range(sm.range(at: 1), in: rawName) {
                    unit = String(rawName[r]).lowercased() + " cloves"
                } else {
                    unit = "cloves"
                }
                rawName = "garlic"
            } else if let m = try? NSRegularExpression(pattern: "(?i)^\\s*garlic\\s+" + sizeGroup + "?\\s*cloves?\\b.*")
                .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)), m.numberOfRanges >= 1 {
                if let sm = try? NSRegularExpression(pattern: "(?i)" + sizeGroup)
                    .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)),
                   sm.numberOfRanges >= 2, let r = Range(sm.range(at: 1), in: rawName) {
                    unit = String(rawName[r]).lowercased() + " cloves"
                } else {
                    unit = "cloves"
                }
                rawName = "garlic"
            } else if let m = try? NSRegularExpression(pattern: "(?i)^\\s*" + sizeGroup + "?\\s*cloves?\\s+(?:of\\s+)?garlic\\b.*")
                .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)), m.numberOfRanges >= 1 {
                if let sm = try? NSRegularExpression(pattern: "(?i)" + sizeGroup)
                    .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)),
                   sm.numberOfRanges >= 2, let r = Range(sm.range(at: 1), in: rawName) {
                    unit = String(rawName[r]).lowercased() + " cloves"
                } else {
                    unit = "cloves"
                }
                rawName = "garlic"
            }
        }
        if let m = try? NSRegularExpression(pattern: #"(?i)^\s*(?:\d+[\d\/\s\.]*)?\s*(?:\(([^)]*)\)\s*)?(?:a|an|one)?\s*(can|cans|package|packages|jar|jars|bottle|bottles|container|containers|bag|bags|bunch|bunches|head|heads|slice|slices|clove|cloves|piece|pieces)\s+(.+)$"#)
            .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)),
           m.numberOfRanges >= 4,
           let rSizeAll = Range(m.range(at: 1), in: rawName),
           let rContainer = Range(m.range(at: 2), in: rawName),
           let rRest = Range(m.range(at: 3), in: rawName) {
            let container = String(rawName[rContainer]).lowercased()
            let sizeCapture: String = String(rawName[rSizeAll]).lowercased()
            let rest = String(rawName[rRest])
            rawName = rest
            if unit.isEmpty {
                let normalizedContainer = standardizeUnit(container)
                // Attach parenthetical size for common sized containers (cans, packages, jars, bottles, containers)
                let sizedContainers: Set<String> = ["can", "cans", "package", "packages", "jar", "jars", "bottle", "bottles", "container", "containers"]
                if !sizeCapture.isEmpty, sizedContainers.contains(normalizedContainer) {
                    // Only mark pantry-by-container when it's truly canned/jarred (not generic packages/containers)
                    if normalizedContainer == "can" || normalizedContainer == "cans" || normalizedContainer == "jar" || normalizedContainer == "jars" {
                        isCannedOrJarredItem = true
                    }
                    // Build a hyphenated size like "16-ounce" from "16 ounce" or "14.5 oz"
                    var sizeText = sizeCapture.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let rx = try? NSRegularExpression(pattern: #"(?i)^\s*([0-9]+(?:\.[0-9]+)?)\s*(oz|ounce|ounces)\s*$"#) {
                        let r = NSRange(sizeText.startIndex..., in: sizeText)
                        if let mm = rx.firstMatch(in: sizeText, options: [], range: r), mm.numberOfRanges >= 3,
                           let nr = Range(mm.range(at: 1), in: sizeText) {
                            let num = String(sizeText[nr])
                            sizeText = "\(num)-ounce"
                        }
                    }
                    // Fallbacks for grams and milliliters if present
                    if sizeText == sizeCapture {
                        if let rx = try? NSRegularExpression(pattern: #"(?i)^\s*([0-9]+(?:\.[0-9]+)?)\s*(g|gram|grams)\s*$"#) {
                            let r = NSRange(sizeText.startIndex..., in: sizeText)
                            if let mm = rx.firstMatch(in: sizeText, options: [], range: r), mm.numberOfRanges >= 3,
                               let nr = Range(mm.range(at: 1), in: sizeText) {
                                let num = String(sizeText[nr])
                                sizeText = "\(num)-gram"
                            }
                        }
                    }
                    if sizeText == sizeCapture {
                        if let rx = try? NSRegularExpression(pattern: #"(?i)^\s*([0-9]+(?:\.[0-9]+)?)\s*(ml|milliliter|milliliters)\s*$"#) {
                            let r = NSRange(sizeText.startIndex..., in: sizeText)
                            if let mm = rx.firstMatch(in: sizeText, options: [], range: r), mm.numberOfRanges >= 3,
                               let nr = Range(mm.range(at: 1), in: sizeText) {
                                let num = String(sizeText[nr])
                                sizeText = "\(num)-milliliter"
                            }
                        }
                    }
                    // Choose singular/plural container based on amount and container type
                    func singularFor(_ normalized: String) -> String {
                        switch normalized {
                        case "cans": return "can"
                        case "packages": return "package"
                        case "jars": return "jar"
                        case "bottles": return "bottle"
                        case "containers": return "container"
                        default: return normalized
                        }
                    }
                    let containerWord = (abs(amount - 1.0) < 0.0001) ? singularFor(normalizedContainer) : normalizedContainer
                    unit = "\(sizeText) \(containerWord)"
                } else {
                    unit = normalizedContainer
                }
            }
        }
        // Normalize patterns like "4 small pinches of Espelette pepper" → unit: pinches, name: Espelette pepper
        do {
            let unitLower = unit.lowercased()
            let sizeTokens: Set<String> = ["small", "medium", "large", "extra large"]
            if sizeTokens.contains(unitLower) {
                if let m = try? NSRegularExpression(pattern: #"(?i)^\s*pinches?\s+of\s+(.+)$"#)
                    .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: rawName) {
                    unit = "pinches"
                    rawName = String(rawName[r]).trimmingCharacters(in: .whitespaces)
                }
            } else if unit.isEmpty {
                if let m = try? NSRegularExpression(pattern: #"(?i)^\s*(?:small|medium|large|extra\s*large)?\s*pinches?\s+of\s+(.+)$"#)
                    .firstMatch(in: rawName, options: [], range: NSRange(rawName.startIndex..., in: rawName)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: rawName) {
                    unit = "pinches"
                    rawName = String(rawName[r]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        var cleanName = cleanIngredientName(rawName)
        // If the parsed unit is empty but the name starts with a unit word, move it to unit
        if unit.isEmpty {
            if let m = try? NSRegularExpression(pattern: #"(?i)^(cup|cups|teaspoon|teaspoons|tsp|tablespoon|tablespoons|tbsp|oz|ounce|ounces|pound|pounds|grams?|g(?![a-z])|ml|milliliter|milliliters|liter|liters|l|clove|cloves|piece|pieces|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches|head|heads|slice|slices)(?![a-z])\b"#)
                .firstMatch(in: cleanName, options: [], range: NSRange(cleanName.startIndex..., in: cleanName)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: cleanName) {
                let token = String(cleanName[r]).lowercased()
                var shouldUse = true
                // Prevent single-letter units 'l' or 'g' from leaking from words like 'large' or 'garlic'
                if token == "l" || token == "g" {
                    let after = r.upperBound
                    if after < cleanName.endIndex, cleanName[after].isLetter {
                        shouldUse = false
                    }
                }
                if shouldUse {
                    unit = standardizeUnit(token)
                    cleanName = String(cleanName[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // Container + size normalization at parse time (handles inputs like "(1-inch) piece fresh ginger")
        do {
            let startsWithPiece = (cleanName.range(of: #"(?i)^\s*(?:\(([^)]*)\)\s*)?(?:a|an|one)?\s*(piece|pieces)\b"#, options: .regularExpression) != nil)
            if startsWithPiece || unit.lowercased().contains("piece") {
                // Extract size from the original ingredient string if present
                var sizeText: String = ""
                if let m = try? NSRegularExpression(pattern: #"(?i)\((\d+(?:[\/\.]\d+)?-?inch)\)"#)
                    .firstMatch(in: cleanString, options: [], range: NSRange(cleanString.startIndex..., in: cleanString)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: cleanString) {
                    sizeText = String(cleanString[r]).lowercased()
                }
                // Move leading "(size) piece(s)" out of the name
                cleanName = cleanName.replacingOccurrences(of: #"(?i)^\s*(?:\([^)]*\)\s*)?(?:a|an|one)?\s*(piece|pieces)\s+"#, with: "", options: .regularExpression)
                // Drop leading freshness descriptor left behind
                cleanName = cleanName.replacingOccurrences(of: #"(?i)^\s*fresh\s+"#, with: "", options: .regularExpression)
                // Build unit with size if available
                let pieceWord = unit.lowercased().contains("pieces") ? "pieces" : (unit.lowercased().contains("piece") ? "piece" : (startsWithPiece ? "piece" : unit))
                if !sizeText.isEmpty {
                    unit = sizeText + " " + pieceWord
                } else {
                    unit = pieceWord
                }
            }
        }
        // Removed: duplicate seasoning 'to taste' and 'for serving' handling; centralized in processing stage

        // Prefer concrete examples after comma (such as/like/e.g.)
        // Otherwise, choose the segment that looks like a real ingredient (produce beats pantry),
        // falling back to the longer segment. Treat trailing citrus source notes ("from N limes") as notes.
        if let commaIndex = firstTopLevelCommaIndex(in: cleanName) {
            let before = String(cleanName[..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(cleanName[cleanName.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // If trailing clause is a citrus source note like "from about 4 small limes", prefer the main ingredient
            if after.range(of: #"(?i)^from\s+(?:about\s+)?[0-9]+(?:[\/\.\s][0-9]+)?\s+(?:small\s+|medium\s+|large\s+|extra\s*large\s+)?(?:lime|limes|lemon|lemons|orange|oranges|grapefruit|grapefruits)\b"#, options: .regularExpression) != nil {
                cleanName = before
            } else if let rx = try? NSRegularExpression(pattern: #"(?i)\b(?:such\s+as|like|e\.g\.)\b\s*([^,;]+)"#),
                      let m = rx.firstMatch(in: after, options: [], range: NSRange(after.startIndex..., in: after)),
                      m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: after) {
                cleanName = String(after[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // If the trailing clause looks like a note (e.g., "divided", "plus more"), ignore it
                if after.range(of: #"(?i)^(?:divided|plus\s+more|plus\s+extra|to\s+taste|as\s+needed|or\s+.+)$"#, options: .regularExpression) != nil {
                    cleanName = before
                } else {
                    // Prefer the ingredient-y side using category signal and descriptor-only heuristic
                    let beforeCat = determineCategory(before)
                    let afterCat = determineCategory(after)
                    let descriptorOnly = before.range(of: #"(?i)^(?:fresh|ripe|best(?:-|\s*)quality|quality|summer|peak(?:-|\s*)season|small|medium|large|extra\s*large|xl)\b"#, options: .regularExpression) != nil
                    if (afterCat != .pantry && beforeCat == .pantry) || afterCat == .produce || descriptorOnly {
                        cleanName = after
                    } else {
                        cleanName = before
                    }
                }
            }
        }

        // Final name/unit normalization
        var category = determineCategory(cleanName)
        if isCannedOrJarredItem { category = .pantry }
        // Lowercase conjunctions inside name
        do {
            let lowercaseTokens: Set<String> = ["and", "or", "of", "with", "in", "on", "for", "to", "from"]
            let parts = cleanName.split(separator: " ", omittingEmptySubsequences: false)
            if parts.count > 1 {
                var rebuilt: [String] = []
                for (idx, p) in parts.enumerated() {
                    let token = String(p)
                    if idx > 0 && lowercaseTokens.contains(token.lowercased()) {
                        rebuilt.append(token.lowercased())
                    } else {
                        rebuilt.append(token)
                    }
                }
                cleanName = rebuilt.joined(separator: " ")
            }
        }
        unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        // If this is produce and unit is a count-like token or empty, round up fractional amounts
        let countUnits: Set<String> = ["", "piece", "pieces", "small", "medium", "large", "extra large", "heads", "head", "bunch", "bunches", "clove", "cloves", "sprig", "sprigs", "leaf", "leaves"]
        if category == .produce && countUnits.contains(unit.lowercased()) {
            if amount > 0 && amount < 1 {
                // round up fractional produce to 1 piece for shopping
                return Ingredient(name: cleanName, amount: 1.0, unit: unit.isEmpty ? "piece" : unit, category: category)
            }
        }

        return Ingredient(name: cleanName, amount: amount, unit: unit, category: category)
    }
    
    private func fetchWebpageContent(from url: String) async throws -> String {
        guard let url = URL(string: url) else {
            print("❌ Invalid URL: \(url)")
            throw LLMServiceError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("❌ Invalid HTTP response")
            throw LLMServiceError.invalidResponse
        }
        guard let htmlString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to decode HTML content")
            throw LLMServiceError.invalidResponse
        }
        return htmlString
    }
    
    private func createRecipeParsingPrompt(ingredientContent: String) -> String {
        return """
        Respond ONLY with a JSON object. Do not include markdown, explanation, or formatting.

        Parse ingredients into {"ingredients":[{"name":X,"amount":Y,"unit":Z,"category":C}]}

        Rules:
        1. name: Remove prep words, keep essential descriptors
        2. amount: Convert ALL fractions to decimals (default to 1 if no amount)
        3. unit: Standardize to full words (default to "piece" if no unit)
        4. category: Must be one of [Produce, Meat & Seafood, Deli, Bakery, Frozen, Pantry, Dairy, Beverages]

        Examples:
        "2 1/2 tbsp finely chopped fresh basil" → {"name":"basil","amount":2.5,"unit":"tablespoons","category":"Produce"}
        "1 (14.5 oz) can diced tomatoes, drained" → {"name":"tomatoes","amount":14.5,"unit":"ounces","category":"Pantry"}
        "3 large cloves garlic, minced" → {"name":"garlic","amount":3,"unit":"large cloves","category":"Produce"}
        "1 lb medium shrimp (31-40 count), peeled and deveined" → {"name":"shrimp","amount":1,"unit":"pound","category":"Meat & Seafood"}
        "crispy shallots" → {"name":"crispy shallots","amount":1,"unit":"piece","category":"Produce"}
        "1/2 cup dry white wine" → {"name":"white wine","amount":0.5,"unit":"cup","category":"Beverages"}
        "1/4 cup fresh lemon juice" → {"name":"lemon juice","amount":0.25,"unit":"cup","category":"Produce"}

        Parse these ingredients:
        \(ingredientContent)
        """
    }
    
    private func callLLM(prompt: String) async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let url = URL(string: baseURL) else {
            throw LLMServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ API Error: \(errorString)")
            throw LLMServiceError.apiError
        }
        
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success,
              let content = jsonResponse["content"] as? String else {
            throw LLMServiceError.parsingError
        }
        
        // Log server metrics if available
        if let metrics = jsonResponse["metrics"] as? [String: Any] {
            if let apiCallTime = metrics["apiCallTime"] as? Int {
                print("⏱️ OpenAI API: \(apiCallTime)ms")
            }
            if let tokens = metrics["tokens"] as? Int {
                print("📊 Tokens: \(tokens)")
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Total API time: \(String(format: "%.2f", totalTime))s")
        
        return content
    }
    
    private func createRequestBody(prompt: String) -> [String: Any] {
        return ["prompt": prompt]
    }
    
    private func parseLLMResponse(_ response: String, originalURL: String, originalContent: String = "") -> RecipeParsingResult {
        // Parse the JSON response and convert to Recipe
        var recipe = Recipe(url: originalURL)
        
        do {
            // The response is already the raw LLM content (extracted from Vercel API response)
            
            // Clean up the JSON string
            var cleanedJsonString = response
            
            // Remove markdown code blocks if present (should be rare with new prompt)
            if cleanedJsonString.contains("```json") {
                if let startRange = cleanedJsonString.range(of: "```json"),
                   let endRange = cleanedJsonString.range(of: "```", range: startRange.upperBound..<cleanedJsonString.endIndex) {
                    cleanedJsonString = String(cleanedJsonString[startRange.upperBound..<endRange.lowerBound])
                }
            } else if cleanedJsonString.contains("```") {
                if let startRange = cleanedJsonString.range(of: "```"),
                   let endRange = cleanedJsonString.range(of: "```", range: startRange.upperBound..<cleanedJsonString.endIndex) {
                    cleanedJsonString = String(cleanedJsonString[startRange.upperBound..<endRange.lowerBound])
                }
            }
            
            // Additional cleanup for any remaining markdown artifacts
            cleanedJsonString = cleanedJsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If the string still starts with "```", try to find the actual JSON start
            if cleanedJsonString.hasPrefix("```") {
                if let jsonStart = cleanedJsonString.range(of: "{") {
                    cleanedJsonString = String(cleanedJsonString[jsonStart.lowerBound...])
                }
            }
            
            // Trim whitespace and newlines
            cleanedJsonString = cleanedJsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If it still doesn't start with '{', try to find the first '{'
            if !cleanedJsonString.hasPrefix("{") {
                if let braceIndex = cleanedJsonString.firstIndex(of: "{") {
                    cleanedJsonString = String(cleanedJsonString[braceIndex...])
                }
            }
            
            // Also ensure it ends with '}' and remove any trailing content
            if let lastBraceIndex = cleanedJsonString.lastIndex(of: "}") {
                cleanedJsonString = String(cleanedJsonString[...lastBraceIndex])
            }
            
            // Replace literal \n with actual newlines
            cleanedJsonString = cleanedJsonString.replacingOccurrences(of: "\\n", with: "\n")
            
            // Also replace other common escaped characters
            cleanedJsonString = cleanedJsonString.replacingOccurrences(of: "\\\"", with: "\"")
            cleanedJsonString = cleanedJsonString.replacingOccurrences(of: "\\t", with: "\t")
            
            // Convert fractions to decimal values for JSON parsing
            cleanedJsonString = convertFractionsToDecimals(cleanedJsonString)
            
            print("Extracted JSON string (first 50 chars): \(String(cleanedJsonString.prefix(50)))")
            print("JSON string starts with '{': \(cleanedJsonString.hasPrefix("{"))")
            print("JSON string length: \(cleanedJsonString.count)")
            print("Full JSON string: \(cleanedJsonString)")
            
            if let jsonData = cleanedJsonString.data(using: .utf8) {
                let recipeJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                guard let recipeJson = recipeJson else {
                    print("Failed to cast JSON to dictionary")
                    return RecipeParsingResult(recipe: recipe, success: false, error: "Invalid JSON structure")
                }
            
                recipe.name = recipeJson["recipeName"] as? String
                print("Recipe name: \(recipe.name ?? "nil")")
                
                if let ingredientsArray = recipeJson["ingredients"] as? [[String: Any]] {
                    var parsedIngredients: [Ingredient] = []
                    var validationErrors: [String] = []
                    
                    for (index, ingredientDict) in ingredientsArray.enumerated() {
                        guard let name = ingredientDict["name"] as? String,
                              let categoryString = ingredientDict["category"] as? String,
                              let category = GroceryCategory(rawValue: categoryString) else {
                            let error = "Failed to parse ingredient at index \(index): \(ingredientDict)"
                            print(error)
                            validationErrors.append(error)
                            continue
                        }
                        
                        // Process and standardize the ingredient
                        let ingredient = processAndStandardizeIngredient(
                            name: name,
                            amount: ingredientDict["amount"],
                            unit: ingredientDict["unit"],
                            category: category
                        )
                        
                        // Validate ingredient quality
                        let validationResult = validateIngredient(ingredient, originalContent: "")
                        if !validationResult.isValid {
                            validationErrors.append("Ingredient validation failed for '\(name)': \(validationResult.reason)")
                        }
                        
                        parsedIngredients.append(ingredient)
                        print("Parsed ingredient: \(ingredient.name) - \(ingredient.amount) \(ingredient.unit) (\(ingredient.category))")
                    }
                    
                    recipe.ingredients = sanitizeIngredientList(parsedIngredients)
                    print("Total ingredients parsed: \(recipe.ingredients.count)")
                    
                    // Check if we have enough ingredients (most recipes have 10-20 ingredients)
                    if recipe.ingredients.count < 8 {
                        print("⚠️ Warning: Only \(recipe.ingredients.count) ingredients found - this seems too few for a complete recipe")
                        validationErrors.append("Suspiciously low ingredient count (\(recipe.ingredients.count)) - may be missing ingredients")
                    }
                    
                    // Calculate confidence score
                    let confidenceScore = calculateConfidenceScore(ingredients: parsedIngredients, validationErrors: validationErrors)
                    print("Confidence score: \(confidenceScore)%")
                    
                    // Verify ingredients against original content
                    print("🔍 Verifying \(parsedIngredients.count) ingredients against content (length: \(originalContent.count))")
                    print("🔍 Content preview: \(String(originalContent.prefix(1000)))")
                    
                    // Remove hardcoded unrelated keyword checks; rely on general verification instead
                    
                    let verification = verifyIngredientsAgainstContent(parsedIngredients, originalContent: originalContent)
                    
                    // Only log verification details if there are issues
                    if verification.verificationScore < 80 {
                        print("⚠️ Verification score: \(verification.verificationScore)% (\(verification.verifiedIngredients.count)/\(parsedIngredients.count) ingredients verified)")
                        for note in verification.notes {
                            print("   \(note)")
                        }
                    }
                    
                    // If confidence is too low, return error
                    if confidenceScore < 70 {
                        return RecipeParsingResult(recipe: recipe, success: false, error: "Low confidence score (\(confidenceScore)%) - possible parsing errors")
                    }
                    
                    // If verification score is too low, reject the parsing
                    if verification.verificationScore < 30 {
                        print("❌ Rejecting parsing due to low verification score (\(verification.verificationScore)%) - ingredients don't match original content")
                        return RecipeParsingResult(recipe: recipe, success: false, error: "Low verification score (\(verification.verificationScore)%) - ingredients may be incorrect or generated rather than extracted")
                    } else if verification.verificationScore < 60 {
                        print("⚠️ Warning: Low verification score (\(verification.verificationScore)%) - some ingredients may be incorrect")
                    } else if verification.verificationScore < 80 {
                        print("⚠️ Warning: Moderate verification score (\(verification.verificationScore)%) - some ingredients may be incorrect")
                    }
                }
                
                recipe.isParsed = true
                return RecipeParsingResult(recipe: recipe, success: true, error: nil)
            }
        } catch {
            print("JSON parsing error: \(error)")
            return RecipeParsingResult(recipe: recipe, success: false, error: "Failed to parse LLM response: \(error.localizedDescription)")
        }
        
        return RecipeParsingResult(recipe: recipe, success: false, error: "Invalid response format")
    }
    
    // MARK: - Validation Methods
    
    private struct IngredientValidation {
        let isValid: Bool
        let reason: String
    }
    
    private func validateIngredient(_ ingredient: Ingredient, originalContent: String) -> IngredientValidation {
        // Check for common ingredient validation issues
        
        // 1. Check for empty or very short names
        if ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return IngredientValidation(isValid: false, reason: "Empty ingredient name")
        }
        
        if ingredient.name.count < 2 {
            return IngredientValidation(isValid: false, reason: "Ingredient name too short")
        }
        
        // 2. Check for common parsing errors
        let lowercasedName = ingredient.name.lowercased()
        let commonErrors = [
            "ingredient", "ingredients", "list", "item", "step", "direction", "instruction",
            "recipe", "cook", "prep", "total", "time", "serving", "servings"
        ]
        
        for error in commonErrors {
            if lowercasedName.contains(error) {
                return IngredientValidation(isValid: false, reason: "Ingredient name contains non-ingredient word: '\(error)'")
            }
        }
        
        // 3. Check for reasonable amounts (allow 0 when unit is "To taste" or unit is empty/omitted)
        let unitLowercased = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isToTasteUnit = unitLowercased == "to taste"
        if ingredient.amount <= 0 && !isToTasteUnit && !unitLowercased.isEmpty {
            return IngredientValidation(isValid: false, reason: "Invalid amount: \(ingredient.amount)")
        }
        
        if ingredient.amount > 1000 {
            return IngredientValidation(isValid: false, reason: "Unrealistic amount: \(ingredient.amount)")
        }
        
        // 4. Check for valid units
        let validUnits = [
            "cup", "cups", "tablespoon", "tablespoons", "teaspoon", "teaspoons",
            "ounce", "ounces", "pound", "pounds", "gram", "grams", "kilogram", "kilograms",
            "ml", "l", "g", "kg", "oz", "lb", "tbsp", "tsp",
            "small", "medium", "large", "clove", "cloves", "slice", "slices",
            "piece", "pieces", "can", "cans", "jar", "jars", "bottle", "bottles",
            "package", "packages", "bag", "bags", "bunch", "bunches", "head", "heads",
            "count", "to taste"
        ]
        
        if !unitLowercased.isEmpty {
            let hasValidUnit = validUnits.contains { validUnit in
                unitLowercased == validUnit
            }
            if !hasValidUnit {
                return IngredientValidation(isValid: false, reason: "Unrecognized unit: '\(ingredient.unit)'")
            }
        }
        
        return IngredientValidation(isValid: true, reason: "Valid ingredient")
    }
    
    private func calculateConfidenceScore(ingredients: [Ingredient], validationErrors: [String]) -> Int {
        var score = 100
        
        // Deduct points for validation errors
        score -= validationErrors.count * 10
        
        // Deduct points for too few ingredients (likely incomplete parsing)
        if ingredients.count < 3 {
            score -= 20
        }
        
        // Deduct points for too many ingredients (likely over-parsing)
        if ingredients.count > 50 {
            score -= 30
        }
        
        // Bonus points for reasonable ingredient count
        if ingredients.count >= 5 && ingredients.count <= 20 {
            score += 10
        }
        
        // Check for common ingredient patterns
        let ingredientNames = ingredients.map { $0.name.lowercased() }
        let commonIngredients = ["salt", "pepper", "oil", "water", "flour", "sugar", "egg", "milk", "butter"]
        let foundCommonIngredients = commonIngredients.filter { common in
            ingredientNames.contains { name in
                name.contains(common)
            }
        }
        
        // Bonus for finding common ingredients (indicates good parsing)
        if foundCommonIngredients.count >= 2 {
            score += 5
        }
        
        // Ensure score is within bounds
        return max(0, min(100, score))
    }
    
    private func verifyIngredientsAgainstContent(_ ingredients: [Ingredient], originalContent: String) -> IngredientVerification {
        var verifiedIngredients: [Ingredient] = []
        var unverifiedIngredients: [Ingredient] = []
        var verificationNotes: [String] = []
        
        let lowercasedContent = originalContent.lowercased()
        
        for ingredient in ingredients {
            let ingredientName = ingredient.name.lowercased()
            let amount = ingredient.amount
            let unit = ingredient.unit.lowercased()
            
            // Create search patterns for this ingredient
            let searchPatterns = [
                // Exact match with amount and unit
                "\(Int(amount)) \(unit) \(ingredientName)",
                "\(amount) \(unit) \(ingredientName)",
                "\(Int(amount)) \(ingredientName)",
                "\(amount) \(ingredientName)",
                
                // Common variations
                "\(ingredientName) \(amount) \(unit)",
                "\(ingredientName) \(Int(amount)) \(unit)",
                "\(ingredientName) \(amount)",
                "\(ingredientName) \(Int(amount))",
                
                // Handle fractions
                "\(ingredientName) \(amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(amount))",
                
                // Handle common abbreviations
                "\(ingredientName) \(amount) \(unit.replacingOccurrences(of: "tablespoon", with: "tbsp").replacingOccurrences(of: "teaspoon", with: "tsp"))",
                "\(ingredientName) \(amount) \(unit.replacingOccurrences(of: "ounce", with: "oz").replacingOccurrences(of: "pound", with: "lb"))",
                
                // Handle ingredients with preparation instructions
                "\(ingredientName), halved",
                "\(ingredientName), diced",
                "\(ingredientName), chopped",
                "\(ingredientName), finely chopped",
                "\(ingredientName), coarsely chopped",
                "\(ingredientName), thinly sliced",
                "\(ingredientName), minced",
                "\(ingredientName), grated",
                "\(ingredientName), shredded",
                "\(ingredientName), torn into small pieces",
                "\(ingredientName), cut into strips",
                "\(ingredientName), divided"
            ]
            
            var found = false
            for pattern in searchPatterns {
                if lowercasedContent.contains(pattern) {
                    verifiedIngredients.append(ingredient)
                    found = true
                    verificationNotes.append("✅ Verified '\(ingredient.name)' in content")
                    break
                }
            }
            
            // If exact match not found, try partial matching
            if !found {
                // Check if ingredient name appears in content
                if lowercasedContent.contains(ingredientName) {
                    // Check if there's a number near the ingredient name
                    let ingredientWords = ingredientName.components(separatedBy: .whitespaces)
                    for word in ingredientWords {
                        if word.count > 2 && lowercasedContent.contains(word) {
                            // Look for numbers near this word
                            let wordPattern = "\\b\\d+\\s*\(word)\\b"
                            if let regex = try? NSRegularExpression(pattern: wordPattern, options: [.caseInsensitive]) {
                                let matches = regex.matches(in: originalContent, options: [], range: NSRange(originalContent.startIndex..., in: originalContent))
                                if !matches.isEmpty {
                                    verifiedIngredients.append(ingredient)
                                    found = true
                                    verificationNotes.append("✅ Partially verified '\(ingredient.name)' in content")
                                    break
                                }
                            }
                        }
                    }
                }
            }
            
            // If still not found, try more flexible matching (but be more strict)
            if !found {
                // Split ingredient name into words and check if most words are present
                let ingredientWords = ingredientName.components(separatedBy: .whitespaces)
                let significantWords = ingredientWords.filter { $0.count > 2 }
                
                if significantWords.count > 0 {
                    let foundWords = significantWords.filter { word in
                        lowercasedContent.contains(word)
                    }
                    
                    // Require at least 50% of significant words for verification (more reasonable)
                    let matchRatio = Double(foundWords.count) / Double(significantWords.count)
                    if matchRatio >= 0.5 {
                        verifiedIngredients.append(ingredient)
                        found = true
                        verificationNotes.append("✅ Flexibly verified '\(ingredient.name)' (found \(foundWords.count)/\(significantWords.count) words)")
                    } else {
                        verificationNotes.append("❌ Insufficient word matches for '\(ingredient.name)' (found \(foundWords.count)/\(significantWords.count) words, need 75%)")
                    }
                }
            }
            
            if !found {
                unverifiedIngredients.append(ingredient)
                verificationNotes.append("❌ Could not verify '\(ingredient.name)' in content")
            }
        }
        
        let verificationScore = verifiedIngredients.count > 0 ? 
            (verifiedIngredients.count * 100) / ingredients.count : 0
        
        return IngredientVerification(
            verifiedIngredients: verifiedIngredients,
            unverifiedIngredients: unverifiedIngredients,
            verificationScore: verificationScore,
            notes: verificationNotes
        )
    }
    
    private struct IngredientVerification {
        let verifiedIngredients: [Ingredient]
        let unverifiedIngredients: [Ingredient]
        let verificationScore: Int
        let notes: [String]
    }
    
    // MARK: - Unit Standardization
    
    private func standardizeUnit(_ unit: String) -> String {
        let lowercasedUnit = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return unitMappings[lowercasedUnit] ?? lowercasedUnit
    }
    
    // Find the index of the first comma that is not inside parentheses
    private func firstTopLevelCommaIndex(in text: String) -> String.Index? {
        var depth = 0
        for i in text.indices {
            let ch = text[i]
            if ch == "(" { depth += 1 }
            else if ch == ")" { if depth > 0 { depth -= 1 } }
            else if ch == "," && depth == 0 { return i }
        }
        return nil
    }
    
    // MARK: - Final Sanitization (name-only enforcement)
    
    private func sanitizeIngredientList(_ ingredients: [Ingredient]) -> [Ingredient] {
        var result: [Ingredient] = []
        var seen: Set<String> = []
        for ing in ingredients {
            let sanitized = sanitizeIngredient(ing)
            // Robust dedup key: ignore trivial casing, stray leading adverbs, and unit punctuation differences
            let normalizedNameForKey: String = {
                var n = sanitized.name
                    .replacingOccurrences(of: "’", with: "'")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip leading adverb-only descriptors that sometimes leak into names
                n = n.replacingOccurrences(
                    of: #"(?i)^\s*(?:very\s+thinly|thinly|finely|roughly|coarsely)\b\s+"#,
                    with: "",
                    options: .regularExpression
                )
                return n.lowercased()
            }()
            let normalizedUnitForKey: String = {
                // Collapse whitespace and punctuation to make equivalent container-size units match
                let u = sanitized.unit.lowercased()
                // Remove spaces and common punctuation; keep letters/numbers
                return u.replacingOccurrences(of: #"[\s,_;:–\-]+"#, with: "", options: .regularExpression)
            }()
            let key = "\(normalizedNameForKey)|\(normalizedUnitForKey)|\(String(format: "%.4f", sanitized.amount))"
            if seen.contains(key) { continue }
            seen.insert(key)
            // Split salt and pepper combo if present
            let lower = sanitized.name.lowercased()
            if lower.contains("salt") && lower.contains("pepper") && lower.contains(" and ") {
                let salt = Ingredient(name: "salt", amount: 0.0, unit: "To taste", category: .pantry)
                let pepper = Ingredient(name: "black pepper", amount: 0.0, unit: "To taste", category: .pantry)
                if !result.contains(where: { $0.name.lowercased() == salt.name }) { result.append(salt) }
                if !result.contains(where: { $0.name.lowercased() == pepper.name }) { result.append(pepper) }
                continue
            }
            result.append(sanitized)
        }
        return result
    }

    // Removed post-LLM 'for serving' attachment to avoid duplication; handled centrally in processAndStandardizeIngredient
    
    private func sanitizeIngredient(_ ingredient: Ingredient) -> Ingredient {
		var name = ingredient.name
		var amount = ingredient.amount
		var unit = ingredient.unit
		let originalName = ingredient.name
        let originalCategory = ingredient.category
        let lowerName = name.lowercased()
        let lowerUnit = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Canonicalize select proper nouns early
        do {
            name = name.replacingOccurrences(of: "’", with: "'")
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"(?i)^'?\s*nduja\b"#, options: .regularExpression) != nil {
                name = "'Nduja"
            }
        }

        // A) Final guard: Avoid defaulting to "1 piece" for non-individual, non-produce items (e.g., cheeses)
        if (lowerUnit == "piece" || lowerUnit == "pieces") && amount == 1.0 {
            // Tokens that indicate truly countable items
            let individualTokens: [String] = ["egg", "eggs", "clove", "cloves", "sprig", "sprigs", "leaf", "leaves", "head", "heads", "bunch", "bunches"]
            let containerTokens: [String] = ["can", "cans", "jar", "jars", "bottle", "bottles", "package", "packages", "bag", "bags", "block", "wedge", "stick", "wheel"]
            let isIndividualByName = individualTokens.contains { lowerName.contains($0) }
            let hasContainerWord = containerTokens.contains { lowerName.contains($0) }
            let isProduce = (originalCategory == .produce)
            if !isIndividualByName && !hasContainerWord && !isProduce {
                amount = 0.0
                unit = ""
            }
        }
        
		// 0) Prefer grams only for salts (canonical amount)
		if originalName.lowercased().contains("salt") || name.lowercased().contains("salt") {
			if let gramsMatch = try? NSRegularExpression(pattern: "(?i)\\((?:[^)]*?)(\\d+(?:\\.\\d+)?)\\s*(?:g|grams)\\b[^^(]*\\)"),
			   let mm = gramsMatch.firstMatch(in: originalName, options: [], range: NSRange(originalName.startIndex..., in: originalName)),
			   mm.numberOfRanges >= 2,
			   let rr = Range(mm.range(at: 1), in: originalName),
			   let gramsVal = Double(String(originalName[rr])) {
				amount = gramsVal
				unit = "grams"
			}
		}

		// 1) Strip all parentheticals
        name = name.replacingOccurrences(of: #"\s*\([^)]*\)\s*"#, with: " ", options: .regularExpression)
        // Remove unmatched trailing parenthesis fragments (e.g., "name ( 6 ounces" → "name")
        name = name.replacingOccurrences(of: #"\s*\([^)]*$"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2) Remove leading amounts/units from name; keep them only in fields
        let leadingUnitPattern = #"(?i)^(?:[\d¼½¾/\.\-]+\s+)?(cups?|tablespoons?|tbsp|teaspoons?|tsp|ounces?|oz|pounds?|lb|lbs|grams?|g|milliliters?|ml|liters?|l(?![a-z])|slices?|cloves?|pieces?|balls?|buns?)\b\s*"#
        if let rx = try? NSRegularExpression(pattern: leadingUnitPattern) {
            let r = NSRange(name.startIndex..., in: name)
            if let m = rx.firstMatch(in: name, options: [], range: r), m.numberOfRanges >= 2,
               let ur = Range(m.range(at: 1), in: name) {
                // Extract the matched leading unit token
                let matchedToken = String(name[ur]).lowercased()
					// If the token is a single-letter "l" or "g" from the start of a word like
					// "large" or "garlic", do NOT interpret it as liters/grams. Require that the
					// character after the token is not a letter when the token length is 1.
					var shouldMoveUnit = true
					if matchedToken == "l" || matchedToken == "g" {
                    let afterIndex = ur.upperBound
                    if afterIndex < name.endIndex, name[afterIndex].isLetter {
                        shouldMoveUnit = false
                    }
                }

                if shouldMoveUnit {
                    // Always remove the leading unit token from the name
                    if let fullMatchRange = Range(m.range(at: 0), in: name) {
                        let sliceStart = fullMatchRange.upperBound
                        let slice = name[sliceStart..<name.endIndex]
                        name = String(slice)
                    }
                    // Set unit only if it wasn't already set
                    if unit.isEmpty { unit = standardizeUnit(matchedToken) }
                }
            }
        }

		// 2.2) If name begins with a container word like "can"/"cans" and unit is empty or a generic count unit, move it to unit
		if (unit.isEmpty || unit.lowercased() == "piece" || unit.lowercased() == "pieces") {
			if let m = try? NSRegularExpression(pattern: #"(?i)^\s*(can|cans)\s+(.+)$"#)
				.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)),
			   m.numberOfRanges >= 3,
			   let ur = Range(m.range(at: 1), in: name),
			   let nr = Range(m.range(at: 2), in: name) {
				unit = standardizeUnit(String(name[ur]))
				name = String(name[nr]).trimmingCharacters(in: .whitespaces)
			}
		}
        // Preserve previous narrow fix in final name: remove only a stray leading 's '
        name = name.replacingOccurrences(of: #"(?i)^\s*s\s+"#, with: "", options: .regularExpression)

		// 3.5) Combine any remaining plus-fragments and remove from name
		do {
			let plusPattern = "(?i)\\b(?:\\+|plus)\\s*(\\d+[\\d\\/\\s\\.]*)\\s*(cups?|tablespoons?|tbsp|teaspoons?|tsp)\\b"
			let rx = try NSRegularExpression(pattern: plusPattern)
			let rName = NSRange(name.startIndex..., in: name)
			let matches = rx.matches(in: name, options: [], range: rName)
			if !matches.isEmpty {
				func toTeaspoons(_ amt: Double, _ u: String) -> Double {
					switch u.lowercased() {
					case "teaspoon", "teaspoons", "tsp": return amt
					case "tablespoon", "tablespoons", "tbsp": return amt * 3.0
					case "cup", "cups": return amt * 48.0
					default: return 0
					}
				}
				if unit.lowercased() != "grams" { // only combine if not already using grams
					var totalTsp: Double
					switch unit.lowercased() {
					case "teaspoon", "teaspoons", "tsp": totalTsp = amount
					case "tablespoon", "tablespoons", "tbsp": totalTsp = amount * 3.0
					case "cup", "cups": totalTsp = amount * 48.0
					default: totalTsp = 0
					}
					for m in matches {
						if m.numberOfRanges >= 3,
						   let ar = Range(m.range(at: 1), in: name),
						   let ur = Range(m.range(at: 2), in: name) {
							let addAmount = parseAmount(String(name[ar]))
							let addUnit = String(name[ur])
							totalTsp += toTeaspoons(addAmount, addUnit)
						}
					}
					if totalTsp > 0 {
						if abs(totalTsp.rounded() - totalTsp) < 1e-6, Int(totalTsp) % 3 == 0 {
							amount = Double(Int(totalTsp) / 3)
							unit = "tablespoons"
						} else if abs(totalTsp - Double(Int(totalTsp))) < 1e-6 {
							amount = totalTsp
							unit = "teaspoons"
						} else {
							amount = roundToPlaces(totalTsp / 3.0, places: 2)
							unit = "tablespoons"
						}
					}
				}
				// remove all plus fragments from display name
				name = rx.stringByReplacingMatches(in: name, options: [], range: rName, withTemplate: "")
				name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
			}
		} catch {}
        
        // 3) Cut prep/tool tails after comma or dash if RHS contains prep keywords
        let tailSplitters = [",", "–", "-"]
        for splitter in tailSplitters {
            if let idx = name.firstIndex(of: Character(splitter)) {
                let rhs = name[name.index(after: idx)...]
                let rhsStr = String(rhs)
                if rhsStr.range(of: #"(?i)\b(grated|minced|chopped|sliced|peeled|seeded|soaked\s+in\s+cold\s+water|on\s+the\s+.*?box\s+grater|warmed?\s+on\s+(the\s+)?grill|cut\s+into\s+wedges|divided)\b"#, options: .regularExpression) != nil {
                    name = String(name[..<idx])
                }
            }
        }
        name = name.replacingOccurrences(of: #"(?i)\bon\s+the\s+.*?box\s+grater\b"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"(?i)\b(grated|minced|chopped|diced|sliced|peeled|seeded|soaked\s+in\s+cold\s+water|warmed?\s+on\s+(the\s+)?grill|divided)\b(?:\s+with\s+a\s+[^,;]+?grater)?"#, with: "", options: .regularExpression)
        
        // 4) Drop non-purchasable notes and stray unit letters that can leak (e.g., leading "l" in "large")
        name = name.replacingOccurrences(of: #"(?i)\b(optional|or\s+a\s+mix|see\s+note|to\s+taste|for\s+serving)\b"#, with: "", options: .regularExpression)
        // Remove a solitary leading single-letter unit like 'l ' or 'g ' ONLY when followed by a space and then a letter (e.g., "l arge", "g arlic")
        name = name.replacingOccurrences(of: #"^(?i)\s*(?:(?<unit>[lg])\s+(?=[A-Za-z]))"#, with: "", options: .regularExpression)
        
        // 5) Normalize containers → core noun; capture size like 2-inch as unit if unit empty
        if let sizeRange = name.range(of: #"(?i)\b(\d+(?:[\/\.]\d+)?-?inch)\b"#, options: .regularExpression) {
            if unit.isEmpty { unit = String(name[sizeRange]).lowercased() }
        }
        // If unit is piece(s), attach size descriptor from original text if present: "1-inch piece"
        if unit.lowercased().contains("piece") {
            if let sizeRange = originalName.range(of: #"(?i)\b(\d+(?:[\/\.]\d+)?-?inch)\b"#, options: .regularExpression) {
                let sizeText = String(originalName[sizeRange]).lowercased()
                if !unit.lowercased().contains(sizeText) {
                    unit = sizeText + " " + unit
                }
            }
        }
        // If name begins with optional size in parentheses then piece/pieces, move to unit and set amount if needed
        if let m = try? NSRegularExpression(pattern: #"(?i)^\s*(?:\(([^)]*)\)\s*)?(?:a|an|one)?\s*(piece|pieces)\s+(.+)$"#)
            .firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)),
           m.numberOfRanges >= 4,
           let sizeR = Range(m.range(at: 1), in: name),
           let ur = Range(m.range(at: 2), in: name),
           let nr = Range(m.range(at: 3), in: name) {
            let sizeInline = String(name[sizeR])
            let pieceUnit = String(name[ur]).lowercased()
            // Prefer inline size, else grab from original name if present
            if !sizeInline.isEmpty {
                unit = sizeInline.lowercased() + " " + (pieceUnit == "pieces" ? "pieces" : "piece")
            } else if let sizeRange = originalName.range(of: #"(?i)\b(\d+(?:[\/\.]\d+)?-?inch)\b"#, options: .regularExpression) {
                let sizeText = String(originalName[sizeRange]).lowercased()
                unit = sizeText + " " + (pieceUnit == "pieces" ? "pieces" : "piece")
            } else {
                unit = pieceUnit == "pieces" ? "pieces" : "piece"
            }
            name = String(name[nr])
            if amount <= 0 { amount = 1 }
        }
        if let rx = try? NSRegularExpression(pattern: #"(?i)^(?:a|an|one)?\s*(knob|piece|clove|head)\s+of\s+(.+)$"#),
           let m = rx.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)),
           m.numberOfRanges >= 3,
           let r2 = Range(m.range(at: 2), in: name) {
            name = String(name[r2])
        }
        // Also strip a leading "piece(s) " when present (no "of")
        if let rx = try? NSRegularExpression(pattern: #"(?i)^(?:a|an|one)?\s*(?:piece|pieces)\s+(.+)$"#),
           let m = rx.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)),
           m.numberOfRanges >= 2,
           let r2 = Range(m.range(at: 1), in: name) {
            name = String(name[r2])
        }
        
        // 6) Choose concrete example if "such as/like/e.g." present
        if let rx = try? NSRegularExpression(pattern: #"(?i)\b(?:such\s+as|like|e\.g\.)\b\s*([^,;]+)"#) {
            let r = NSRange(name.startIndex..., in: name)
            if let m = rx.firstMatch(in: name, options: [], range: r), m.numberOfRanges >= 2,
               let ex = Range(m.range(at: 1), in: name) {
                name = String(name[ex])
            }
        }
        
        // 7) Reduce to core noun phrase: trim adjectives like "fresh" and forms like "leaves"
        name = name.replacingOccurrences(of: #"(?i)^\s*(fresh|loosely\s+packed|small|medium|large)\s+"#, with: "", options: .regularExpression)
        // Brand normalization in final sanitize as well
        name = name.replacingOccurrences(of: #"(?i)\bdiamond\s+crystal\b"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"(?i)\bleaves\b"#, with: "", options: .regularExpression)
        
        // Punctuation and conjunction normalization
        // Normalize comma spacing: no space before, single space after
        name = name.replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression)
        // Lowercase standalone 'Or' between options
        name = name.replacingOccurrences(of: #"\bOr\b"#, with: "or", options: [.regularExpression])

        // Final tidy
        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

		// Herb-specific fix: strip a stray leading single-letter 's ' before common herb names (e.g., "s dill" → "dill")
		let herbList = ["dill","basil","parsley","cilantro","thyme","rosemary","sage","mint","tarragon","oregano","chives","scallion","scallions","green onion","green onions"]
		if let m = try? NSRegularExpression(pattern: #"(?i)^\s*s\s+([a-z].*)$"#)
			.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)),
		   m.numberOfRanges >= 2,
		   let r1 = Range(m.range(at: 1), in: name) {
			let rest = String(name[r1]).trimmingCharacters(in: .whitespaces)
			let firstWord = rest.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
			if herbList.contains(firstWord) {
				name = rest
			}
		}

        // FINAL GUARD: If name still begins with a container word (piece/clove/slice/head), move it to unit
        if let m = try? NSRegularExpression(pattern: #"(?i)^\s*(piece|pieces|clove|cloves|slice|slices|head|heads)\s+(.+)$"#)
            .firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)),
           m.numberOfRanges >= 3,
           let ur = Range(m.range(at: 1), in: name),
           let nr = Range(m.range(at: 2), in: name) {
            let container = String(name[ur]).lowercased()
            name = String(name[nr]).trimmingCharacters(in: .whitespaces)
            if unit.isEmpty {
                // Attach size if one was extracted earlier
                if let sizeRange = originalName.range(of: #"(?i)\b(\d+(?:[\/\.]\d+)?-?inch)\b"#, options: .regularExpression) {
                    let sizeText = String(originalName[sizeRange]).lowercased()
                    unit = sizeText + " " + (container == "pieces" ? "pieces" : "piece")
                } else {
                    unit = container
                }
            }
        }

        // Remove any stray leading single-letter token (e.g., "s strawberries")
        name = name.replacingOccurrences(of: #"(?i)^\s*[a-z]\s+(?=[a-z])"#, with: "", options: .regularExpression)
        
        // Singularize count-like units when amount is exactly 1 (preserve any leading size descriptor)
        if abs(amount - 1.0) < 0.0001 {
            let pluralToSingular: [String: String] = [
                "pieces": "piece",
                "cloves": "clove",
                "slices": "slice",
                "heads": "head",
                "bunches": "bunch",
                "cans": "can",
                "jars": "jar",
                "bottles": "bottle",
                "packages": "package",
                "containers": "container",
                "bags": "bag",
                "leaves": "leaf",
                "sprigs": "sprig"
            ]
            let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
            if !trimmedUnit.isEmpty {
                var parts = trimmedUnit.split(separator: " ").map(String.init)
                if let last = parts.last?.lowercased(), let singular = pluralToSingular[last] {
                    parts.removeLast()
                    parts.append(singular)
                    unit = parts.joined(separator: " ")
                }
            }
        }

        return Ingredient(name: name, amount: amount, unit: unit, category: ingredient.category)
    }

    // MARK: - Centralized Ingredient Processing
    
    private func processAndStandardizeIngredient(name: String, amount: Any?, unit: Any?, category: GroceryCategory) -> Ingredient {
        // 1. Clean and standardize the ingredient name
        var cleanedName = cleanIngredientName(name)
        // Preserve size descriptors (e.g., small/medium/large or 2-inch) as parenthetical
        if let sizeText = extractSizeDescriptor(from: name), !cleanedName.contains("(") {
            cleanedName = "\(cleanedName) (\(sizeText))"
        }
        
        // 2. Process and standardize the amount and unit
        var (standardizedAmount, standardizedUnit) = processAmountAndUnit(name: cleanedName, amount: amount, unit: unit)

        // 2.5 Apply rounding-up rule for countable produce (shopping practicality)
        let lcName = cleanedName.lowercased()
        let isProduce = validateAndAdjustCategory(cleanedName, originalCategory: category) == .produce
        let countUnits: Set<String> = ["", "piece", "pieces", "small", "medium", "large", "extra large", "heads", "head", "bunch", "bunches", "clove", "cloves", "sprig", "sprigs", "leaf", "leaves"]
        if isProduce && countUnits.contains(standardizedUnit.lowercased()) {
            if standardizedAmount > 0 && standardizedAmount < 1 {
                // e.g., 1/4 onion → 1 piece
                standardizedAmount = 1
                if standardizedUnit.isEmpty { standardizedUnit = "piece" }
            }
        }

        // 2.6 Prefer whole counts for certain produce even when given in weight (centralized for both paths)
        if isProduce {
            let weightUnits: Set<String> = ["ounces", "ounce", "grams", "gram", "g"]
            let isWeight = weightUnits.contains(standardizedUnit.lowercased())
            if isWeight {
                // Garlic: use heads (but do not override when explicitly "garlic cloves")
                if lcName.contains("garlic") && !lcName.contains("clove") {
                    standardizedAmount = 1
                    standardizedUnit = "head"
                }
                // Onions: prefer whole piece, but avoid green onions/scallions which are often measured differently
                else if lcName.contains("onion") && !lcName.contains("green onion") && !lcName.contains("scallion") {
                    standardizedAmount = 1
                    standardizedUnit = "piece"
                }
            }
        }
        
        // 2.7 Single-purpose rule: if the original description mentions "for serving" and we still have no explicit unit, set unit accordingly
        do {
            let rawLower = name.lowercased()
            if standardizedUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               rawLower.range(of: #"(?i)\bfor\s+serving\b"#, options: .regularExpression) != nil {
                standardizedUnit = "For serving"
                standardizedAmount = 0.0
                // Keep cleanedName free of the phrase; it was already removed by cleanIngredientName where applicable
            }
        }

        // 3. Validate and potentially adjust category based on cleaned name
        let validatedCategory = validateAndAdjustCategory(cleanedName, originalCategory: category)
        
        // 3.8 Harden: avoid implicit 1 piece for cheeses and similar pantry items without explicit quantity
        do {
            let lcName = cleanedName.lowercased()
            if (standardizedUnit.lowercased() == "piece" || standardizedUnit.lowercased() == "pieces") && standardizedAmount == 1.0 {
                let isCheese = lcName.contains("cheese") || lcName.contains("parmigiano") || lcName.contains("parmesan") || lcName.contains("pecorino")
                let isProduce = validateAndAdjustCategory(cleanedName, originalCategory: category) == .produce
                if isCheese && !isProduce {
                    standardizedUnit = ""
                    standardizedAmount = 0.0
                }
            }
        }

        // 4. Create the standardized ingredient with singularization when appropriate
        // Skip singularization when amount is zero (unknown) or unit is empty and not a count-like unit
        let shouldSingularize = standardizedAmount == 1 && !standardizedUnit.isEmpty
        let finalName = shouldSingularize ? singularizeNameIfNeeded(cleanedName, amount: standardizedAmount, unit: standardizedUnit) : cleanedName
        return Ingredient(name: finalName, amount: standardizedAmount, unit: standardizedUnit, category: validatedCategory)
    }

    // Extract size descriptor to keep in name as parenthetical
    private func extractSizeDescriptor(from raw: String) -> String? {
        let lower = raw.lowercased()
        // Common size words
        let sizeWords = ["small", "medium", "large"]
        if let word = sizeWords.first(where: { lower.contains($0) }) {
            return word
        }
        // Patterns like "2-inch", "1-inch", "2 inch"
        let inchPatterns = [
            #"\b(\d+(?:[\/\\.]\d+)?)\s*-\s*inch\b"#,
            #"\b(\d+(?:[\/\\.]\d+)?)\s+inch\b"#
        ]
        for pattern in inchPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: raw) {
                let val = String(raw[r]).trimmingCharacters(in: .whitespaces)
                return "\(val)-inch"
            }
        }
        return nil
    }

    // Singularize simple plural produce names when amount is 1 and unit is empty/piece
    private func singularizeNameIfNeeded(_ name: String, amount: Double, unit: String) -> String {
        guard amount == 1, unit.isEmpty || unit.lowercased() == "piece" else { return name }
        let lower = name.lowercased()
        // Do not singularize garlic cloves or items that are commonly plural-only
        if lower.contains("garlic clove") || lower.contains("garlic cloves") || lower.hasSuffix("chives") {
            return name
        }
        // Whitelist common plural -> singular mappings
        let mappings: [String: String] = [
            "onions": "onion",
            "tomatoes": "tomato",
            "potatoes": "potato",
            "peppers": "pepper",
            "shallots": "shallot",
            "carrots": "carrot",
            "lemons": "lemon",
            "limes": "lime",
            "cucumbers": "cucumber",
            "zucchinis": "zucchini",
            "eggplants": "eggplant",
            "mushrooms": "mushroom",
            "radishes": "radish"
        ]
        for (plural, singular) in mappings {
            if lower.hasSuffix(plural) {
                // Replace trailing plural token with singular
                if let range = name.range(of: plural, options: [.caseInsensitive, .backwards]) {
                    return name.replacingCharacters(in: range, with: singular)
                }
            }
        }
        // Generic fallback: drop a single trailing 's' when safe
        if lower.hasSuffix("s") && !lower.hasSuffix("ss") {
            return String(name.dropLast())
        }
        return name
    }
    
    private func processAmountAndUnit(name: String, amount: Any?, unit: Any?) -> (amount: Double, unit: String) {
        // Check if this is an individual fruit/vegetable that should use piece units
        let lowercasedName = name.lowercased()
        let individualItems: Set<String> = [
            "peppers", "bell peppers", "red bell peppers", "green bell peppers", "yellow bell peppers",
            "tomatoes", "grape tomatoes", "cherry tomatoes", "roma tomatoes",
            "avocados", "hass avocados", "bananas", "peaches", "oranges", "limes", "lemons",
            "apples", "pears", "plums", "nectarines", "mangoes", "pineapples",
            "cucumbers", "zucchinis", "eggplants", "squashes", "pumpkins",
            // Eggs
            "egg", "eggs", "egg yolk", "egg yolks", "yolk", "yolks"
        ]
        
        let isIndividualItem = individualItems.contains { lowercasedName.contains($0) }
        
        if isIndividualItem {
            // For individual items, try to extract quantity from the original description
            if let amountString = amount as? String {
                let numberPattern = "\\b(\\d+)\\b"
                if let range = amountString.range(of: numberPattern, options: .regularExpression),
                   let number = Double(String(amountString[range])) {
                    return (amount: number, unit: "piece")
                }
            }
        }
        
        // Default processing
        var standardizedAmount = processAndStandardizeAmount(amount)
        var standardizedUnit = processAndStandardizeUnit(unit)

        // If name includes a trailing ", for <use>" or similar and unit is empty or "piece(s)", drop the unit
        if standardizedUnit.isEmpty || standardizedUnit.lowercased() == "piece" || standardizedUnit.lowercased() == "pieces" {
            if lowercasedName.range(of: #"(?i),\s*for\s+[^,]+$"#, options: .regularExpression) != nil {
                standardizedUnit = ""
                // Do not force an amount of 1 in this specific pattern; leave amount as parsed
                if standardizedAmount == 1.0 {
                    standardizedAmount = 1.0 // keep amount but unit blank; consolidation logic will handle duplicates
                }
            }
        }

        // Heuristic: avoid defaulting to "1 piece" for non-individual, non-produce items when quantity isn't explicit
        if (standardizedUnit.lowercased() == "piece" || standardizedUnit.lowercased() == "pieces") && standardizedAmount == 1.0 {
            let isProduceCategory = validateAndAdjustCategory(name, originalCategory: .pantry) == .produce
        let individualItems: Set<String> = [
                "pepper", "bell pepper", "red bell pepper", "green bell pepper", "yellow bell pepper",
                "tomato", "grape tomato", "cherry tomato", "roma tomato",
                "avocado", "hass avocado", "banana", "peach", "orange", "lime", "lemon",
                "apple", "pear", "plum", "nectarine", "mango", "pineapple",
            "cucumber", "zucchini", "eggplant", "squash", "pumpkin",
                "clove", "cloves", "sprig", "sprigs", "leaf", "leaves"
            ,
            // Eggs
            "egg", "eggs", "egg yolk", "egg yolks", "yolk", "yolks"
            ]
            let isIndividual = individualItems.contains { lowercasedName.contains($0) }
            if !isProduceCategory && !isIndividual {
                standardizedUnit = ""
                // Leave amount at 0.0 if it was implicit; do not force 1
            }
        }

        // Seasoning override: when salt/pepper-type items lack an explicit measure, set "To taste"
        do {
            let lc = lowercasedName
            let isSalt = lc == "salt" || lc == "sea salt" || lc == "kosher salt" || lc == "table salt"
            let isBlackPepper = lc == "black pepper"
            let isWhitePepper = lc == "white pepper"
            let isPepperFlakes = lc == "red pepper flakes" || lc == "chili flakes" || lc == "chile flakes"
            if (isSalt || isBlackPepper || isWhitePepper || isPepperFlakes) {
                if standardizedAmount == 0.0 && (standardizedUnit.isEmpty || standardizedUnit.lowercased() == "piece" || standardizedUnit.lowercased() == "pieces") {
                    standardizedUnit = "To taste"
                    standardizedAmount = 0.0
                }
            }
        }

        return (amount: standardizedAmount, unit: standardizedUnit)
    }
    
    private func processAndStandardizeAmount(_ amount: Any?) -> Double {
        // Handle null/optional amount values
        let processedAmount: Double
        if let amountValue = amount as? Double {
            processedAmount = amountValue
        } else if let amountValue = amount as? Int {
            processedAmount = Double(amountValue)
        } else if let amountString = amount as? String {
            // Try to parse the string as a number
            if let parsedAmount = Double(amountString) {
                processedAmount = parsedAmount
            } else {
                // Check if it contains a number (e.g., "3 small red bell peppers")
                let numberPattern = "\\b(\\d+)\\b"
                if let range = amountString.range(of: numberPattern, options: .regularExpression),
                   let number = Double(String(amountString[range])) {
                    processedAmount = number
                } else {
                    // If it's not a number, default to 1
                    processedAmount = 1.0
                }
            }
        } else {
        // Default to 0 when no amount specified (will be upgraded by processing if appropriate)
        processedAmount = 0.0
        }
        
        // Standardize the amount (round to 2 decimal places for consistency)
        return round(processedAmount * 100) / 100
    }
    
    private func processAndStandardizeUnit(_ unit: Any?) -> String {
        // Handle null/optional unit values
        let processedUnit: String
        if let unitValue = unit as? String, !unitValue.isEmpty {
            processedUnit = unitValue
        } else {
            // Default to "piece" if no unit specified
            processedUnit = "piece"
        }
        
        // Handle special cases where we want to extract quantity from description
        let lowercasedUnit = processedUnit.lowercased()
        
        // Extract number from descriptions like "3 small red bell peppers"
        if lowercasedUnit.contains("small") || lowercasedUnit.contains("medium") || lowercasedUnit.contains("large") {
            // This will be handled in the amount processing
            return "piece"
        }
        
        // Handle "for greasing" or similar non-measurable units
        if lowercasedUnit.contains("greasing") || lowercasedUnit.contains("garnish") {
            return ""
        }
        
        // Handle individual fruit/vegetable quantities
        let individualItems: Set<String> = [
            "peppers", "bell peppers", "red bell peppers", "green bell peppers", "yellow bell peppers",
            "tomatoes", "grape tomatoes", "cherry tomatoes", "roma tomatoes",
            "avocados", "hass avocados", "bananas", "peaches", "oranges", "limes", "lemons",
            "apples", "pears", "plums", "nectarines", "mangoes", "pineapples",
            "cucumbers", "zucchinis", "eggplants", "squashes", "pumpkins"
        ]
        
        for item in individualItems {
            if lowercasedUnit.contains(item.lowercased()) {
                return "piece"
            }
        }
        
        // Standardize the unit using existing logic
        return standardizeUnit(processedUnit)
    }
    
    private func validateAndAdjustCategory(_ name: String, originalCategory: GroceryCategory) -> GroceryCategory {
        let lowercasedName = name.lowercased()
        
        // Check category overrides first (highest priority)
        for (keyword, category) in categoryOverrides {
            if lowercasedName.contains(keyword) {
                return category
            }
        }
        
        // Check if the ingredient name contains any category-specific keywords
        for (category, keywords) in categoryKeywords {
            for keyword in keywords {
                if lowercasedName.contains(keyword) {
                    return category
                }
            }
        }
        
        // Explicit pantry classification for stocks/broths (avoid beverage/meat misclassification)
        if lowercasedName.range(of: #"(?i)\b(chicken|beef|vegetable|veggie|turkey|bone)\s+(stock|broth)\b"#, options: .regularExpression) != nil {
            return .pantry
        }
        if lowercasedName.range(of: #"(?i)\b(stock|broth)\b"#, options: .regularExpression) != nil {
            return .pantry
        }

        // If no matching keywords found, return the original category
        return originalCategory
    }
    
    private func cleanIngredientName(_ name: String) -> String {
        var cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Decode a few common HTML entities and normalize curly quotes early
        if !cleanedName.isEmpty {
            cleanedName = cleanedName
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&rsquo;", with: "'")
                .replacingOccurrences(of: "&lsquo;", with: "'")
        }

        // Canonicalize proper nouns with leading apostrophes
        do {
            let normalizedApostrophes = cleanedName.replacingOccurrences(of: "’", with: "'")
            let trimmed = normalizedApostrophes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"(?i)^'?\s*nduja\b"#, options: .regularExpression) != nil {
                return "'Nduja"
            }
        }

        // Preserve canonical spice phrasing before generic cleanup
        // Map "crushed red pepper" → "red pepper flakes"
        let lcOriginal = cleanedName.lowercased()
        if lcOriginal.contains("crushed red pepper") {
            return "red pepper flakes"
        }

        // Normalize pepper synonyms → "black pepper" (but do not affect white pepper or chili/pepper flakes)
        do {
            let pepperSynonyms: Set<String> = [
                "pepper",
                "ground pepper",
                "freshly ground pepper",
                "black pepper",
                "ground black pepper",
                "freshly ground black pepper"
            ]
            if pepperSynonyms.contains(lcOriginal) {
                return "black pepper"
            }
        }

        // Normalize salt variants → "salt"
        do {
            // Look for salt variants, but do NOT mutate the original string unless it is salt
            // Also drop any semicolon note if present (e.g., "; for table salt, use half as much by volume")
            let candidate = cleanedName
                .replacingOccurrences(of: #"(?i)\s*;\s*for\s+table\s+salt.*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*;\s*.*$"#, with: "", options: .regularExpression)
            let lcSalt = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Collapse common salt descriptors and types to just "salt"
            if lcSalt.range(of: #"(?i)\b(?:fine|coarse|iodized|non-iodized|flake|flaky|maldon|fleur\s+de\s+sel)?\s*(?:sea|kosher|table)?\s*salt\b"#, options: .regularExpression) != nil,
               lcSalt.range(of: #"(?i)\bpepper\b"#, options: .regularExpression) == nil {
                return "salt"
            }
        }

        // Preserve meat/seafood descriptors: collapse comma-separated forms
        // e.g., "boneless, skinless chicken breasts" → "boneless skinless chicken breasts"
        do {
            // Normalize spacing/hyphens
            cleanedName = cleanedName.replacingOccurrences(of: #"(?i)\bbone\s+in\b"#, with: "bone-in", options: .regularExpression)
            cleanedName = cleanedName.replacingOccurrences(of: #"(?i)\bskin\s+on\b"#, with: "skin-on", options: .regularExpression)
            // Join comma-separated descriptors when stacked at the start or before the main noun
            cleanedName = cleanedName.replacingOccurrences(
                of: #"(?i)\b(boneless|bone-?in|skinless|skin-?on)\s*,\s*(?=(?:boneless|bone-?in|skinless|skin-?on)\b)"#,
                with: "$1 ",
                options: .regularExpression
            )
        }

        // Special handling for garlic cloves - preserve "cloves" in the name
        let initialLower = cleanedName.lowercased()
        if initialLower.contains("garlic") && initialLower.contains("cloves") {
            return "garlic cloves"
        }

        // 1) Remove parenthetical descriptors that contain preparation terms
        cleanedName = cleanedName.replacingOccurrences(
            of: #"\([^)]*(?:chopp|slice|dice|minc|grate|shred|julienn|zest|torn|cube|mash|pur(?:e|é)|whipp|beat|crush)[^)]*\)"#,
            with: "",
            options: .regularExpression
        )

        // 1.2) Remove common preparation tokens anywhere (not just at start/end)
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\b(drained|rinsed|patted\s+dry)\b"#,
            with: "",
            options: .regularExpression
        )

		// 1.3) Brand normalization: strip brand names
		let brandPatterns = [
			#"(?i)\bdiamond\s+crystal\b"#
		]
        for pattern in brandPatterns {
            cleanedName = cleanedName.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Second-chance salt collapse anywhere in the string (post brand cleanup)
        do {
            let lc = cleanedName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if lc.range(of: #"(?i)\b(?:sea|kosher|table)?\s*salt\b"#, options: .regularExpression) != nil,
               lc.range(of: #"(?i)\bpepper\b"#, options: .regularExpression) == nil {
                return "salt"
            }
        }

        // 2) Remove inline/trailed descriptors after comma, semicolon, en dash, or hyphen
        // Consume the entire clause up to the next comma/semicolon or end (e.g., "; thinly sliced ...", ", cleaned")
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)(?:,|;|–|-)\s*(?:finely|roughly|coarsely|thinly|thickly|lightly|well)?\s*(?:chopped|sliced|diced|minced|grated|shredded|torn|julienned|zested|cubed|mashed|pureed|whipped|beaten|crushed|halved|quartered|drained|rinsed|patted\s+dry|cleaned|deveined|shucked|scaled|gutted|trimmed)\b[^,;]*"#,
            with: "",
            options: .regularExpression
        )

        // Remove leftover directional tails like "horizontally to create 4 pieces"
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\bhorizontally\s+to\s+create\s+\d+\s+pieces\b"#,
            with: "",
            options: .regularExpression
        )

		// 3) Remove phrases like "torn into small pieces" or "cut into strips" (and bite-size variants)
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\b(?:torn\s+into\s+(?:small\s+)?bite[-\s]?size(?:d)?\s+pieces|torn\s+into\s+small\s+pieces|torn\s+into\s+pieces|cut\s+into\s+strips|into\s+(?:small\s+)?bite[-\s]?size(?:d)?\s+pieces|into\s+small\s+pieces|into\s+pieces)\b"#,
            with: "",
            options: .regularExpression
        )
        // Remove parenthetical counts and size totals specific to meat items
        // e.g., "(3 or 4 ounces each)" or "(1 1/2 pounds; 680 g total)"
        cleanedName = cleanedName.replacingOccurrences(
            of: #"\((?i)(?:\d+\s+or\s+\d+\s+ounces\s+each|\d+(?:[\/\.\s]\d+)?\s*(?:pounds?|lbs?)\s*;\s*\d+\s*g\s*total)\)"#,
            with: "",
            options: .regularExpression
        )
        // Remove generic parentheticals that contain weight/volume units (applies to produce too),
        // e.g., "(about 3/4 pound; 340 g)" or "(60 ml)"
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\([^)]*\b(?:pounds?|lbs?|ounces?|oz|grams?|g|kilograms?|kg|milliliters?|ml|liters?|l)\b[^)]*\)"#,
            with: "",
            options: .regularExpression
        )

		// 4) Remove leading descriptors such as "finely chopped " at the start (also remove cleanliness/state descriptors like cleaned/deveined)
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)^(?:finely|roughly|coarsely|thinly|thickly|lightly|well)?\s*(?:chopped|sliced|diced|minced|grated|shredded|torn|julienned|zested|cubed|mashed|pureed|whipped|beaten|crushed|halved|quartered|drained|rinsed|patted\s+dry|cleaned|deveined|shucked|scaled|gutted|trimmed)\s+"#,
            with: "",
            options: .regularExpression
        )
        // 4.1) Remove stray adverbs left at the beginning (e.g., "Finely", "Thinly")
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)^\s*(?:very\s+thinly|thinly|finely|roughly|coarsely)\b\s+"#,
            with: "",
            options: .regularExpression
        )
        // Normalize position of bone/skin descriptors if they were pushed away from the noun
        // e.g., "chicken breasts, boneless skinless" → "boneless skinless chicken breasts"
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)^\s*([^,]+?)\s*,\s*(boneless|bone-?in|skinless|skin-?on)(?:\s+(boneless|bone-?in|skinless|skin-?on))?\s*$"#,
            with: "$2 $3 $1",
            options: .regularExpression
        ).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        // Final punctuation/space cleanup after descriptor removals
        cleanedName = cleanedName
            .replacingOccurrences(of: #"^[\s,;:–-]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s,;:–-]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 3.2) If the ingredient contains an alternative with its own quantity after "or",
        // drop the second option entirely (e.g., "... or 8 chicken cutlets" → removed)
        // but keep flavor-style alternatives without quantities (e.g., "canola or vegetable oil").
        do {
            let altWithQtyPattern = #"(?i)\s+or\s+(?:(?:about\s+)?(?:\d+(?:[\/\.\s]\d+)?|\d+\s*-\s*\d+|one|two|three|four|five|six|seven|eight|nine|ten|a|an|[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]))\b.*$"#
            if let rx = try? NSRegularExpression(pattern: altWithQtyPattern) {
                cleanedName = rx.stringByReplacingMatches(in: cleanedName, options: [], range: NSRange(cleanedName.startIndex..., in: cleanedName), withTemplate: "")
                cleanedName = cleanedName.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 4.5) Normalize generic containers like "knob of ginger" → "ginger"; also drop leading container words
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)^(?:a|an|one)?\s*(knob|piece|pieces|slice|slices|clove|cloves|head|heads|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches)\s+of\s+"#,
            with: "",
            options: .regularExpression
        )
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)^\s*(?:knob|piece|pieces|slice|slices|clove|cloves|head|heads|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches)\s+"#,
            with: "",
            options: .regularExpression
        )

		// 4.7) Remove packing density descriptors (e.g., "loosely packed", "lightly packed", "tightly packed")
		cleanedName = cleanedName.replacingOccurrences(
			of: #"(?i)\b(?:loosely|lightly|tightly)\s+packed\b"#,
			with: "",
			options: .regularExpression
		)

        // 5) Normalize common herb phrasing
        // Remove trailing "leaves" for herbs (e.g., "parsley leaves" → "parsley")
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\bflat[ -]leaf\s+parsley\s+leaves?\b"#,
            with: "flat-leaf parsley",
            options: .regularExpression
        )
		cleanedName = cleanedName.replacingOccurrences(
			of: #"(?i)\b(basil|parsley|cilantro|coriander|mint|sage|thyme|rosemary|dill|tarragon|oregano|chives|scallions?|green onion(?:s)?)\s+leaves?\b"#,
			with: "$1",
			options: .regularExpression
		)

		// Herb plant-part descriptors: collapse variants like "leaves and tender stems" or "and stems" to base herb
		do {
			let herbAlternatives = #"(?:flat[ -]leaf\s+parsley|basil|parsley|cilantro|coriander|mint|sage|thyme|rosemary|dill|tarragon|oregano|chives|scallions?|green onion(?:s)?)"#
			// e.g., "parsley leaves and tender stems" → "parsley"
			cleanedName = cleanedName.replacingOccurrences(
				of: #"(?i)\b(\#(herbAlternatives))\b\s+leaves?\s+and\s+(?:tender\s+)?stems\b"#,
				with: "$1",
				options: .regularExpression
			)
			// e.g., "parsley and tender stems" → "parsley"
			cleanedName = cleanedName.replacingOccurrences(
				of: #"(?i)\b(\#(herbAlternatives))\b\s+and\s+(?:tender\s+)?stems\b"#,
				with: "$1",
				options: .regularExpression
			)
			// Optional convenience: "scallion tops"/"green onion tops" → base herb
			cleanedName = cleanedName.replacingOccurrences(
				of: #"(?i)\b(scallions?|green onion(?:s)?)\s+tops\b"#,
				with: "$1",
				options: .regularExpression
			)
		}

        // 6) Ensure 'fresh' is preserved but not duplicated and appears at the start when present
        if cleanedName.range(of: #"(?i)\bfresh\b"#, options: .regularExpression) != nil {
            // remove all 'fresh' occurrences first
            cleanedName = cleanedName.replacingOccurrences(of: #"(?i)\bfresh\b"#, with: "", options: .regularExpression)
            cleanedName = cleanedName.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            cleanedName = cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanedName = cleanedName.isEmpty ? "fresh" : "fresh " + cleanedName
        }

        // 6.1) Ensure 'frozen' is preserved and appears at the start when present
        if cleanedName.range(of: #"(?i)\bfrozen\b"#, options: .regularExpression) != nil {
            // remove all 'frozen' occurrences first
            cleanedName = cleanedName.replacingOccurrences(of: #"(?i)\bfrozen\b"#, with: "", options: .regularExpression)
            cleanedName = cleanedName.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            cleanedName = cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanedName = cleanedName.isEmpty ? "frozen" : "frozen " + cleanedName
        }

        // 6.2) Remove quality/season descriptors like "ripe", "best-quality", "summer", "peak-season"
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\b(best(?:-|\s*)quality|high(?:-|\s*)quality|peak(?:-|\s*)season|in(?:-|\s*)season|summer|ripe)\b"#,
            with: "",
            options: .regularExpression
        )

        // Preserve canonical capitalization for select proper nouns
        do {
            let test = cleanedName.replacingOccurrences(of: "’", with: "'")
            if test.range(of: #"(?i)^'?\s*nduja\b"#, options: .regularExpression) != nil {
                cleanedName = "'Nduja"
            }
        }

        // 7) Remove common trailing notes and dangling punctuation (e.g., "divided; for dressing", "plus more", etc.)
        cleanedName = cleanedName.replacingOccurrences(
            of: #"(?i)\s*(?:,|;|:)\s*(?:divided|for\s+serving|for\s+garnish|for\s+the\s+.+|to\s+taste|as\s+needed|plus\s+more|plus\s+extra|or\s+.+)\s*$"#,
            with: "",
            options: .regularExpression
        )
        cleanedName = cleanedName.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        cleanedName = cleanedName.replacingOccurrences(of: #"\s*(?:,|;|:|\-|–)\s*$"#, with: "", options: .regularExpression)

        // 7.2) Remove stray leading single-letter leftovers like 's ' that can leak (e.g., 's dill', 's diced strawberries')
        // Drop any solitary leading single-letter token rather than merging it with the next word.
        cleanedName = cleanedName.replacingOccurrences(of: #"(?i)^\s*[a-z]\s+"#, with: "", options: .regularExpression)

        // Fallback: remove single preparation words only at the very start or end (but preserve important descriptors)
        var changed = true
        while changed {
            changed = false
            let lowercased = cleanedName.lowercased()

            // Beginning
            if let word = preparationWords.first(where: { !preservedWords.contains($0) && lowercased.range(of: "^\\s*\\b\($0)\\b\\s+", options: .regularExpression) != nil }) {
                if let range = lowercased.range(of: "^\\s*\\b\(word)\\b\\s+", options: .regularExpression) {
                    cleanedName = String(cleanedName[range.upperBound...])
                    changed = true
                    continue
                }
            }

            // End
            if let word = preparationWords.first(where: { !preservedWords.contains($0) && lowercased.range(of: "\\s+\\b\($0)\\b\\s*$", options: .regularExpression) != nil }) {
                if let range = lowercased.range(of: "\\s+\\b\(word)\\b\\s*$", options: .regularExpression) {
                    cleanedName = String(cleanedName[..<range.lowerBound])
                    changed = true
                    continue
                }
            }
        }

        cleanedName = cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 8.2) Remove trailing thin/thick/fine/coarse descriptors that can leak from phrases like "sliced thin"
        cleanedName = cleanedName.replacingOccurrences(
            of: #"\s+\b(thin|thick|fine|coarse|finely|coarsely|roughly)\b\s*$"#,
            with: "",
            options: .regularExpression
        )

        // 8.5) Fallback: if cleaning removed everything, salvage the last alphabetic word from the original
        if cleanedName.isEmpty {
            if let rx = try? NSRegularExpression(pattern: #"(?i)([A-Za-z][A-Za-z\-]+)\s*$"#) {
                let r = NSRange(name.startIndex..., in: name)
                if let m = rx.firstMatch(in: name, options: [], range: r), m.numberOfRanges >= 2,
                   let rr = Range(m.range(at: 1), in: name) {
                    let candidate = String(name[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !preparationWords.contains(candidate.lowercased()) {
                        cleanedName = candidate
                    }
                }
            }
        }

        // 8) Lowercase coordinating conjunctions and prepositions inside the phrase (e.g., "Cream or Heavy Cream")
        // Do not alter leading word casing.
        let lowercaseTokens: Set<String> = ["and", "or", "of", "with", "in", "on", "for", "to", "from"]
        let parts = cleanedName.split(separator: " ", omittingEmptySubsequences: false)
        if parts.count > 1 {
            var rebuilt: [String] = []
            for (idx, p) in parts.enumerated() {
                let token = String(p)
                if idx > 0 && lowercaseTokens.contains(token.lowercased()) {
                    rebuilt.append(token.lowercased())
                } else {
                    rebuilt.append(token)
                }
            }
            cleanedName = rebuilt.joined(separator: " ")
        }

        return cleanedName.isEmpty ? name : cleanedName
    }
    
    private func convertToStandardUnits(amount: Double, unit: String) -> (amount: Double, unit: String) {
        let lowercasedUnit = unit.lowercased()
        
        // Convert metric to imperial if needed (you can customize this based on user preferences)
        switch lowercasedUnit {
        case "grams", "g":
            if amount >= 1000 {
                return (amount / 1000, "kilograms")
            }
        case "milliliters", "ml":
            if amount >= 1000 {
                return (amount / 1000, "liters")
            }
        default:
            break
        }
        
        return (amount, unit)
    }
    
    private func extractIngredientSection(from content: String) -> String {
        // Strip obvious HTML, CSS, JS blocks to reduce leakage before any parsing
        var text = content
        // Remove script and style blocks entirely
        text = text.replacingOccurrences(of: #"(?is)<script[^>]*>[\s\S]*?</script>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<style[^>]*>[\s\S]*?</style>"#, with: "\n", options: .regularExpression)
        // Remove head and noscript blocks
        text = text.replacingOccurrences(of: #"(?is)<head[^>]*>[\s\S]*?</head>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<noscript[^>]*>[\s\S]*?</noscript>"#, with: "\n", options: .regularExpression)
        // Remove common meta/link tags
        text = text.replacingOccurrences(of: #"(?is)<meta[^>]*>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<link[^>]*>"#, with: "\n", options: .regularExpression)
        // Strip remaining tags to plain text skeleton
        text = text.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "\n", options: .regularExpression)
        // Collapse excessive whitespace
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text
    }
    
    // MARK: - Semantic Recipe Extraction Methods
    
    private func findRecipeSection(in content: String) -> String? {
        // Look for recipe-specific semantic markers
        let recipeMarkers = [
            "Recipe Details",
            "Ingredients",
            "Directions", 
            "Instructions",
            "Method",
            "Prep",
            "Cook",
            "Total"
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var recipeLines: [String] = []
        var inRecipeSection = false
        var consecutiveRecipeLines = 0
        
        print("🔍 Searching for recipe markers in \(lines.count) lines")
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let lowercasedLine = trimmedLine.lowercased()
            
            // Check if this line indicates start of recipe section
            for marker in recipeMarkers {
                if lowercasedLine.contains(marker.lowercased()) {
                    print("🎯 Found recipe marker '\(marker)' at line \(index): '\(trimmedLine)'")
                    inRecipeSection = true
                    consecutiveRecipeLines = 0
                    recipeLines.append(line)
                    break
                }
            }
            
            if inRecipeSection {
                // Look for measurement patterns that indicate ingredients
                if hasMeasurementPattern(trimmedLine) {
                    recipeLines.append(line)
                    consecutiveRecipeLines += 1
                } else if lowercasedLine.contains("ingredient") || 
                          lowercasedLine.contains("direction") ||
                          lowercasedLine.contains("instruction") ||
                          lowercasedLine.contains("step") {
                    recipeLines.append(line)
                    consecutiveRecipeLines += 1
                } else if consecutiveRecipeLines > 0 {
                    // Continue adding lines if we're in a recipe section
                    recipeLines.append(line)
                    consecutiveRecipeLines += 1
                }
                
                // Stop if we hit content that looks like the end of recipe
                if lowercasedLine.contains("nutrition") ||
                   lowercasedLine.contains("calories") ||
                   lowercasedLine.contains("serving") ||
                   lowercasedLine.contains("special equipment") ||
                   consecutiveRecipeLines > 30 {
                    break
                }
            }
        }
        
        if recipeLines.count > 5 {
            return recipeLines.joined(separator: "\n")
        }
        
        return nil
    }

    // MARK: - Non-recipe page detection
    private func isLikelyRecipePage(urlString: String, html: String) -> Bool {
        // 1) Domain heuristics
        if let host = URL(string: urlString)?.host?.lowercased() {
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if nonRecipeDomainDenyList.contains(bare) {
                return false
            }
            // Allow list is advisory; do not strictly require it
        }

        let lower = html.lowercased()
        // 2) Look for strong recipe markers
        let hasRecipeSchema = (lower.range(of: #""@type"\s*:\s*"recipe""#, options: .regularExpression) != nil)
            || lower.contains("itemtype=\"http://schema.org/recipe\"")
        let hasIngredientMarkers = lower.contains(">ingredients<") || lower.contains("ingredients:") || lower.contains("ingredient list")
        let hasInstructionMarkers = lower.contains(">instructions<") || lower.contains("directions:") || lower.contains("method:")
        let hasCookMeta = lower.contains("prep time") || lower.contains("cook time") || lower.contains("total time") || lower.contains("servings")

        let strongSignals = hasRecipeSchema || (hasIngredientMarkers && hasInstructionMarkers) || (hasIngredientMarkers && hasCookMeta)
        if strongSignals { return true }

        // 3) Weak heuristic: presence of multiple list items near an ingredient heading
        if let rx = try? NSRegularExpression(pattern: "(?is)ingredients.{0,1200}(<li[^>]*>.*?</li>){3,}") {
            if rx.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) != nil {
                return true
            }
        }

        // 4) Negative signals: news/sports/video heavy pages
        let negativeTokens = ["scoreboard", "subscribe", "live updates", "highlights", "analysis", "breaking news", "video player"]
        if negativeTokens.contains(where: { lower.contains($0) }) {
            return false
        }

        // Default: unsure → treat as non-recipe to avoid leakage
        return false
    }
    
    private func extractStructuredIngredients(from content: String) -> String? {
        // Look for HTML-like structured data or bullet point patterns
        let lines = content.components(separatedBy: .newlines)
        var ingredientLines: [String] = []
        var inIngredientSection = false
        var foundIngredients = false
        
        print("🔍 Looking for structured ingredients in \(lines.count) lines")
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let lowercasedLine = trimmedLine.lowercased()
            
            // Check for ingredient section markers (human-like pattern recognition)
            if (lowercasedLine.contains("ingredients") || lowercasedLine.contains("ingredient list")) && 
               (lowercasedLine.contains(":") || lowercasedLine.contains("*") || lowercasedLine.contains("•")) {
                inIngredientSection = true
                foundIngredients = true
                print("🎯 Found ingredient section marker at line \(index): '\(trimmedLine)'")
                continue
            }
            
            // Look for "For the [recipe name]:" pattern
            if lowercasedLine.contains("for the") && lowercasedLine.contains(":") {
                inIngredientSection = true
                foundIngredients = true
                print("🎯 Found 'For the' pattern at line \(index): '\(trimmedLine)'")
                continue
            }
            
            // Look for "You'll need:" or "What you need:" patterns
            if lowercasedLine.contains("you'll need") || lowercasedLine.contains("what you need") {
                inIngredientSection = true
                foundIngredients = true
                print("🎯 Found 'You'll need' pattern at line \(index): '\(trimmedLine)'")
                continue
            }
            
            // Also look for JSON-like structured data
            if lowercasedLine.contains("\"ingredients\"") || lowercasedLine.contains("\"ingredient\"") {
                inIngredientSection = true
                foundIngredients = true
                print("🎯 Found JSON ingredient marker at line \(index): '\(trimmedLine)'")
                continue
            }
            
            if inIngredientSection {
                // Look for bullet points or measurement patterns (human-like recognition)
                if trimmedLine.hasPrefix("*") || 
                   trimmedLine.hasPrefix("-") || 
                   trimmedLine.hasPrefix("•") ||
                   hasMeasurementPattern(trimmedLine) ||
                   isLikelyIngredientLine(trimmedLine) {
                    ingredientLines.append(line)
                    print("📏 Found ingredient line: '\(trimmedLine)'")
                } else if lowercasedLine.contains("direction") ||
                          lowercasedLine.contains("instruction") ||
                          lowercasedLine.contains("step") ||
                          lowercasedLine.contains("method") ||
                          lowercasedLine.contains("preparation") ||
                          lowercasedLine.contains("cooking") {
                    // Stop at directions/instructions (human-like boundary detection)
                    print("🛑 Stopping at directions/instructions")
                    break
                } else if foundIngredients && ingredientLines.count > 0 {
                    // Continue adding lines if we're in an ingredient section and have found some ingredients
                    ingredientLines.append(line)
                }
            }
        }
        
        // If we didn't find structured ingredients, try to extract from JSON-like content
        if ingredientLines.count < 2 {
            print("🔍 Looking for JSON-like ingredient data")
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty && 
                   (trimmedLine.contains("ounce") || trimmedLine.contains("cup") || trimmedLine.contains("tablespoon") || 
                    trimmedLine.contains("pound") || trimmedLine.contains("gram") || trimmedLine.contains("clove")) {
                    ingredientLines.append(line)
                    print("📏 Found JSON ingredient: '\(trimmedLine)'")
                }
            }
        }
        
        if ingredientLines.count >= 2 {
            let result = ingredientLines.joined(separator: "\n")
            print("✅ Found \(ingredientLines.count) structured ingredient lines")
            return result
        }
        
        return nil
    }
    
    private func findRecipeContent(in content: String) -> String? {
        // Look for recipe-specific sections in the full content
        let recipeKeywords = [
            "ingredients", "directions", "instructions", "method", "prep", "cook", "total",
            "recipe details", "you'll need", "what you need", "for the", "serves"
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var recipeLines: [String] = []
        var inRecipeSection = false
        var consecutiveRecipeLines = 0
        var ingredientCount = 0
        
        print("🔍 Searching for recipe content in \(lines.count) lines")
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let lowercasedLine = trimmedLine.lowercased()
            
            // Skip obvious CSS/JS content early
            if lowercasedLine.contains("display:") || 
               lowercasedLine.contains("width:") || 
               lowercasedLine.contains("function") ||
               lowercasedLine.contains("var(--") ||
               lowercasedLine.contains("!important") {
                continue
            }
            
            // Check if this line indicates start of recipe section
            for keyword in recipeKeywords {
                if lowercasedLine.contains(keyword) {
                    print("🎯 Found recipe keyword '\(keyword)' at line \(index): '\(trimmedLine)'")
                    inRecipeSection = true
                    consecutiveRecipeLines = 0
                    recipeLines.append(line)
                    break
                }
            }
            
            if inRecipeSection {
                // Look for measurement patterns that indicate ingredients
                if hasMeasurementPattern(trimmedLine) {
                    recipeLines.append(line)
                    consecutiveRecipeLines += 1
                    ingredientCount += 1
                    print("📏 Found ingredient with measurement: '\(trimmedLine)'")
                } else if lowercasedLine.contains("ingredient") || 
                          lowercasedLine.contains("direction") ||
                          lowercasedLine.contains("instruction") ||
                          lowercasedLine.contains("step") ||
                          lowercasedLine.contains("serving") {
                    recipeLines.append(line)
                    consecutiveRecipeLines += 1
                } else if consecutiveRecipeLines > 0 {
                    // Continue adding lines if we're in a recipe section
                    recipeLines.append(line)
                    consecutiveRecipeLines += 1
                }
                
                // Stop if we hit content that looks like the end of recipe
                if lowercasedLine.contains("nutrition") ||
                   lowercasedLine.contains("calories") ||
                   lowercasedLine.contains("special equipment") ||
                   consecutiveRecipeLines > 50 {
                    break
                }
            }
        }
        
        if recipeLines.count > 10 && ingredientCount > 0 {
            let result = recipeLines.joined(separator: "\n")
            print("✅ Found \(recipeLines.count) recipe lines with \(ingredientCount) ingredients")
            return result
        }
        
        return nil
    }
    
    private func extractIngredientList(from content: String) -> String? {
        // Look specifically for ingredient lists with measurements
        let lines = content.components(separatedBy: .newlines)
        var ingredientLines: [String] = []
        var inIngredientSection = false
        var consecutiveIngredientLines = 0
        
        print("🔍 Looking for ingredient list with measurements")
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let lowercasedLine = trimmedLine.lowercased()
            
            // Check for ingredient section markers (more comprehensive)
            if lowercasedLine.contains("ingredients") || 
               lowercasedLine.contains("ingredient list") ||
               lowercasedLine.contains("you'll need") ||
               lowercasedLine.contains("what you need") ||
               lowercasedLine.contains("for the") ||
               lowercasedLine.contains("ingredients:") ||
               lowercasedLine.contains("ingredient:") {
                inIngredientSection = true
                print("🎯 Found ingredient section marker at line \(index): '\(trimmedLine)'")
                continue
            }
            
            if inIngredientSection {
                // Look for lines that contain measurements
                if hasMeasurementPattern(trimmedLine) {
                    ingredientLines.append(line)
                    consecutiveIngredientLines += 1
                    print("📏 Found ingredient with measurement: '\(trimmedLine)'")
                } else if lowercasedLine.contains("direction") ||
                          lowercasedLine.contains("instruction") ||
                          lowercasedLine.contains("step") ||
                          lowercasedLine.contains("method") ||
                          lowercasedLine.contains("preparation") ||
                          lowercasedLine.contains("cooking") {
                    // Stop at directions/instructions
                    print("🛑 Stopping at directions/instructions")
                    break
                } else if consecutiveIngredientLines > 0 {
                    // Continue adding lines if we're in an ingredient section
                    ingredientLines.append(line)
                    consecutiveIngredientLines += 1
                }
                
                // Stop if we hit content that looks like the end of ingredients
                if lowercasedLine.contains("nutrition") ||
                   lowercasedLine.contains("calories") ||
                   lowercasedLine.contains("serving") ||
                   lowercasedLine.contains("total time") ||
                   lowercasedLine.contains("prep time") ||
                   lowercasedLine.contains("cook time") ||
                   consecutiveIngredientLines > 50 {
                    break
                }
            }
        }
        
        // Also look for standalone ingredient lines with measurements throughout the content
        if ingredientLines.count < 3 {
            print("🔍 Looking for standalone ingredient lines with measurements")
            for (_, line) in lines.enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty && (hasMeasurementPattern(trimmedLine) || isLikelyIngredientLine(trimmedLine)) {
                    ingredientLines.append(line)
                    print("📏 Found standalone ingredient: '\(trimmedLine)'")
                }
            }
        }
        
        // If still not enough ingredients, do a more aggressive search throughout the content
        if ingredientLines.count < 5 {
            print("🔍 Doing aggressive ingredient search throughout content")
            for (_, line) in lines.enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty && isLikelyIngredientLine(trimmedLine) {
                    ingredientLines.append(line)
                    print("📏 Found ingredient in aggressive search: '\(trimmedLine)'")
                }
            }
        }
        
        if ingredientLines.count >= 2 {
            let result = ingredientLines.joined(separator: "\n")
            print("✅ Found \(ingredientLines.count) ingredient lines")
            return result
        }
        
        return nil
    }
    
    private func hasMeasurementPattern(_ line: String) -> Bool {
        // First, check if this line contains CSS or other non-recipe content
        let lowercasedLine = line.lowercased()
        
        // CSS keywords that should be rejected
        let cssKeywords = [
            "display:", "width:", "height:", "position:", "border:", "padding:", "margin:",
            "background:", "color:", "font:", "text-align:", "float:", "clear:", "overflow:",
            "z-index:", "opacity:", "visibility:", "box-shadow:", "border-radius:",
            "flex:", "grid:", "transform:", "transition:", "animation:",
            "var(--", "!important", "@media", "@keyframes", "@import", "@font-face",
            "body{", "html{", "div{", "span{", "p{", "h1{", "h2{", "h3{", "h4{", "h5{", "h6{",
            ".is-hidden", ".visually-hidden", ".img--noscript", ".primary-img--noscript",
            ".no-js", ".mntl-", ".lazyload", "img[src=", "rem", "px", "em", "vh", "vw", "%"
        ]
        
        // Check if this line contains CSS content
        for keyword in cssKeywords {
            if lowercasedLine.contains(keyword.lowercased()) {
                return false // Reject CSS content
            }
        }
        
        // Special CSS detection patterns
        if (lowercasedLine.contains(".") && lowercasedLine.contains("{")) ||
           (lowercasedLine.contains("display:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("width:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("height:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("position:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("background:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("color:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("font:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("border:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("padding:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("margin:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("!important") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("var(--") && lowercasedLine.contains(")")) ||
           (lowercasedLine.contains("overflow:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("z-index:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("opacity:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("visibility:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("box-shadow:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("border-radius:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("flex:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("grid:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("transform:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("transition:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("animation:") && lowercasedLine.contains(";")) {
            return false // Reject CSS content
        }
        
        // Look for common measurement patterns (like how I quickly identify ingredients)
        let measurementPatterns = [
            "\\b\\d+\\s*(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|ounce|ounces|pound|pounds|gram|grams|ml|l|g|kg|oz|lb|tbsp|tsp)\\b",
            "\\b\\d+\\s*\\([^)]*\\)\\b", // Patterns like "2 ounces (55 ml)"
            "\\b\\d+\\s*to\\s*\\d+\\s*(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons)\\b", // Ranges like "2 to 3 tablespoons"
            "\\b\\d+\\s*(small|large|medium)\\b", // Patterns like "3 small red bell peppers"
            "\\b\\d+\\s*(cloves|slices|pieces)\\b", // Patterns like "5 medium cloves garlic"
            "\\b\\d+\\s*\\+\\s*\\d+\\s*(tablespoon|teaspoon|cup)", // Patterns like "2 + 2 teaspoons"
            "\\b\\d+\\s*\\/\\s*\\d+\\s*(cup|tablespoon|teaspoon)", // Patterns like "1/2 cup"
            "\\b\\d+\\s*\\-\\s*\\d+\\s*(cup|tablespoon|teaspoon)", // Patterns like "2-3 tablespoons"
            "\\b\\d+\\s*(quart|quarts|gallon|gallons|pint|pints)\\b", // Additional volume measurements
            "\\b\\d+\\s*(teaspoon|teaspoons|tablespoon|tablespoons)\\b", // More specific patterns
            "\\b\\d+\\s*(ounce|ounces|pound|pounds)\\b", // Weight measurements
            "\\b\\d+\\s*(gram|grams|kilogram|kilograms)\\b" // Metric weight measurements
        ]
        
        // Check for measurement patterns first
        for pattern in measurementPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
                if !matches.isEmpty {
                    return true
                }
            }
        }

        // Fallback: count-only pattern like "6 strawberries" (no explicit unit word)
        if let rx = try? NSRegularExpression(pattern: #"^\s*\d+\s+[A-Za-z][A-Za-z\-\s]*$"#, options: []) {
            if rx.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func isLikelyIngredientLine(_ ingredientLine: String) -> Bool {
        // First, check if this line contains CSS or other non-recipe content
        let lowercasedLine = ingredientLine.lowercased()
        
        // CSS keywords that should be rejected
        let cssKeywords = [
            "display:", "width:", "height:", "position:", "border:", "padding:", "margin:",
            "background:", "color:", "font:", "text-align:", "float:", "clear:", "overflow:",
            "z-index:", "opacity:", "visibility:", "box-shadow:", "border-radius:",
            "flex:", "grid:", "transform:", "transition:", "animation:",
            "var(--", "!important", "@media", "@keyframes", "@import", "@font-face",
            "body{", "html{", "div{", "span{", "p{", "h1{", "h2{", "h3{", "h4{", "h5{", "h6{",
            ".is-hidden", ".visually-hidden", ".img--noscript", ".primary-img--noscript",
            ".no-js", ".mntl-", ".lazyload", "img[src=", "rem", "px", "em", "vh", "vw", "%"
        ]
        
        // Check if this line contains CSS content
        for keyword in cssKeywords {
            if lowercasedLine.contains(keyword.lowercased()) {
                return false // Reject CSS content
            }
        }
        
        // Special CSS detection patterns
        if (lowercasedLine.contains(".") && lowercasedLine.contains("{")) ||
           (lowercasedLine.contains("display:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("width:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("height:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("position:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("background:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("color:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("font:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("border:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("padding:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("margin:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("!important") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("var(--") && lowercasedLine.contains(")")) ||
           (lowercasedLine.contains("overflow:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("z-index:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("opacity:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("visibility:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("box-shadow:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("border-radius:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("flex:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("grid:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("transform:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("transition:") && lowercasedLine.contains(";")) ||
           (lowercasedLine.contains("animation:") && lowercasedLine.contains(";")) {
            return false // Reject CSS content
        }
        
        // Human-like ingredient recognition - look for common ingredient words with measurements
        let ingredientWords = [
            // Grains & Flours
            "flour", "pasta", "rice", "bread", "cornmeal", "semolina", "couscous",
            
            // Dairy
            "milk", "cream", "butter", "cheese", "yogurt", "sour cream", "heavy cream",
            
            // Proteins
            "egg", "eggs", "chicken", "beef", "pork", "fish", "salmon", "tuna", "shrimp",
            "bacon", "sausage", "ham", "salami", "pepperoni", "prosciutto",
            
            // Vegetables
            "onion", "garlic", "tomato", "tomatoes", "pepper", "peppers", "carrot", "carrots",
            "celery", "cucumber", "lettuce", "spinach", "kale", "broccoli", "cauliflower",
            "potato", "potatoes", "sweet potato", "zucchini", "eggplant", "mushroom",
            
            // Fruits
            "apple", "banana", "orange", "lemon", "lime", "strawberry", "blueberry",
            "raspberry", "peach", "pear", "grape", "cherry", "pineapple",
            
            // Herbs & Spices
            "basil", "parsley", "oregano", "thyme", "rosemary", "sage", "cilantro",
            "mint", "dill", "chive", "chives", "salt", "pepper", "paprika",
            "cinnamon", "nutmeg", "ginger", "cumin", "coriander", "turmeric",
            
            // Oils & Vinegars
            "olive oil", "vegetable oil", "canola oil", "sesame oil", "vinegar",
            "balsamic", "red wine vinegar", "apple cider vinegar",
            
            // Sweeteners
            "sugar", "honey", "maple syrup", "agave", "stevia", "brown sugar",
            
            // Nuts & Seeds
            "almond", "walnut", "pecan", "cashew", "peanut", "sunflower seed",
            "pumpkin seed", "sesame seed", "chia seed", "flax seed",
            
            // Other Common Ingredients
            "water", "broth", "stock", "sauce", "ketchup", "mustard", "mayonnaise",
            "soy sauce", "worcestershire", "hot sauce", "salsa", "pesto"
        ]
        
        // Check if line contains ingredient words with numbers (human-like pattern)
        for word in ingredientWords {
            if lowercasedLine.contains(word) && lowercasedLine.range(of: "\\b\\d+", options: .regularExpression) != nil {
                return true
            }
        }
        
        // Also check for measurement patterns
        return hasMeasurementPattern(ingredientLine)
    }
    
    private func isValidIngredientSection(_ content: String) -> Bool {
        // Check if the content contains common ingredient indicators
        let ingredientKeywords = [
            "cup", "tablespoon", "teaspoon", "ounce", "pound", "gram", "kilogram",
            "ml", "l", "g", "kg", "oz", "lb", "tbsp", "tsp", "cups", "tablespoons", "teaspoons",
            "egg", "milk", "flour", "sugar", "salt", "butter", "oil", "water", "cream",
            "vanilla", "chocolate", "fruit", "vegetable", "meat", "fish", "chicken", "beef"
        ]
        
        // Check for CSS/programming content that should be excluded
        let excludeKeywords = [
            "display:", "width:", "height:", "position:", "border:", "padding:", "margin:",
            "background:", "color:", "font:", "text-align:", "float:", "clear:", "overflow:",
            "var(--", "!important", "function", "return", "if(", "for(", "while(", "switch(",
            "document.", "window.", "console.", "setTimeout", "addEventListener",
            ".is-hidden", ".visually-hidden", ".img--noscript", ".primary-img--noscript",
            ".no-js", ".mntl-", ".lazyload", "img[src=", "body{", "html{", "div{", "span{",
            "p{", "h1{", "h2{", "h3{", "h4{", "h5{", "h6{", "@media", "@keyframes", "@import"
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var ingredientCount = 0
        var totalLines = 0
        var excludeCount = 0
        var measurementCount = 0
        var cssBlockCount = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLine.isEmpty {
                totalLines += 1
                let lowercasedLine = trimmedLine.lowercased()
                
                // Check for CSS blocks (strong negative indicator)
                if lowercasedLine.contains("{") && (lowercasedLine.contains("display:") || 
                                                   lowercasedLine.contains("width:") || 
                                                   lowercasedLine.contains("height:") ||
                                                   lowercasedLine.contains("position:") ||
                                                   lowercasedLine.contains("background:") ||
                                                   lowercasedLine.contains("color:") ||
                                                   lowercasedLine.contains("font:") ||
                                                   lowercasedLine.contains("border:") ||
                                                   lowercasedLine.contains("padding:") ||
                                                   lowercasedLine.contains("margin:")) {
                    cssBlockCount += 1
                    excludeCount += 1
                    continue
                }
                
                // Check for excluded content
                for excludeKeyword in excludeKeywords {
                    if lowercasedLine.contains(excludeKeyword.lowercased()) {
                        excludeCount += 1
                        break
                    }
                }
                
                // Check for ingredient keywords
                for keyword in ingredientKeywords {
                    if lowercasedLine.contains(keyword) {
                        ingredientCount += 1
                        break
                    }
                }
                
                // Check for measurement patterns (strong indicator of recipe ingredients)
                if hasMeasurementPattern(trimmedLine) {
                    measurementCount += 1
                }
            }
        }
        
        print("🔍 Ingredient validation: \(ingredientCount) ingredient lines, \(measurementCount) measurement patterns, \(excludeCount) excluded lines (\(cssBlockCount) CSS blocks) out of \(totalLines) total lines")
        
        // Reject if too much excluded content is found
        if excludeCount > ingredientCount && excludeCount > 2 {
            print("❌ Rejecting content due to too much CSS/programming content")
            return false
        }
        
        // Reject if we have CSS blocks (strong negative indicator)
        if cssBlockCount > 0 {
            print("❌ Rejecting content due to CSS blocks")
            return false
        }
        
        // Additional CSS rejection - check for any CSS-like content
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLine.isEmpty {
                let lowercasedLine = trimmedLine.lowercased()
                
                // Check for CSS patterns that should always be rejected
                if (lowercasedLine.contains(".") && lowercasedLine.contains("{")) ||
                   (lowercasedLine.contains("display:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("width:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("height:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("position:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("background:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("color:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("font:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("border:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("padding:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("margin:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("!important") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("var(--") && lowercasedLine.contains(")")) ||
                   (lowercasedLine.contains("overflow:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("z-index:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("opacity:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("visibility:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("box-shadow:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("border-radius:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("flex:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("grid:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("transform:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("transition:") && lowercasedLine.contains(";")) ||
                   (lowercasedLine.contains("animation:") && lowercasedLine.contains(";")) {
                    print("❌ Rejecting content due to CSS patterns")
                    return false
                }
            }
        }
        
        // Enhanced validation: prioritize measurement patterns
        if measurementCount >= 2 {
            print("✅ Valid section with strong measurement patterns")
            return true
        }
        
        // Fallback validation: if we have ingredient keywords or substantial content
        return ingredientCount >= 1 || (totalLines >= 3 && content.count > 50)
    }
    
    private func cleanIngredientContent(_ content: String) -> String {
        print("🧹 Cleaning ingredient content (length: \(content.count))")
        
        let lines = content.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        
        // Keywords that indicate CSS, JavaScript, or other non-recipe content
        let nonRecipeKeywords = [
            // CSS properties
            "display:", "width:", "height:", "position:", "border:", "padding:", "margin:",
            "background:", "color:", "font:", "text-align:", "float:", "clear:", "overflow:",
            "z-index:", "opacity:", "visibility:", "box-shadow:", "border-radius:",
            "flex:", "grid:", "transform:", "transition:", "animation:",
            
            // CSS selectors and rules
            "var(--", "!important", "@media", "@keyframes", "@import", "@font-face",
            "body{", "html{", "div{", "span{", "p{", "h1{", "h2{", "h3{", "h4{", "h5{", "h6{",
            ".is-hidden", ".visually-hidden", ".img--noscript", ".primary-img--noscript",
            ".no-js", ".mntl-", ".lazyload", "img[src=",
            
            // JavaScript
            "function", "return", "if(", "for(", "while(", "switch(", "case", "break",
            "document.", "window.", "console.", "setTimeout", "addEventListener",
            "getElementById", "getElementsByClassName", "querySelector",
            "addEventListener", "removeEventListener", "preventDefault",
            
            // Programming patterns
            "const ", "let ", "var ", "=>", "=>", "async", "await", "Promise",
            "try{", "catch{", "finally{", "throw", "new ", "class ", "extends",
            
            // HTML entities and encoding
            "&nbsp;", "&amp;", "&lt;", "&gt;", "&quot;", "&#39;", "&rsquo;", "&lsquo;",
            "&mdash;", "&ndash;", "&hellip;", "&copy;", "&trade;", "&reg;",
            
            // Common web development patterns
            "data-", "aria-", "role=", "tabindex=", "alt=", "src=", "href=",
            "class=", "id=", "style=", "onclick=", "onload=", "onscroll=",
            
            // Analytics and tracking
            "gtag", "ga(", "analytics", "tracking", "pixel", "beacon",
            "facebook", "twitter", "linkedin", "instagram", "pinterest",
            
            // Common web framework patterns
            "react", "vue", "angular", "jquery", "bootstrap", "foundation",
            "materialize", "semantic", "tailwind", "bulma"
        ]
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let lowercasedLine = trimmedLine.lowercased()
            
            // Check if this line contains non-recipe content
            var isNonRecipeLine = false
            for keyword in nonRecipeKeywords {
                if lowercasedLine.contains(keyword.lowercased()) {
                    isNonRecipeLine = true
                    break
                }
            }
            
            // Special handling for CSS blocks - skip entire blocks
            if lowercasedLine.contains("{") && (lowercasedLine.contains("display:") || 
                                               lowercasedLine.contains("width:") || 
                                               lowercasedLine.contains("height:") ||
                                               lowercasedLine.contains("position:") ||
                                               lowercasedLine.contains("background:") ||
                                               lowercasedLine.contains("color:") ||
                                               lowercasedLine.contains("font:") ||
                                               lowercasedLine.contains("border:") ||
                                               lowercasedLine.contains("padding:") ||
                                               lowercasedLine.contains("margin:")) {
                isNonRecipeLine = true
            }
            
            // Additional CSS detection - look for CSS selectors and properties
            if lowercasedLine.contains(".") && (lowercasedLine.contains("{") || 
                                               lowercasedLine.contains("display:") ||
                                               lowercasedLine.contains("width:") ||
                                               lowercasedLine.contains("height:") ||
                                               lowercasedLine.contains("position:") ||
                                               lowercasedLine.contains("background:") ||
                                               lowercasedLine.contains("color:") ||
                                               lowercasedLine.contains("font:") ||
                                               lowercasedLine.contains("border:") ||
                                               lowercasedLine.contains("padding:") ||
                                               lowercasedLine.contains("margin:") ||
                                               lowercasedLine.contains("!important") ||
                                               lowercasedLine.contains("var(--") ||
                                               lowercasedLine.contains("overflow:") ||
                                               lowercasedLine.contains("z-index:") ||
                                               lowercasedLine.contains("opacity:") ||
                                               lowercasedLine.contains("visibility:") ||
                                               lowercasedLine.contains("box-shadow:") ||
                                               lowercasedLine.contains("border-radius:") ||
                                               lowercasedLine.contains("flex:") ||
                                               lowercasedLine.contains("grid:") ||
                                               lowercasedLine.contains("transform:") ||
                                               lowercasedLine.contains("transition:") ||
                                               lowercasedLine.contains("animation:")) {
                isNonRecipeLine = true
            }
            
            // More aggressive CSS detection - catch any line that looks like CSS
            if (lowercasedLine.contains(".") && lowercasedLine.contains("{")) ||
               (lowercasedLine.contains("display:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("width:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("height:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("position:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("background:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("color:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("font:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("border:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("padding:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("margin:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("!important") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("var(--") && lowercasedLine.contains(")")) ||
               (lowercasedLine.contains("overflow:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("z-index:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("opacity:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("visibility:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("box-shadow:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("border-radius:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("flex:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("grid:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("transform:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("transition:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("animation:") && lowercasedLine.contains(";")) {
                isNonRecipeLine = true
            }
            
            // Only include non-CSS lines
            if !isNonRecipeLine {
                cleanedLines.append(line)
            }
        }
        
        let cleanedContent = cleanedLines.joined(separator: "\n")
        print("🧹 Cleaned ingredient content: \(cleanedLines.count) lines kept out of \(lines.count) total lines")
        
        return cleanedContent
    }
    
    private func cleanContentForRecipeExtraction(_ content: String) -> String {
        print("🧹 Cleaning content for recipe extraction")
        
        let lines = content.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var consecutiveNonRecipeLines = 0
        let maxConsecutiveNonRecipeLines = 10
        
        // Keywords that indicate CSS, JavaScript, or other non-recipe content
        let nonRecipeKeywords = [
            // CSS properties
            "display:", "width:", "height:", "position:", "border:", "padding:", "margin:",
            "background:", "color:", "font:", "text-align:", "float:", "clear:", "overflow:",
            "z-index:", "opacity:", "visibility:", "box-shadow:", "border-radius:",
            "flex:", "grid:", "transform:", "transition:", "animation:",
            
            // CSS selectors and rules
            "var(--", "!important", "@media", "@keyframes", "@import", "@font-face",
            "body{", "html{", "div{", "span{", "p{", "h1{", "h2{", "h3{", "h4{", "h5{", "h6{",
            ".is-hidden", ".visually-hidden", ".img--noscript", ".primary-img--noscript",
            ".no-js", ".mntl-", ".lazyload", "img[src=",
            
            // JavaScript
            "function", "return", "if(", "for(", "while(", "switch(", "case", "break",
            "document.", "window.", "console.", "setTimeout", "addEventListener",
            "getElementById", "getElementsByClassName", "querySelector",
            "addEventListener", "removeEventListener", "preventDefault",
            
            // Programming patterns
            "const ", "let ", "var ", "=>", "=>", "async", "await", "Promise",
            "try{", "catch{", "finally{", "throw", "new ", "class ", "extends",
            
            // HTML entities and encoding
            "&nbsp;", "&amp;", "&lt;", "&gt;", "&quot;", "&#39;", "&rsquo;", "&lsquo;",
            "&mdash;", "&ndash;", "&hellip;", "&copy;", "&trade;", "&reg;",
            
            // Common web development patterns
            "data-", "aria-", "role=", "tabindex=", "alt=", "src=", "href=",
            "class=", "id=", "style=", "onclick=", "onload=", "onscroll=",
            
            // Analytics and tracking
            "gtag", "ga(", "analytics", "tracking", "pixel", "beacon",
            "facebook", "twitter", "linkedin", "instagram", "pinterest",
            
            // Common web framework patterns
            "react", "vue", "angular", "jquery", "bootstrap", "foundation",
            "materialize", "semantic", "tailwind", "bulma"
        ]
        
        // Keywords that indicate recipe content (positive indicators)
        let recipeKeywords = [
            "ingredient", "recipe", "cook", "prep", "serving", "servings",
            "cup", "tablespoon", "teaspoon", "ounce", "pound", "gram", "kilogram",
            "ml", "l", "g", "kg", "oz", "lb", "tbsp", "tsp", "cups", "tablespoons", "teaspoons",
            "egg", "milk", "flour", "sugar", "salt", "butter", "oil", "water", "cream",
            "vanilla", "chocolate", "fruit", "vegetable", "meat", "fish", "chicken", "beef",
            "onion", "garlic", "tomato", "pepper", "carrot", "celery", "potato",
            "apple", "banana", "orange", "lemon", "lime", "strawberry", "blueberry",
            "basil", "parsley", "oregano", "thyme", "rosemary", "sage", "cilantro",
            "olive oil", "vegetable oil", "vinegar", "balsamic", "honey", "maple syrup"
        ]
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let lowercasedLine = trimmedLine.lowercased()
            
            // Check if this line contains non-recipe content
            var isNonRecipeLine = false
            for keyword in nonRecipeKeywords {
                if lowercasedLine.contains(keyword.lowercased()) {
                    isNonRecipeLine = true
                    break
                }
            }
            
            // Check if this line contains recipe content (positive indicator)
            var isRecipeLine = false
            for keyword in recipeKeywords {
                if lowercasedLine.contains(keyword.lowercased()) {
                    isRecipeLine = true
                    break
                }
            }
            
            // Special handling for CSS blocks - skip entire blocks
            if lowercasedLine.contains("{") && (lowercasedLine.contains("display:") || 
                                               lowercasedLine.contains("width:") || 
                                               lowercasedLine.contains("height:") ||
                                               lowercasedLine.contains("position:") ||
                                               lowercasedLine.contains("background:") ||
                                               lowercasedLine.contains("color:") ||
                                               lowercasedLine.contains("font:") ||
                                               lowercasedLine.contains("border:") ||
                                               lowercasedLine.contains("padding:") ||
                                               lowercasedLine.contains("margin:")) {
                isNonRecipeLine = true
            }
            
            // Additional CSS detection - look for CSS selectors and properties
            if lowercasedLine.contains(".") && (lowercasedLine.contains("{") || 
                                               lowercasedLine.contains("display:") ||
                                               lowercasedLine.contains("width:") ||
                                               lowercasedLine.contains("height:") ||
                                               lowercasedLine.contains("position:") ||
                                               lowercasedLine.contains("background:") ||
                                               lowercasedLine.contains("color:") ||
                                               lowercasedLine.contains("font:") ||
                                               lowercasedLine.contains("border:") ||
                                               lowercasedLine.contains("padding:") ||
                                               lowercasedLine.contains("margin:") ||
                                               lowercasedLine.contains("!important") ||
                                               lowercasedLine.contains("var(--") ||
                                               lowercasedLine.contains("overflow:") ||
                                               lowercasedLine.contains("z-index:") ||
                                               lowercasedLine.contains("opacity:") ||
                                               lowercasedLine.contains("visibility:") ||
                                               lowercasedLine.contains("box-shadow:") ||
                                               lowercasedLine.contains("border-radius:") ||
                                               lowercasedLine.contains("flex:") ||
                                               lowercasedLine.contains("grid:") ||
                                               lowercasedLine.contains("transform:") ||
                                               lowercasedLine.contains("transition:") ||
                                               lowercasedLine.contains("animation:")) {
                isNonRecipeLine = true
            }
            
            // More aggressive CSS detection - catch any line that looks like CSS
            if (lowercasedLine.contains(".") && lowercasedLine.contains("{")) ||
               (lowercasedLine.contains("display:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("width:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("height:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("position:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("background:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("color:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("font:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("border:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("padding:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("margin:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("!important") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("var(--") && lowercasedLine.contains(")")) ||
               (lowercasedLine.contains("overflow:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("z-index:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("opacity:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("visibility:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("box-shadow:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("border-radius:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("flex:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("grid:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("transform:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("transition:") && lowercasedLine.contains(";")) ||
               (lowercasedLine.contains("animation:") && lowercasedLine.contains(";")) {
                isNonRecipeLine = true
            }
            
            // CSS content should always be rejected, even if it contains recipe keywords
            if isNonRecipeLine {
                consecutiveNonRecipeLines += 1
                print("❌ Skipped non-recipe line \(index): \(String(trimmedLine.prefix(50)))")
                
                // If we've skipped too many consecutive non-recipe lines, stop processing
                if consecutiveNonRecipeLines >= maxConsecutiveNonRecipeLines {
                    print("🛑 Stopping content processing after \(consecutiveNonRecipeLines) consecutive non-recipe lines")
                    break
                }
            }
            // If it's a recipe line and not CSS, include it
            else if isRecipeLine {
                cleanedLines.append(line)
                consecutiveNonRecipeLines = 0
                print("✅ Recipe line \(index): \(String(trimmedLine.prefix(50)))")
            }
            // If it's a neutral line (doesn't match non-recipe patterns), include it
            else {
                cleanedLines.append(line)
                consecutiveNonRecipeLines = 0
                print("📝 Neutral line \(index): \(String(trimmedLine.prefix(50)))")
            }
        }
        
        let cleanedContent = cleanedLines.joined(separator: "\n")
        print("🧹 Cleaned content: \(cleanedLines.count) lines kept out of \(lines.count) total lines")
        print("🧹 Cleaned content preview: \(String(cleanedContent.prefix(200)))")
        
        return cleanedContent
    }
    
    // MARK: - New Extraction Methods
    
    private func extractStructuredData(from html: String) -> String? {
        print("🔍 Looking for structured data (JSON-LD)")
        // Match <script ... type="application/ld+json" ...>...</script> with flexible attribute order/quotes and case-insensitive
        let jsonLdPattern = "(?is)<script[^>]*type=['\\\"]application/ld\\+json['\\\"][^>]*>(.*?)</script>"
        if let regex = try? NSRegularExpression(pattern: jsonLdPattern, options: []) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let jsonString = String(html[range])
                    print("🔍 Found JSON-LD data: \(String(jsonString.prefix(200)))")
                    // Check if this contains recipe data
                    if jsonString.range(of: "\\\"@type\\\"\\s*:\\s*\\\"Recipe\\\"", options: .regularExpression) != nil ||
                       jsonString.contains("\"recipeIngredient\"") ||
                       jsonString.contains("\"ingredients\"") {
                        print("✅ Found recipe structured data")
                        return jsonString
                    }
                }
            }
        }
        return nil
    }
    
    private func extractRecipeContent(from html: String) -> String? {
        print("🔍 Looking for recipe-specific HTML content")
        
        // Look for recipe-specific HTML elements
        let recipePatterns = [
            #"<div[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</div>"#,
            #"<li[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</li>"#,
            #"<span[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</span>"#,
            #"<div[^>]*class="[^"]*recipe[^"]*"[^>]*>(.*?)</div>"#,
            #"<section[^>]*class="[^"]*recipe[^"]*"[^>]*>(.*?)</section>"#,
            #"<ul[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</ul>"#,
            #"<ol[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</ol>"#,
            #"<div[^>]*class="[^"]*ingredients[^"]*"[^>]*>(.*?)</div>"#,
            #"<section[^>]*class="[^"]*ingredients[^"]*"[^>]*>(.*?)</section>"#,
            #"<div[^>]*class="[^"]*recipe-ingredients[^"]*"[^>]*>(.*?)</div>"#,
            #"<div[^>]*class="[^"]*recipe-ingredient[^"]*"[^>]*>(.*?)</div>"#,
            // Serious Eats MNTL structured ingredients containers
            #"<div[^>]*class="[^"]*mntl-structured-ingredients[^"]*"[^>]*>(.*?)</div>"#,
            #"<ul[^>]*class="[^"]*mntl-structured-ingredients__list[^"]*"[^>]*>(.*?)</ul>"#,
            #"<li[^>]*class="[^"]*mntl-structured-ingredients__list-item[^"]*"[^>]*>(.*?)</li>"#
        ]
        
        for pattern in recipePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
                let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                
                if !matches.isEmpty {
                    print("✅ Found recipe content with pattern: \(pattern)")
                    var extractedContent: [String] = []
                    
                    for match in matches {
                        if let range = Range(match.range(at: 1), in: html) {
                            let content = String(html[range])
                            extractedContent.append(content)
                        }
                    }
                    
                    let combinedContent = extractedContent.joined(separator: "\n")
                    print("📄 Extracted recipe content length: \(combinedContent.count)")
                    print("📄 First 200 chars of extracted content: \(String(combinedContent.prefix(200)))")
                    return combinedContent
                }
            }
        }
        
        return nil
    }
    
    private func extractContentAroundKeywords(_ content: String) -> String {
        // Look for sections that contain ingredient-related keywords
        let ingredientKeywords = [
            "ingredients", "ingredient", "for the", "you'll need", "what you need",
            "cup", "tablespoon", "teaspoon", "ounce", "pound", "egg", "milk", "flour", "sugar",
            "salt", "butter", "oil", "water", "cream", "vanilla", "chocolate"
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var relevantLines: [String] = []
        var inIngredientSection = false
        var consecutiveEmptyLines = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercasedLine = trimmedLine.lowercased()
            
            // Check if this line indicates start of ingredient section
            for keyword in ingredientKeywords {
                if lowercasedLine.contains(keyword) {
                    inIngredientSection = true
                    consecutiveEmptyLines = 0
                    break
                }
            }
            
            if inIngredientSection {
                if !trimmedLine.isEmpty {
                    relevantLines.append(line)
                    consecutiveEmptyLines = 0
                } else {
                    consecutiveEmptyLines += 1
                }
                
                // Stop if we hit a section that looks like instructions or too many empty lines
                if lowercasedLine.contains("instructions") || 
                   lowercasedLine.contains("directions") || 
                   lowercasedLine.contains("method") ||
                   lowercasedLine.contains("steps") ||
                   lowercasedLine.contains("preparation") ||
                   consecutiveEmptyLines >= 3 {
                    break
                }
            }
        }
        
        let extracted = relevantLines.joined(separator: "\n")
        print("📋 Extracted content around keywords: \(String(extracted.prefix(200)))")
        return extracted
    }
    
    // MARK: - JSON Processing Utilities
    
    private func convertFractionsToDecimals(_ jsonString: String) -> String {
        var result = jsonString
        
        // Common fraction patterns to convert
        let fractionPatterns: [(String, Double)] = [
            ("1/4", 0.25),
            ("1/3", 0.333),
            ("1/2", 0.5),
            ("2/3", 0.667),
            ("3/4", 0.75),
            ("1/8", 0.125),
            ("3/8", 0.375),
            ("5/8", 0.625),
            ("7/8", 0.875),
            ("1/6", 0.167),
            ("1/5", 0.2),
            ("2/5", 0.4),
            ("3/5", 0.6),
            ("4/5", 0.8)
        ]
        
        for (fraction, decimal) in fractionPatterns {
            // Replace fractions in JSON values (but not in strings)
            // Look for patterns like "amount": 1/4 or "amount": 1/2
            let pattern = "\"amount\":\\s*\(fraction)"
            let replacement = "\"amount\": \(decimal)"
            
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
            }
        }
        
        print("🔄 Converted fractions to decimals in JSON")
        return result
    }
    
    // MARK: - Ingredient Processing Constants
    
    // Words that should be preserved in ingredient names (not removed during cleaning)
    private let preservedWords: Set<String> = [
        // Keep these descriptors in ingredient names
        "fresh", // keep e.g. "fresh basil" per requirement
        "frozen", // keep e.g. "frozen sour cherries" per requirement
        "whipped", // keep e.g. "whipped cream" as a product label
        "pitted", // keep e.g. "pitted kalamata olives"
        "salted", "unsalted",
        "sweet", "sour", "bitter", "spicy", "hot", "mild",
        "extra", "virgin"
    ]
    
    // Words that should be removed from ingredient names during cleaning
    private let preparationWords: Set<String> = [
        // Preparation/state words
        "uncooked", "drained", "chopped", "sliced", "diced", "minced",
        "crushed", "whole", "raw", "cooked", "roasted", "toasted", "thawed", 
        "warm", "cold", "hot", "softened", "melted", "chilled", "room temperature", "room temp",
        "soft", "hard", "ripe", "unripe", "overripe", "underripe",
        
        // Size descriptors
        "large", "small", "medium", "jumbo", "baby", "mini", "regular", "extra large", "xl",
        
        // Quality/premium descriptors (marketing terms)
        "organic", "natural", "pure", "premium", "gourmet", "artisanal", "handmade", "homemade",
        "store-bought", "imported", "domestic", "local", "regional", "seasonal", "year-round",
        "quality", "best", "finest", "select", "choice", "grade", "a", "b", "c", "perfect", 
        "ideal", "optimal", "authentic", "traditional", "classic", "original", "genuine",
        "real", "true", "genuine", "premium", "superior", "excellent", "outstanding",
        "top-quality", "high-quality", "premium-quality", "gourmet-quality", "restaurant-quality",
        "farm-fresh", "farm-to-table", "sustainably-sourced", "ethically-sourced", "fair-trade",
        "non-gmo", "gluten-free", "dairy-free", "vegan", "vegetarian", "kosher", "halal",
        "all-natural", "100% natural", "pure", "unprocessed", "unrefined", "cold-pressed",
        "extra-virgin", "virgin", "first-press", "single-origin", "small-batch", "craft",
        "boutique", "specialty", "premium", "luxury", "deluxe", "premium-grade", "select-grade"
    ]
    
    // Special category overrides (priority order)
    private let categoryOverrides: [(String, GroceryCategory)] = [
        // Pantry-first: oils
        ("olive oil", .pantry),
        ("vegetable oil", .pantry),
        ("canola oil", .pantry),
        ("avocado oil", .pantry),
        ("grapeseed oil", .pantry),
        ("peanut oil", .pantry),
        ("sesame oil", .pantry),
        ("coconut oil", .pantry),
        ("sunflower oil", .pantry),
        ("safflower oil", .pantry),
        ("corn oil", .pantry),
        ("oil", .pantry), // generic catch-all for cooking oils

        // Pantry: common spices that could collide with Produce keywords
        ("garlic powder", .pantry),
        ("cayenne pepper", .pantry),
        ("cayenne", .pantry),
        ("peppercorn", .pantry),
        ("peppercorns", .pantry),
        ("black pepper", .pantry),
        ("ground pepper", .pantry),
        ("ground black pepper", .pantry),
        ("dried mint", .pantry),
        ("miso", .pantry),
        ("vinegar", .pantry),

        // Pantry: leaveners and alkalis
        ("baking soda", .pantry),
        ("bicarbonate of soda", .pantry),
        ("sodium bicarbonate", .pantry),
        ("baking powder", .pantry),

        // Pantry: gelatin / dessert mixes
        ("jell-o", .pantry),
        ("jello", .pantry),
        ("gelatin", .pantry),
        ("gelatine", .pantry),

        // Pantry: chile/pepper flake seasonings
        ("red pepper flakes", .pantry),
        ("crushed red pepper", .pantry),
        ("chili flakes", .pantry),
        ("chile flakes", .pantry),

        // Dairy: whipped toppings and creams (brand-inclusive)
        ("whipped topping", .dairy),
        ("whipped cream", .dairy),
        ("cool whip", .dairy),

        // Pantry: broths & stocks (explicit high-priority overrides)
        ("chicken stock", .pantry),
        ("chicken broth", .pantry),
        ("beef stock", .pantry),
        ("beef broth", .pantry),
        ("vegetable stock", .pantry),
        ("vegetable broth", .pantry),
        ("bone broth", .pantry),
        ("stock", .pantry),
        ("broth", .pantry),

        // Pantry: pickled/jarred items commonly listed as rings
        ("banana pepper rings", .pantry),
        ("mild banana pepper rings", .pantry),
        ("pickled banana pepper", .pantry),

        // Produce: explicit override to avoid Beverages "water" collision
        ("watermelon", .produce),

            // Beverages: common spirits
            ("rum", .beverages),
            ("vodka", .beverages),
            ("gin", .beverages),
            ("tequila", .beverages),
            ("whiskey", .beverages),
            ("whisky", .beverages),
            ("bourbon", .beverages),
            ("scotch", .beverages),
            ("brandy", .beverages),
            ("cognac", .beverages),
            ("liqueur", .beverages),
            ("liqueurs", .beverages),

        // Produce: specific juices and items
		("lemon juice", .produce),
		("lime juice", .produce),
		("orange juice", .produce),
		("grapefruit juice", .produce),
        
		// Produce: citrus zest
		("lemon zest", .produce),
		("lime zest", .produce),
		("orange zest", .produce),
		("grapefruit zest", .produce)
    ]
}
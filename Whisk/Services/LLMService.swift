import Foundation

class LLMService: ObservableObject {
    private let baseURL = "https://whisk-server-97zqsyqbp-dannelson.vercel.app/api/call-openai"
    
    // 🚀 NEW: Simple in-memory cache for parsed recipes
    private var recipeCache: [String: RecipeParsingResult] = [:]
    private let cacheQueue = DispatchQueue(label: "recipeCache", attributes: .concurrent)
    
    // 🚀 NEW: Performance tracking
    private var performanceStats = PerformanceStats()
    
    init() {
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
        
        // Extract ingredient section and try regex fallback first
        let ingredientSection = extractIngredientSection(from: webpageContent)
        
        // 🚀 NEW: Try regex-based parsing as fallback (fast, no LLM cost)
        if let regexParsedIngredients = parseIngredientsWithRegex(ingredientSection),
           regexParsedIngredients.count >= 3 {
            print("✅ Successfully parsed \(regexParsedIngredients.count) ingredients with regex - skipping LLM call!")
            performanceStats.recordRegexSuccess()
            var recipe = Recipe(url: url)
            recipe.ingredients = regexParsedIngredients
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
        }
        
        // 🚀 NEW: Estimate token usage and truncate if needed
        let estimatedTokens = estimateTokenCount(ingredientSection)
        let maxTokens = 4000 // Conservative limit for GPT-4
        let truncatedContent = estimatedTokens > maxTokens ? truncateContent(ingredientSection, targetTokens: maxTokens) : ingredientSection
        
        let prompt = createRecipeParsingPrompt(ingredientContent: truncatedContent)
        
        // Call LLM
        let llmStartTime = CFAbsoluteTimeGetCurrent()
        let response = try await callLLM(prompt: prompt)
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
    func parseIngredientsWithRegex(_ content: String) -> [Ingredient]? {
        print("🔍 Attempting regex-based ingredient parsing...")
        
        let lines = content.components(separatedBy: .newlines)
        var ingredients: [Ingredient] = []
        
        // More precise regex pattern for actual ingredients only
        let ingredientPattern = #"(?i)(\d+[\d\/\s\.]*)\s*(cup|cups|tsp|teaspoon|teaspoons|tbsp|tablespoon|tablespoons|oz|ounce|ounces|pound|pounds|gram|grams|ml|clove|cloves|sprig|sprigs|piece|pieces|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches|head|heads|slice|slices|small|medium|large|extra\s*large|xl)\s+([^,\.]+?)(?:\s*\([^)]*\))?(?:\s*,\s*[^,]*)?$"#
        
        guard let regex = try? NSRegularExpression(pattern: ingredientPattern, options: [.caseInsensitive]) else {
            print("❌ Failed to create regex pattern")
            return nil
        }
        
        // Keywords that indicate this is NOT an ingredient (cooking instructions, etc.)
        let nonIngredientKeywords = [
            "minute", "minutes", "second", "seconds", "hour", "hours", "cook", "cooking", "heat", "heated",
            "simmer", "boil", "fry", "bake", "roast", "grill", "stir", "mix", "blend", "whisk",
            "strain", "drain", "press", "squeeze", "chop", "slice", "dice", "mince", "grate",
            "until", "until just", "until lightly", "until golden", "until tender", "until cooked",
            "over medium", "over high", "over low", "in a", "in the", "on a", "on the",
            "carefully", "gently", "slowly", "quickly", "immediately", "transfer", "serve",
            "season", "seasoning", "salt and pepper", "to taste", "divided", "reserved",
            "cooled", "heated", "warmed", "chilled", "frozen", "thawed", "room temperature"
        ]
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            let matches = regex.matches(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine))
            
            for match in matches {
                if match.numberOfRanges >= 4 {
                    let amountRange = match.range(at: 1)
                    let unitRange = match.range(at: 2)
                    let nameRange = match.range(at: 3)
                    
                    if let amountString = Range(amountRange, in: trimmedLine).map({ String(trimmedLine[$0]) }),
                       let nameString = Range(nameRange, in: trimmedLine).map({ String(trimmedLine[$0]) }) {
                        
                        // Check if this looks like an actual ingredient (not cooking instructions)
                        let cleanName = nameString.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lowercasedName = cleanName.lowercased()
                        
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
                        
                        // Skip if it looks like a cooking instruction (contains verbs)
                        let cookingVerbs = ["cook", "heat", "stir", "mix", "blend", "whisk", "strain", "drain", "press", "squeeze", "chop", "slice", "dice", "mince", "grate", "season", "transfer", "serve"]
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
                        let amount = parseAmount(amountString)
                        
                        // Parse unit
                        let unit: String
                        if unitRange.location != NSNotFound,
                           let unitString = Range(unitRange, in: trimmedLine).map({ String(trimmedLine[$0]) }) {
                            unit = standardizeUnit(unitString)
                        } else {
                            unit = "piece"
                        }
                        
                        // Clean ingredient name - remove measurement units and parentheses
                        var cleanIngredientName = cleanIngredientName(cleanName)
                        
                        // Remove measurement units in parentheses like "(30 g)", "(20 g)", etc.
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                        
                        // Remove measurement units that might be at the start
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"^[^a-zA-Z]*"#, with: "", options: .regularExpression)
                        
                        // Remove trailing measurement units
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
                        
                        // Remove "from 1 small head" type phrases (but preserve "shredded")
                        cleanIngredientName = cleanIngredientName.replacingOccurrences(of: #"\s+from\s+\d+\s+[^,]*"#, with: "", options: .regularExpression)
                        
                        // If comma descriptors exist, keep only the main name before the first comma
                        if let commaIndex = cleanIngredientName.firstIndex(of: ",") {
                            cleanIngredientName = String(cleanIngredientName[..<commaIndex])
                        }
                        // Clean up extra whitespace
                        cleanIngredientName = cleanIngredientName.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Determine category
                        let category = determineCategory(cleanIngredientName)
                        
                        let ingredient = Ingredient(name: cleanIngredientName, amount: amount, unit: unit, category: category)
                        ingredients.append(ingredient)
                        
                        print("📋 Regex parsed: \(cleanIngredientName) - \(amount) \(unit) (\(category))")
                    }
                }
            }
        }
        
        if ingredients.count >= 3 {
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
    
    // 🚀 NEW: Determine ingredient category from name
    private func determineCategory(_ name: String) -> GroceryCategory {
        let lowercasedName = name.lowercased()
        
        // Check category overrides first
        for (keyword, category) in categoryOverrides {
            if lowercasedName.contains(keyword) {
                return category
            }
        }
        
        // Check category keywords
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
    func parseIngredientFromString(_ ingredientString: String) -> Ingredient? {
        let cleanString = ingredientString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract amount and unit using regex
        let pattern = #"(?i)(\d+[\d\/\s\.]*)\s*(cup|tsp|tbsp|oz|pound|grams?|ml|clove|piece|pieces|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches|head|heads|slice|slices|small|medium|large|extra\s*large|xl)?\s*(.*)"#
        
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
            
            // Clean up extra whitespace
            cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let category = determineCategory(cleanName)
            return Ingredient(name: cleanName, amount: 1.0, unit: "piece", category: category)
        }
        
        let amountRange = match.range(at: 1)
        let unitRange = match.range(at: 2)
        let nameRange = match.range(at: 3)
        
        guard let amountString = Range(amountRange, in: cleanString).map({ String(cleanString[$0]) }),
              let nameString = Range(nameRange, in: cleanString).map({ String(cleanString[$0]) }) else {
            return nil
        }
        
        let amount = parseAmount(amountString)
        
        let unit: String
        if unitRange.location != NSNotFound,
           let unitString = Range(unitRange, in: cleanString).map({ String(cleanString[$0]) }) {
            unit = standardizeUnit(unitString)
        } else {
            unit = "piece"
        }
        
        let cleanName = cleanIngredientName(nameString)
        let category = determineCategory(cleanName)
        
        return Ingredient(name: cleanName, amount: amount, unit: unit, category: category)
    }
    
    private func fetchWebpageContent(from url: String) async throws -> String {
        guard let url = URL(string: url) else {
            print("❌ Invalid URL: \(url)")
            throw LLMServiceError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw LLMServiceError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            print("❌ HTTP Error: \(httpResponse.statusCode)")
            throw LLMServiceError.invalidResponse
        }
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to decode HTML content")
            throw LLMServiceError.invalidResponse
        }
        
        // ULTRA-AGGRESSIVE: Extract only ingredient lines
        let startTime = CFAbsoluteTimeGetCurrent()
        var textContent = ""
        
        // Extract only lines that contain measurements AND look like ingredients
        let lines = htmlString.components(separatedBy: .newlines)
        var ingredientLines: [String] = []
        var timings: [String: Double] = [:]
        
        // Keywords that indicate cooking instructions (not ingredients)
        let cookingKeywords = [
            "minute", "minutes", "second", "seconds", "hour", "hours", "cook", "cooking", "heat", "heated",
            "simmer", "boil", "fry", "bake", "roast", "grill", "stir", "mix", "blend", "whisk",
            "strain", "drain", "press", "squeeze", "chop", "slice", "dice", "mince", "grate",
            "until", "until just", "until lightly", "until golden", "until tender", "until cooked",
            "over medium", "over high", "over low", "in a", "in the", "on a", "on the",
            "carefully", "gently", "slowly", "quickly", "immediately", "transfer", "serve",
            "season", "seasoning", "salt and pepper", "to taste", "divided", "reserved",
            "cooled", "heated", "warmed", "chilled", "frozen", "thawed", "room temperature"
        ]
        
        for line in lines {
            let cleanLine = line
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&rsquo;", with: "'")
                .replacingOccurrences(of: "&lsquo;", with: "'")
                .replacingOccurrences(of: "&mdash;", with: "—")
                .replacingOccurrences(of: "&ndash;", with: "–")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanLine.isEmpty {
                let lowercasedLine = cleanLine.lowercased()
                
                // Skip lines that are clearly cooking instructions
                var isCookingInstruction = false
                for keyword in cookingKeywords {
                    if lowercasedLine.contains(keyword.lowercased()) {
                        isCookingInstruction = true
                        break
                    }
                }
                
                if isCookingInstruction {
                    continue
                }
                
                // Only keep lines with measurements AND reasonable length
                if (lowercasedLine.contains("cup") || lowercasedLine.contains("tablespoon") || 
                    lowercasedLine.contains("teaspoon") || lowercasedLine.contains("ounce") || 
                    lowercasedLine.contains("pound") || lowercasedLine.contains("gram") ||
                    lowercasedLine.contains("clove") || lowercasedLine.contains("sprig") || lowercasedLine.contains("sprigs") || lowercasedLine.contains("medium") ||
                    lowercasedLine.contains("small") || lowercasedLine.contains("large") ||
                    lowercasedLine.contains("ml") || lowercasedLine.contains("g ") ||
                    lowercasedLine.contains("kg") || lowercasedLine.contains("l ") ||
                    lowercasedLine.contains("tbsp") || lowercasedLine.contains("tsp")) &&
                   cleanLine.count > 10 && cleanLine.count < 200 {
                    ingredientLines.append(cleanLine)
                }
            }
        }
        
        textContent = ingredientLines.joined(separator: "\n")
        timings["lineFiltering"] = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Line filtering time: \(String(format: "%.2f", timings["lineFiltering"]!)) seconds")
        print("📋 Filtered to \(ingredientLines.count) ingredient lines")
        
        // HARD LIMIT: Truncate to 1000 characters max
        if textContent.count > 1000 {
            textContent = String(textContent.prefix(1000))
            textContent += "\n\n[Content truncated...]"
        }
        
        // First, try to extract ingredients from HTML list elements
        let listStartTime = CFAbsoluteTimeGetCurrent()
        let listPatterns = [
            #"<ul[^>]*>(.*?)</ul>"#,
            #"<ol[^>]*>(.*?)</ol>"#
        ]
        
        var extractedIngredients: [String] = []
        
        for pattern in listPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
                let matches = regex.matches(in: htmlString, options: [], range: NSRange(htmlString.startIndex..., in: htmlString))
                
                for match in matches {
                    if let range = Range(match.range(at: 1), in: htmlString) {
                        let listContent = String(htmlString[range])
                        
                        // Extract individual list items
                        let itemPattern = #"<li[^>]*>(.*?)</li>"#
                        var allItems: [String] = []
                        var hasMeasurement = false
                        if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
                            let itemMatches = itemRegex.matches(in: listContent, options: [], range: NSRange(listContent.startIndex..., in: listContent))
                            
                            for itemMatch in itemMatches {
                                if let itemRange = Range(itemMatch.range(at: 1), in: listContent) {
                                    let item = String(listContent[itemRange])
                                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !item.isEmpty {
                                        allItems.append(item)
                                        // Check for measurement keywords
                                        if item.contains("cup") || item.contains("tablespoon") || 
                                           item.contains("teaspoon") || item.contains("ounce") || 
                                           item.contains("pound") || item.contains("gram") ||
                                           item.contains("clove") || item.contains("medium") ||
                                           item.contains("small") || item.contains("large") {
                                            hasMeasurement = true
                                        }
                                    }
                                }
                            }
                        }
                        // If at least one item has a measurement, include all items from this list
                        if hasMeasurement {
                            for item in allItems {
                                extractedIngredients.append(item)
                                print("📋 Found ingredient in validated list: \(item)")
                            }
                        }
                    }
                }
            }
        }
        
        // If we found ingredients in lists, use them; otherwise look for ingredient section
        timings["listParsing"] = CFAbsoluteTimeGetCurrent() - listStartTime
        print("⏱️ List parsing time: \(String(format: "%.2f", timings["listParsing"]!)) seconds")
        
        if !extractedIngredients.isEmpty {
            textContent = extractedIngredients.joined(separator: "\n")
            print("📋 Found \(extractedIngredients.count) ingredients in HTML lists")
        } else {
            // Fallback: Look for ingredient section specifically
            let sectionStartTime = CFAbsoluteTimeGetCurrent()
            let ingredientKeywords = ["ingredients", "ingredient", "recipe details", "what you need", "you'll need"]
            let lines = textContent.components(separatedBy: .newlines)
            var ingredientSection: [String] = []
            var inIngredientSection = false
            
            for line in lines {
                let lowercasedLine = line.lowercased()
                
                // Check if we're entering ingredient section
                for keyword in ingredientKeywords {
                    if lowercasedLine.contains(keyword) {
                        inIngredientSection = true
                        ingredientSection.append(line)
                        break
                    }
                }
                
                if inIngredientSection {
                    ingredientSection.append(line)
                    
                    // Stop at directions/instructions
                    if lowercasedLine.contains("directions") || 
                       lowercasedLine.contains("instructions") || 
                       lowercasedLine.contains("method") ||
                       lowercasedLine.contains("steps") {
                        break
                    }
                }
            }
            
            // If we found an ingredient section, use it; otherwise use full content
            timings["sectionParsing"] = CFAbsoluteTimeGetCurrent() - sectionStartTime
            print("⏱️ Section parsing time: \(String(format: "%.2f", timings["sectionParsing"]!)) seconds")
            
            if !ingredientSection.isEmpty {
                textContent = ingredientSection.joined(separator: "\n")
                print("📋 Found ingredient section with \(ingredientSection.count) lines")
            }
        }
        
        print("📄 Processed text length: \(textContent.count)")
        print("📄 First 200 chars: \(String(textContent.prefix(200)))")
        
        // Truncate if too long to stay within token limits
        let maxLength = 50000
        if textContent.count > maxLength {
            textContent = String(textContent.prefix(maxLength))
            textContent += "\n\n[Content truncated due to length...]"
        }
        
        return textContent
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
                    
                    recipe.ingredients = parsedIngredients
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
                    
                    // Also check if key ingredients are in the content
                    let keyIngredients = ["conchiglie", "pasta", "grape", "tomatoes", "mozzarella", "basil", "olives", "onion", "vinegar"]
                    for ingredient in keyIngredients {
                        if originalContent.lowercased().contains(ingredient.lowercased()) {
                            print("✅ Found '\(ingredient)' in content")
                        } else {
                            print("❌ Missing '\(ingredient)' in content")
                        }
                    }
                    
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
        
        // 3. Check for reasonable amounts
        if ingredient.amount <= 0 {
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
            "count"
        ]
        
        let lowercasedUnit = ingredient.unit.lowercased()
        let hasValidUnit = validUnits.contains { validUnit in
            lowercasedUnit.contains(validUnit)
        }
        
        if !hasValidUnit {
            return IngredientValidation(isValid: false, reason: "Unrecognized unit: '\(ingredient.unit)'")
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
    
    // MARK: - Centralized Ingredient Processing
    
    private func processAndStandardizeIngredient(name: String, amount: Any?, unit: Any?, category: GroceryCategory) -> Ingredient {
        // 1. Clean and standardize the ingredient name
        let cleanedName = cleanIngredientName(name)
        
        // 2. Process and standardize the amount and unit
        let (standardizedAmount, standardizedUnit) = processAmountAndUnit(name: cleanedName, amount: amount, unit: unit)
        
        // 3. Validate and potentially adjust category based on cleaned name
        let validatedCategory = validateAndAdjustCategory(cleanedName, originalCategory: category)
        
        // 4. Create the standardized ingredient
        return Ingredient(name: cleanedName, amount: standardizedAmount, unit: standardizedUnit, category: validatedCategory)
    }
    
    private func processAmountAndUnit(name: String, amount: Any?, unit: Any?) -> (amount: Double, unit: String) {
        // Check if this is an individual fruit/vegetable that should use piece units
        let lowercasedName = name.lowercased()
        let individualItems: Set<String> = [
            "peppers", "bell peppers", "red bell peppers", "green bell peppers", "yellow bell peppers",
            "tomatoes", "grape tomatoes", "cherry tomatoes", "roma tomatoes",
            "avocados", "hass avocados", "bananas", "peaches", "oranges", "limes", "lemons",
            "apples", "pears", "plums", "nectarines", "mangoes", "pineapples",
            "cucumbers", "zucchinis", "eggplants", "squashes", "pumpkins"
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
        let standardizedAmount = processAndStandardizeAmount(amount)
        let standardizedUnit = processAndStandardizeUnit(unit)
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
            // Default to 1 if no amount specified
            processedAmount = 1.0
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
        if lowercasedUnit.contains("greasing") || lowercasedUnit.contains("garnish") || lowercasedUnit.contains("to taste") {
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
        
        // If no matching keywords found, return the original category
        return originalCategory
    }
    
    private func cleanIngredientName(_ name: String) -> String {
        
        var cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Convert to lowercase for comparison
        let lowercasedName = cleanedName.lowercased()
        
        // Special handling for garlic cloves - preserve "cloves" in the name
        if lowercasedName.contains("garlic") && lowercasedName.contains("cloves") {
            // Keep "garlic cloves" as the ingredient name
            return "garlic cloves"
        }
        
        // Remove preparation words from the beginning (but preserve important descriptors)
        for word in preparationWords {
            // Skip if this word should be preserved
            if preservedWords.contains(word) {
                continue
            }
            
            let wordPattern = "^\\s*\(word)\\s+"
            if let range = lowercasedName.range(of: wordPattern, options: .regularExpression) {
                cleanedName = String(cleanedName[range.upperBound...])
                break
            }
        }
        
        // Remove preparation words from the end (but preserve important descriptors)
        for word in preparationWords {
            // Skip if this word should be preserved
            if preservedWords.contains(word) {
                continue
            }
            
            let wordPattern = "\\s+\(word)\\s*$"
            if let range = lowercasedName.range(of: wordPattern, options: .regularExpression) {
                cleanedName = String(cleanedName[..<range.lowerBound])
                break
            }
        }
        
        // Clean up any extra whitespace
        cleanedName = cleanedName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure we don't return an empty string
        if cleanedName.isEmpty {
            return name // Return original if cleaning resulted in empty string
        }
        
        return cleanedName
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
        // Simple approach: Let the LLM handle the filtering
        // Just return the content and let the LLM figure out what's food vs code
        return content
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
        
        // Look for JSON-LD script tags
        let jsonLdPattern = #"<script type="application/ld\+json">(.*?)</script>"#
        
        if let regex = try? NSRegularExpression(pattern: jsonLdPattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let jsonString = String(html[range])
                    print("🔍 Found JSON-LD data: \(String(jsonString.prefix(200)))")
                    
                    // Check if this contains recipe data
                    if jsonString.contains("\"@type\":\"Recipe\"") || 
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
            #"<div[^>]*class="[^"]*recipe-ingredient[^"]*"[^>]*>(.*?)</div>"#
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
        "salted", "unsalted", "sweet", "sour", "bitter", "spicy", "hot", "mild",
        "extra", "virgin"
    ]
    
    // Words that should be removed from ingredient names during cleaning
    private let preparationWords: Set<String> = [
        // Preparation/state words
        "fresh", "mild", "uncooked", "pitted", "drained", "chopped", "sliced", "diced", "minced",
        "crushed", "whole", "raw", "cooked", "roasted", "toasted", "frozen", "thawed", 
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
        ("vinegar", .pantry),
        ("lemon juice", .produce)
    ]
    
    // Category keywords for classification
    private let categoryKeywords: [GroceryCategory: Set<String>] = [
        .produce: ["tomato", "tomatoes", "onion", "onions", "garlic", "lettuce", "carrot", "carrots", 
                  "pepper", "peppers", "cucumber", "basil", "herb", "herbs", "vegetable", "vegetables",
                  "fruit", "fruits", "lemon", "lime", "orange", "apple", "banana", "berry", "berries"],
        .meatAndSeafood: ["chicken", "beef", "pork", "fish", "salmon", "shrimp", "meat", "steak", 
                         "turkey", "lamb", "seafood", "tuna", "cod", "sausage"],
        .deli: ["ham", "salami", "prosciutto", "deli", "cold cut", "cold cuts", "genoa"],
        .bakery: ["bread", "roll", "rolls", "bun", "buns", "bagel", "muffin", "cake", "pastry"],
        .frozen: ["frozen", "ice cream", "ice", "freezer"],
        .pantry: ["flour", "sugar", "salt", "spice", "spices", "oil", "sauce", "pasta", 
                 "rice", "bean", "beans", "canned", "dry", "dried"],
        .dairy: ["milk", "cream", "yogurt", "butter", "mozzarella", "cheese", "egg", "eggs"],
        .beverages: ["water", "juice", "soda", "drink", "beverage", "wine", "beer", "liquor", "spirits"]
    ]
    
    // Unit standardization mappings
    private let unitMappings: [String: String] = [
        // Weight units
        "oz": "ounces", "ounce": "ounces", "ounces": "ounces",
        "lb": "pounds", "lbs": "pounds", "pound": "pounds", "pounds": "pounds",
        "g": "grams", "gram": "grams", "grams": "grams",
        "kg": "kilograms", "kilogram": "kilograms", "kilograms": "kilograms",
        
        // Volume units
        "tbsp": "tablespoons", "tbs": "tablespoons", "tablespoon": "tablespoons", "tablespoons": "tablespoons",
        "tsp": "teaspoons", "teaspoon": "teaspoons", "teaspoons": "teaspoons",
        "c": "cups", "cup": "cups", "cups": "cups",
        "pt": "pints", "pint": "pints", "pints": "pints",
        "qt": "quarts", "quart": "quarts", "quarts": "quarts",
        "gal": "gallons", "gallon": "gallons", "gallons": "gallons",
        "ml": "milliliters", "milliliter": "milliliters", "milliliters": "milliliters",
        "l": "liters", "liter": "liters", "liters": "liters",
        
        // Count units
        "clove": "cloves", "cloves": "cloves",
        "count": "count",
        "slice": "slices", "slices": "slices",
        "piece": "pieces", "pieces": "pieces",
        "can": "cans", "cans": "cans",
        "jar": "jars", "jars": "jars",
        "bottle": "bottles", "bottles": "bottles",
        "package": "packages", "packages": "packages",
        "bag": "bags", "bags": "bags",
        "bunch": "bunches", "bunches": "bunches",
        "head": "heads", "heads": "heads",
        
        // Size units
        "small": "small", "medium": "medium", "large": "large",
        "extra large": "extra large", "xl": "extra large"
    ]
}

enum LLMServiceError: Error {
    case invalidURL
    case invalidResponse
    case apiError
    case parsingError
}
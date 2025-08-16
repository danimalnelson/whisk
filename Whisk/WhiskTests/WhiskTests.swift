//
//  WhiskTests.swift
//  WhiskTests
//
//  Created by Dan Nelson on 8/6/25.
//

import Testing
@testable import Whisk

struct WhiskTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testStructuredDataParsing() async throws {
        let llmService = LLMService()
        
        // Test JSON-LD structured data parsing
        let jsonLD = """
        {
            "@type": "Recipe",
            "name": "Test Recipe",
            "recipeIngredient": [
                "2 cups flour",
                "1 cup sugar",
                "3 large eggs"
            ]
        }
        """
        
        let recipe = await llmService.parseStructuredData(jsonLD, originalURL: "https://test.com")
        
        #expect(recipe != nil)
        #expect(recipe?.name == "Test Recipe")
        #expect(recipe?.ingredients.count == 3)
        #expect(recipe?.ingredients.first?.name == "flour")
        #expect(recipe?.ingredients.first?.amount == 2.0)
        #expect(recipe?.ingredients.first?.unit == "cups")
    }
    
    @Test func testRegexParsing() async throws {
        let llmService = LLMService()
        
        // Test regex-based ingredient parsing
        let ingredientContent = """
        2 cups all-purpose flour
        1 cup granulated sugar
        3 large eggs
        1/2 cup milk
        2 tablespoons butter
        """
        
        let ingredients = await llmService.parseIngredientsWithRegex(ingredientContent)
        
        #expect(ingredients != nil)
        #expect(ingredients?.count == 5)
        #expect(ingredients?.first?.name == "all-purpose flour")
        #expect(ingredients?.first?.amount == 2.0)
        #expect(ingredients?.first?.unit == "cups")
    }
    
    @Test func testAmountParsing() async throws {
        let llmService = LLMService()
        
        // Test fraction parsing
        #expect(llmService.parseAmount("1/2") == 0.5)
        #expect(llmService.parseAmount("1/4") == 0.25)
        #expect(llmService.parseAmount("3/4") == 0.75)
        
        // Test mixed numbers
        #expect(llmService.parseAmount("1 1/2") == 1.5)
        #expect(llmService.parseAmount("2 1/4") == 2.25)
        
        // Test whole numbers
        #expect(llmService.parseAmount("3") == 3.0)
        #expect(llmService.parseAmount("10") == 10.0)
    }
    
    @Test func testCaching() async throws {
        let llmService = LLMService()
        
        // Test cache functionality
        let testURL = "https://test.com/recipe"
        let testResult = RecipeParsingResult(
            recipe: Recipe(url: testURL),
            success: true,
            error: nil
        )
        
        // Cache a result
        llmService.cacheResult(testResult, for: testURL)
        
        // Retrieve from cache
        let cachedResult = llmService.getCachedResult(for: testURL)
        
        #expect(cachedResult != nil)
        #expect(cachedResult?.success == true)
        
        // Test cache miss
        let missingResult = llmService.getCachedResult(for: "https://different.com")
        #expect(missingResult == nil)
        
        // Clear cache
        llmService.clearCache()
        let clearedResult = llmService.getCachedResult(for: testURL)
        #expect(clearedResult == nil)
    }
    
    @Test func testPerformanceStats() async throws {
        let llmService = LLMService()
        
        // Test initial stats
        let initialStats = llmService.getPerformanceStats()
        #expect(initialStats.totalRequests == 0)
        #expect(initialStats.cacheHitRate == 0.0)
        
        // Reset stats
        llmService.resetPerformanceStats()
        let resetStats = llmService.getPerformanceStats()
        #expect(resetStats.totalRequests == 0)
    }
    
    @Test func testTokenEstimation() async throws {
        let llmService = LLMService()
        
        // Test token estimation
        let shortText = "Short text"
        let longText = String(repeating: "This is a longer text for testing token estimation. ", count: 100)
        
        let shortTokens = llmService.estimateTokenCount(shortText)
        let longTokens = llmService.estimateTokenCount(longText)
        
        #expect(shortTokens > 0)
        #expect(longTokens > shortTokens)
        
        // Test content truncation
        let truncated = llmService.truncateContent(longText, targetTokens: 50)
        let truncatedTokens = llmService.estimateTokenCount(truncated)
        
        #expect(truncatedTokens <= 50)
    }
    
    @Test func testRecipeTitleExtraction() async throws {
        let llmService = LLMService()
        
        // Test HTML title extraction
        let htmlWithTitle = """
        <html>
        <head>
        <title>Delicious Chocolate Cake Recipe</title>
        </head>
        <body>
        <h1>Chocolate Cake</h1>
        </body>
        </html>
        """
        
        let title = llmService.extractRecipeTitle(from: htmlWithTitle)
        
        #expect(title != nil)
        #expect(title == "Delicious Chocolate Cake Recipe")
    }
}

import SwiftUI

struct RecipeInputView: View {
    @StateObject private var llmService = LLMService(apiKey: "YOUR_API_KEY") // TODO: Get from secure storage
    @ObservedObject var dataManager: DataManager
    
    @State private var recipeURLs: [String] = []
    @State private var newURL: String = ""
    @State private var isParsing = false
    @State private var parsingProgress: Double = 0.0
    @State private var parsingResults: [RecipeParsingResult] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // URL Input Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Recipe URLs")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter recipe URL", text: $newURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        
                        Button("Add") {
                            addURL()
                        }
                        .disabled(newURL.isEmpty)
                    }
                }
                .padding(.horizontal)
                
                // URL List
                if !recipeURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recipe URLs (\(recipeURLs.count))")
                            .font(.headline)
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(recipeURLs.indices, id: \.self) { index in
                                    HStack {
                                        Text(recipeURLs[index])
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Button("Remove") {
                                            recipeURLs.remove(at: index)
                                        }
                                        .foregroundColor(.red)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Parse Button
                Button(action: parseRecipes) {
                    HStack {
                        if isParsing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        
                        Text(isParsing ? "Parsing Recipes..." : "Parse Recipes")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(recipeURLs.isEmpty || isParsing)
                .padding(.horizontal)
                
                // Progress Bar
                if isParsing {
                    VStack(spacing: 8) {
                        ProgressView(value: parsingProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text("\(Int(parsingProgress * 100))% Complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Add Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addURL() {
        guard !newURL.isEmpty else { return }
        
        // Basic URL validation
        if newURL.hasPrefix("http://") || newURL.hasPrefix("https://") {
            recipeURLs.append(newURL)
            newURL = ""
        } else {
            errorMessage = "Please enter a valid URL starting with http:// or https://"
            showError = true
        }
    }
    
    private func parseRecipes() {
        guard !recipeURLs.isEmpty else { return }
        
        isParsing = true
        parsingProgress = 0.0
        parsingResults = []
        
        Task {
            for (index, url) in recipeURLs.enumerated() {
                do {
                    let result = try await llmService.parseRecipe(from: url)
                    parsingResults.append(result)
                    
                    // Update progress
                    await MainActor.run {
                        parsingProgress = Double(index + 1) / Double(recipeURLs.count)
                    }
                } catch {
                    let errorResult = RecipeParsingResult(
                        recipe: Recipe(url: url),
                        success: false,
                        error: error.localizedDescription
                    )
                    parsingResults.append(errorResult)
                }
            }
            
            // Process results
            await MainActor.run {
                processParsingResults()
                isParsing = false
            }
        }
    }
    
    private func processParsingResults() {
        var allIngredients: [Ingredient] = []
        
        for result in parsingResults {
            if result.success {
                allIngredients.append(contentsOf: result.recipe.ingredients)
            }
        }
        
        // Add ingredients to current list
        dataManager.addIngredientsToCurrentList(allIngredients)
        
        // Show results summary
        let successCount = parsingResults.filter { $0.success }.count
        let totalCount = parsingResults.count
        
        if successCount < totalCount {
            errorMessage = "Successfully parsed \(successCount) of \(totalCount) recipes. Some recipes failed to parse."
            showError = true
        }
    }
}

#Preview {
    RecipeInputView(dataManager: DataManager())
} 

import SwiftUI

struct RecipeInputView: View {
    @StateObject private var llmService = LLMService() // API key managed on Vercel
    @ObservedObject var dataManager: DataManager
    let targetList: GroceryList? // Optional: if nil, use current list
    @Environment(\.dismiss) private var dismiss
    
    init(dataManager: DataManager, targetList: GroceryList? = nil) {
        self.dataManager = dataManager
        self.targetList = targetList
    }
    
    @State private var recipeURLs: [String] = []
    @State private var newURL: String = ""
    @State private var isParsing = false
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
                            .autocapitalization(.none)
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
                        
                        Text(isParsing ? "Creating list..." : "Create list")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(recipeURLs.isEmpty || isParsing)
                .padding(.horizontal)
            }
            .navigationTitle("Add Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addURL() {
        let trimmedURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty && !recipeURLs.contains(trimmedURL) {
            recipeURLs.append(trimmedURL)
            newURL = ""
        }
    }
    
    private func parseRecipes() {
        guard !recipeURLs.isEmpty else { return }
        
        // Start timing the entire parsing process
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⏱️ Starting recipe parsing timer...")
        
        isParsing = true
        parsingResults.removeAll()
        
        Task {
            var successCount = 0
            let totalCount = recipeURLs.count
            var individualTimings: [Double] = []
            
            for (index, url) in recipeURLs.enumerated() {
                let recipeStartTime = CFAbsoluteTimeGetCurrent()
                print("📋 Processing recipe \(index + 1)/\(totalCount): \(url)")
                
                do {
                    let result = try await llmService.parseRecipe(from: url)
                    let recipeEndTime = CFAbsoluteTimeGetCurrent()
                    let recipeDuration = recipeEndTime - recipeStartTime
                    individualTimings.append(recipeDuration)
                    
                    print("⏱️ Recipe \(index + 1) completed in \(String(format: "%.2f", recipeDuration)) seconds")
                    
                    await MainActor.run {
                        parsingResults.append(result)
                        
                        if result.success {
                            successCount += 1
                            print("📋 Success count: \(successCount), Total count: \(totalCount)")
                            
                            // Add ingredients to the target list
                            if result.recipe.ingredients.count > 0 {
                                addIngredientsToGroceryList(result.recipe.ingredients)
                            }
                        } else {
                            print("❌ Failed to parse recipe: \(result.error ?? "Unknown error")")
                        }
                    }
                } catch {
                    let recipeEndTime = CFAbsoluteTimeGetCurrent()
                    let recipeDuration = recipeEndTime - recipeStartTime
                    individualTimings.append(recipeDuration)
                    
                    print("⏱️ Recipe \(index + 1) failed after \(String(format: "%.2f", recipeDuration)) seconds")
                    
                    await MainActor.run {
                        let errorResult = RecipeParsingResult(recipe: Recipe(url: url), success: false, error: error.localizedDescription)
                        parsingResults.append(errorResult)
                        print("❌ Error parsing recipe: \(error.localizedDescription)")
                    }
                }
            }
            
            await MainActor.run {
                let totalEndTime = CFAbsoluteTimeGetCurrent()
                let totalDuration = totalEndTime - startTime
                
                // Log comprehensive timing statistics
                print("⏱️ === PARSING TIMING SUMMARY ===")
                print("⏱️ Total parsing time: \(String(format: "%.2f", totalDuration)) seconds")
                print("⏱️ Number of recipes processed: \(totalCount)")
                print("⏱️ Successful recipes: \(successCount)")
                print("⏱️ Failed recipes: \(totalCount - successCount)")
                
                if !individualTimings.isEmpty {
                    let averageTime = individualTimings.reduce(0, +) / Double(individualTimings.count)
                    let minTime = individualTimings.min() ?? 0
                    let maxTime = individualTimings.max() ?? 0
                    
                    print("⏱️ Average time per recipe: \(String(format: "%.2f", averageTime)) seconds")
                    print("⏱️ Fastest recipe: \(String(format: "%.2f", minTime)) seconds")
                    print("⏱️ Slowest recipe: \(String(format: "%.2f", maxTime)) seconds")
                }
                
                // Log success/failure summary
                if successCount == totalCount {
                    print("✅ All recipes parsed successfully!")
                } else if successCount > 0 {
                    print("⚠️ \(successCount)/\(totalCount) recipes parsed successfully")
                } else {
                    print("❌ All recipes failed to parse")
                }
                
                print("⏱️ === END TIMING SUMMARY ===")
                
                isParsing = false
                
                // Show summary
                let successRate = Double(successCount) / Double(totalCount)
                if successRate >= 0.5 {
                    // Most recipes succeeded, dismiss
                    dismiss()
                } else {
                    // Many failures, show error
                    showError = true
                    errorMessage = "Failed to parse \(totalCount - successCount) out of \(totalCount) recipes. Please check the URLs and try again."
                }
            }
        }
    }
    
    private func addIngredientsToGroceryList(_ ingredients: [Ingredient]) {
        let targetGroceryList = targetList ?? dataManager.currentList
        
        if let targetList = targetGroceryList {
            dataManager.addIngredientsToList(ingredients, list: targetList)
        } else {
            dataManager.addIngredientsToCurrentList(ingredients)
        }
    }
}

#Preview {
    RecipeInputView(dataManager: DataManager())
} 
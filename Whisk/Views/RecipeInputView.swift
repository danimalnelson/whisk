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
    
    @State private var recipeEntries: [RecipeEntry] = []
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemFill))
                        HStack(spacing: 8) {
                            TextField("Enter recipe URL", text: $newURL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .foregroundColor(.white)
                                .frame(height: 38)
                            Button("Add") { addURL() }
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(newURL.isEmpty ? Color.gray.opacity(0.3) : Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                                .disabled(newURL.isEmpty)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .frame(height: 50)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                // URL List
                if !recipeEntries.isEmpty {
                    List {
                        ForEach(recipeEntries) { entry in
                            RecipeRowView(entry: entry)
                                .listRowBackground(Color.clear)
                                .background(Color.clear)
                        }
                        .onDelete { indexSet in
                            recipeEntries.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                
                Spacer()
                
                // Parse Button
                Button(action: parseRecipes) {
                    HStack {
                        if isParsing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        }
                        // Dynamic button label based on whether list already has ingredients
                        let listHasItems = !((targetList ?? dataManager.currentList)?.ingredients.isEmpty ?? true)
                        Text(isParsing ? (listHasItems ? "Adding..." : "Creating...") : (listHasItems ? "Add to list" : "Create list"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                }
                .disabled(recipeEntries.isEmpty || isParsing || recipeEntries.contains(where: { $0.error != nil }))
                .padding(.horizontal)
            }
            .navigationTitle("Add recipes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .preferredColorScheme(.dark)
        }
    }
    
    private func addURL() {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Normalize: if missing scheme but looks like a domain, assume https
        var candidate = trimmed
        if URL(string: candidate)?.scheme == nil {
            if (candidate.hasPrefix("www.") || (candidate.contains(".") && !candidate.contains(" "))) {
                candidate = "https://" + candidate
            }
        }
        guard !recipeEntries.contains(where: { $0.url == candidate }) else { newURL = ""; return }
        var placeholder = RecipeEntry(url: candidate)
        recipeEntries.append(placeholder)
        newURL = ""
        // Pre-validate if this looks like a recipe to give fast feedback
        Task {
            let looksRecipe = await llmService.validateIsLikelyRecipe(url: candidate)
            await MainActor.run {
                if let idx = recipeEntries.firstIndex(where: { $0.url == candidate }) {
                    if !looksRecipe {
                        placeholder.error = "This URL doesn't look like a recipe page. Remove it to continue."
                        recipeEntries[idx] = placeholder
                    }
                }
            }
            await enrichEntry(for: candidate)
        }
    }
    
    private func parseRecipes() {
        guard !recipeEntries.isEmpty else { return }
        
        // Start timing the entire parsing process
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⏱️ Starting parallel recipe parsing timer...")
        
        isParsing = true
        parsingResults.removeAll()
        
        Task {
            let totalCount = recipeEntries.count
            var individualTimings: [Double] = []
            var successCount = 0
            
            // Use TaskGroup to process recipes in parallel
            await withTaskGroup(of: (Int, RecipeParsingResult, Double).self) { group in
                // Add all recipes to the task group
                for (index, entry) in recipeEntries.enumerated() {
                    group.addTask {
                        let recipeStartTime = CFAbsoluteTimeGetCurrent()
                        print("📋 Processing recipe \(index + 1)/\(totalCount): \(entry.url)")
                        
                        do {
                            let result = try await self.llmService.parseRecipe(from: entry.url)
                            let recipeEndTime = CFAbsoluteTimeGetCurrent()
                            let recipeDuration = recipeEndTime - recipeStartTime
                            
                            print("⏱️ Recipe \(index + 1) completed in \(String(format: "%.2f", recipeDuration)) seconds")
                            
                            return (index, result, recipeDuration)
                        } catch {
                            let recipeEndTime = CFAbsoluteTimeGetCurrent()
                            let recipeDuration = recipeEndTime - recipeStartTime
                            
                            print("⏱️ Recipe \(index + 1) failed after \(String(format: "%.2f", recipeDuration)) seconds")
                            
                            let errorResult = RecipeParsingResult(recipe: Recipe(url: entry.url), success: false, error: error.localizedDescription)
                            return (index, errorResult, recipeDuration)
                        }
                    }
                }
                
                // Collect results as they complete
                for await (_, result, duration) in group {
                    individualTimings.append(duration)
                    
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
                            // mark the entry with an error for inline display
                            if let idx = recipeEntries.firstIndex(where: { $0.url == result.recipe.url }) {
                                var e = recipeEntries[idx]
                                e.error = result.error ?? "This URL doesn't look like a recipe page."
                                recipeEntries[idx] = e
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                let totalEndTime = CFAbsoluteTimeGetCurrent()
                let totalDuration = totalEndTime - startTime
                
                // Log comprehensive timing statistics
                print("⏱️ === PARALLEL PARSING TIMING SUMMARY ===")
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
                    
                    // Calculate parallelization efficiency
                    let sequentialTime = individualTimings.reduce(0, +)
                    let efficiency = (sequentialTime / totalDuration) * 100
                    print("⏱️ Parallelization efficiency: \(String(format: "%.1f", efficiency))%")
                }
                
                // Log success/failure summary
                if successCount == totalCount {
                    print("✅ All recipes parsed successfully!")
                } else if successCount > 0 {
                    print("⚠️ \(successCount)/\(totalCount) recipes parsed successfully")
                } else {
                    print("❌ All recipes failed to parse")
                }
                
                print("⏱️ === END PARALLEL TIMING SUMMARY ===")
                
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

        // Prefetch ingredient images to improve subsequent list performance
        let names = ingredients.map { $0.name }
        IngredientImageService.shared.prefetch(ingredientNames: names)
    }
}

#Preview {
    RecipeInputView(dataManager: DataManager())
} 

// MARK: - Recipe Row & Metadata

private struct RecipeEntry: Identifiable, Hashable {
    let id = UUID()
    let url: String
    var title: String? = nil
    var siteName: String? = nil
    var faviconURL: URL? = nil
    var error: String? = nil
}

private struct RecipeRowView: View {
    let entry: RecipeEntry
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: entry.faviconURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 45, height: 45)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 45, height: 45)
                        .clipped()
                        .cornerRadius(6)
                        .transition(.opacity.combined(with: .scale))
                case .failure:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                        .overlay(Image(systemName: "globe").foregroundColor(.secondary))
                        .frame(width: 45, height: 45)
                @unknown default:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 45, height: 45)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text((entry.title ?? formattedURLTitle(entry.url)).isEmpty ? formattedURLTitle(entry.url) : (entry.title ?? "")).lineLimit(2)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.primary)
                if let error = entry.error {
                    Text(error)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.red)
                        .lineLimit(2)
                } else {
                    Text(entry.siteName ?? RecipeRowView.friendlySiteName(from: entry.url))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private func formattedURLTitle(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        var lastPath = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        lastPath = lastPath.replacingOccurrences(of: "_", with: " ")
        return lastPath.capitalized
    }
    
    static func friendlySiteName(from urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "" }
        // Strip www.
        let clean = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        // Known brands
        let brands: [String: String] = [
            "seriouseats.com": "Serious Eats",
            "foodandwine.com": "Food & Wine",
            "bonappetit.com": "Bon Appétit",
            "allrecipes.com": "Allrecipes",
            "nytimes.com": "NYTimes Cooking"
        ]
        if let b = brands[clean] { return b }
        // Generic: use second-level domain and prettify
        let parts = clean.split(separator: ".")
        let sld = parts.dropLast().last.map(String.init) ?? clean
        let pretty = sld.replacingOccurrences(of: "and", with: " & ")
        return pretty.capitalized
    }
}

private func faviconURL(for urlString: String) -> URL? {
    guard let host = URL(string: urlString)?.host else { return nil }
    // High-res favicon proxy
    return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")
}

private extension RecipeInputView {
    func enrichEntry(for urlString: String) async {
        guard let idx = recipeEntries.firstIndex(where: { $0.url == urlString }) else { return }
        var entry = recipeEntries[idx]
        entry.faviconURL = faviconURL(for: urlString)
        // Fetch title quickly
        if let (title, site) = await fetchTitleAndSite(urlString) {
            entry.title = title
            entry.siteName = site
        } else {
            entry.siteName = RecipeRowView.friendlySiteName(from: urlString)
        }
        await MainActor.run {
            recipeEntries[idx] = entry
        }
    }
    
    func fetchTitleAndSite(_ urlString: String) async -> (String, String)? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            // Extract title using NSRegularExpression with dotAll
            let nshtml = html as NSString
            let pattern = "(?s).*<title[^>]*>(.*?)</title>.*"
            if let rx = try? NSRegularExpression(pattern: pattern, options: []),
               let m = rx.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nshtml.length)),
               m.numberOfRanges >= 2 {
                let r = m.range(at: 1)
                var title = nshtml.substring(with: r)
                title = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                title = title.replacingOccurrences(of: "\n", with: " ")
                // Derive site from title separators
                var site = ""
                if let sepRange = title.range(of: #"\s[\-\|]\s"#, options: .regularExpression) {
                    let rhs = String(title[sepRange.upperBound...])
                    site = rhs.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                } else {
                    site = RecipeRowView.friendlySiteName(from: urlString)
                }
                return (title, site)
            }
            return nil
        } catch {
            return nil
        }
    }
}
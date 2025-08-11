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
    
    struct URLItem: Identifiable, Equatable {
        let id: UUID = UUID()
        let url: String
        var title: String?
        var domainDisplay: String
        var host: String
        var faviconURL: URL?
        var isLoading: Bool = true
    }
    
    @State private var urlItems: [URLItem] = []
    @State private var newURL: String = ""
    @State private var isParsing = false
    @State private var parsingResults: [RecipeParsingResult] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // URL Input Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        Text("Add recipe URLs")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("Enter recipe URL", text: $newURL)
                            .textFieldStyle(DarkTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: addURL) {
                            Text("Add")
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(newURL.isEmpty ? Color(.secondarySystemFill) : Color.blue)
                                .foregroundColor(newURL.isEmpty ? Color(.secondaryLabel) : .white)
                                .cornerRadius(10)
                        }
                        .disabled(newURL.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                
                // URL List (no header, edge-to-edge like ingredient list)
                if !urlItems.isEmpty {
                    List {
                        ForEach(urlItems) { item in
                            URLRow(item: item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let idx = urlItems.firstIndex(of: item) { urlItems.remove(at: idx) }
                                    } label: { Label("Remove", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .listRowBackground(Color.black)
                    .background(Color.black)
                    .frame(maxHeight: 260)
                }
                
                Spacer()
                
                // Parse Button
                Button(action: parseRecipes) {
                    HStack(spacing: 8) {
                        if isParsing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down.on.square")
                        }
                        Text(isParsing ? "Adding recipes..." : "Add recipes")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }
                .disabled(urlItems.isEmpty || isParsing)
                .padding(.bottom, 10)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Add Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addURL() {
        let trimmedURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL), let host = url.host else { return }
        if urlItems.contains(where: { $0.url == trimmedURL }) { return }
        let display = displayName(forHost: host)
        let favicon = faviconURL(forHost: host)
        var item = URLItem(url: trimmedURL, title: prettifyTitle(from: url), domainDisplay: display, host: host, faviconURL: favicon, isLoading: true)
        urlItems.append(item)
        newURL = ""
        Task { await fetchMetadata(for: item.id, url: url) }
    }
    
    private func parseRecipes() {
        guard !urlItems.isEmpty else { return }
        
        // Start timing the entire parsing process
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⏱️ Starting parallel recipe parsing timer...")
        
        isParsing = true
        parsingResults.removeAll()
        
        Task {
            let urls = urlItems.map { $0.url }
            let totalCount = urls.count
            var individualTimings: [Double] = []
            var successCount = 0
            
            // Use TaskGroup to process recipes in parallel
            await withTaskGroup(of: (Int, RecipeParsingResult, Double).self) { group in
                // Add all recipes to the task group
                for (index, url) in urls.enumerated() {
                    group.addTask {
                        let recipeStartTime = CFAbsoluteTimeGetCurrent()
                        print("📋 Processing recipe \(index + 1)/\(totalCount): \(url)")
                        
                        do {
                            let result = try await self.llmService.parseRecipe(from: url)
                            let recipeEndTime = CFAbsoluteTimeGetCurrent()
                            let recipeDuration = recipeEndTime - recipeStartTime
                            
                            print("⏱️ Recipe \(index + 1) completed in \(String(format: "%.2f", recipeDuration)) seconds")
                            
                            return (index, result, recipeDuration)
                        } catch {
                            let recipeEndTime = CFAbsoluteTimeGetCurrent()
                            let recipeDuration = recipeEndTime - recipeStartTime
                            
                            print("⏱️ Recipe \(index + 1) failed after \(String(format: "%.2f", recipeDuration)) seconds")
                            
                            let errorResult = RecipeParsingResult(recipe: Recipe(url: url), success: false, error: error.localizedDescription)
                            return (index, errorResult, recipeDuration)
                        }
                    }
                }
                
                // Collect results as they complete
                for await (index, result, duration) in group {
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
    
    // MARK: - Metadata Helpers
    private func fetchMetadata(for id: UUID, url: URL) async {
        var title: String? = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                if let siteName = matchFirst(in: html, pattern: "(?i)<meta[^>]+property=\\\"og:site_name\\\"[^>]+content=\\\"([^\\\"]+)\\\"") {
                    // Prefer og:site_name over host-derived when available
                    await MainActor.run {
                        if let idx = urlItems.firstIndex(where: { $0.id == id }) {
                            urlItems[idx].domainDisplay = siteName
                        }
                    }
                }
                if let t = matchFirst(in: html, pattern: "(?i)<title[^>]*>(.*?)</title>") {
                    title = cleanTitle(t)
                }
                if let iconURL = await bestFaviconURL(html: html, pageURL: url) {
                    await MainActor.run {
                        if let idx = urlItems.firstIndex(where: { $0.id == id }) {
                            urlItems[idx].faviconURL = iconURL
                        }
                    }
                }
            }
        } catch {
            // ignore fetch errors; keep defaults
        }
        await MainActor.run {
            if let idx = urlItems.firstIndex(where: { $0.id == id }) {
                urlItems[idx].title = title ?? prettifyTitle(from: url)
                urlItems[idx].isLoading = false
            }
        }
    }
    
    private func bestFaviconURL(html: String, pageURL: URL) async -> URL? {
        struct IconCandidate { let url: URL; let score: Int }
        var candidates: [IconCandidate] = []

        // 1) Parse link rel icons
        let patterns = [
            "(?i)<link[^>]+rel=\\\"(?:apple-touch-icon|apple-touch-icon-precomposed)\\\"[^>]*href=\\\"([^\\\"]+)\\\"[^>]*?(?:sizes=\\\"([^\\\"]+)\\\")?",
            "(?i)<link[^>]+rel=\\\"(?:icon|shortcut icon)\\\"[^>]*href=\\\"([^\\\"]+)\\\"[^>]*?(?:sizes=\\\"([^\\\"]+)\\\")?"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(html.startIndex..., in: html)
                regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                    guard let match = match, match.numberOfRanges >= 2,
                          let hrefRange = Range(match.range(at: 1), in: html) else { return }
                    let href = String(html[hrefRange])
                    let sizes: String?
                    if match.numberOfRanges >= 3, let sizeRange = Range(match.range(at: 2), in: html) {
                        sizes = String(html[sizeRange])
                    } else {
                        sizes = nil
                    }
                    if let absolute = URL(string: href, relativeTo: pageURL)?.absoluteURL {
                        let sizeScore = parseSizeScore(from: sizes)
                        candidates.append(IconCandidate(url: absolute, score: sizeScore))
                    }
                }
            }
        }

        // 2) Parse web app manifest
        if let manifestHref = matchFirst(in: html, pattern: "(?i)<link[^>]+rel=\\\"manifest\\\"[^>]+href=\\\"([^\\\"]+)\\\"") {
            if let manifestURL = URL(string: manifestHref, relativeTo: pageURL) {
                if let (data, _) = try? await URLSession.shared.data(from: manifestURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let icons = json["icons"] as? [[String: Any]] {
                    for icon in icons {
                        if let src = icon["src"] as? String,
                           let abs = URL(string: src, relativeTo: manifestURL)?.absoluteURL {
                            let sizes = icon["sizes"] as? String
                            let score = parseSizeScore(from: sizes)
                            candidates.append(IconCandidate(url: abs, score: score + 10)) // prefer manifest icons slightly
                        }
                    }
                }
            }
        }

        // 3) Add common fallbacks
        if let host = pageURL.host, let scheme = pageURL.scheme {
            if let fallback = URL(string: "\(scheme)://\(host)/favicon.ico") { candidates.append(IconCandidate(url: fallback, score: 16)) }
            if let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") { candidates.append(IconCandidate(url: google, score: 24)) }
        }

        // Choose best by highest score
        return candidates.sorted { $0.score > $1.score }.first?.url
    }

    private func parseSizeScore(from sizes: String?) -> Int {
        guard let sizes = sizes, !sizes.isEmpty else { return 0 }
        // sizes like "16x16 32x32 180x180" → choose largest
        let tokens = sizes.split(separator: " ")
        var maxSide = 0
        for t in tokens {
            let parts = t.split(separator: "x")
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                maxSide = max(maxSide, max(w, h))
            }
        }
        return maxSide
    }

    private func matchFirst(in text: String, pattern: String) -> String? {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = regex.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) {
                return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func cleanTitle(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\n", with: " ")
        t = t.replacingOccurrences(of: #"\s*[-|]\s*.*$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s*\|\s*.*$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s*Recipe\s*$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func prettifyTitle(from url: URL) -> String {
        // Fallback: use last path component with dashes replaced
        let last = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        if last.count > 2 { return last.capitalized }
        return url.host?.replacingOccurrences(of: "www.", with: "").capitalized ?? url.absoluteString
    }
    
    private func displayName(forHost host: String) -> String {
        let base = host.replacingOccurrences(of: "www.", with: "")
        let comps = base.split(separator: ".")
        let sld = comps.count >= 2 ? comps[comps.count-2] : Substring(base)
        return sld.replacingOccurrences(of: "-", with: " ").capitalized
    }
    
    private func faviconURL(forHost host: String) -> URL? {
        // DuckDuckGo icons service provides consistent favicons
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }
    
    // MARK: - Row View
    private struct URLRow: View {
        let item: URLItem
        
        var body: some View {
            HStack(spacing: 12) {
                // Match ingredient row thumbnail sizing (30x45, rounded)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemFill))
                    AsyncImage(url: item.faviconURL) { phase in
                        switch phase {
                        case .empty:
                            EmptyView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "globe")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .frame(width: 45, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? item.domainDisplay)
                        .font(.system(size: 16, weight: .regular))
                        .lineLimit(1)
                    Text(item.domainDisplay)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
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
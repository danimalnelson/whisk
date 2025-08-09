import Foundation
import SwiftUI

/// Centralized service to resolve ingredient names to image URLs and optionally prefetch/cache them.
final class IngredientImageService {
    static let shared = IngredientImageService()

    /// Base URL for ingredient images. Replace with your CDN.
    private var baseURLString: String { Config.ingredientImageBaseURL }

    /// Known aliases mapping non-canonical names to canonical slugs.
    /// Extend this list over time or fetch remotely.
    private var aliasMap: [String: String] = [
        // Herbs & greens
        "scallion": "green-onion",
        "scallions": "green-onion",
        "green onions": "green-onion",
        "spring onions": "green-onion",
        "coriander": "cilantro",
        "coriander leaves": "cilantro",
        "cilantro leaves": "cilantro",
        // Specific herb forms
        "tarragon sprigs": "tarragon",
        "capsicum": "bell-pepper",
        "aubergine": "eggplant",
        "courgette": "zucchini",
        // Dairy & basics
        "powdered sugar": "confectioners-sugar",
        "confectioners sugar": "confectioners-sugar",
        "caster sugar": "superfine-sugar",
        // Canned/packaged
        "chick peas": "chickpea",
        "garbanzo beans": "chickpea",
        // Common plurals or variants
        "bell peppers": "bell-pepper",
        "red bell peppers": "red-bell-pepper",
        "tomatoes": "tomato",
        "shallots": "shallot",
        "avocados": "avocado",
        "onions": "onion",
        "peppers": "pepper"
    ]

    /// Descriptors to drop when slugging.
    private let descriptors: Set<String> = [
        "fresh", "dried", "ripe", "unripe", "organic", "large", "small", "medium",
        "sliced", "diced", "chopped", "minced", "grated", "peeled", "seeded",
        "thin", "thick", "whole", "raw", "frozen",
        // Quantity nouns that shouldn't affect the slug
        "sprig", "sprigs", "bunch", "bunches", "clove", "cloves", "leaf", "leaves", "stalk", "stalks", "stem", "stems"
    ]

    /// Cache to prevent repeated prefetch for the same slug.
    private var prefetchedSlugs = Set<String>()
    private var remoteAliasLoaded = false

    private init() {}

    /// Optionally load a remote alias map JSON from the bundle or network.
    func loadRemoteAliasesIfNeeded() {
        guard !remoteAliasLoaded else { return }
        remoteAliasLoaded = true
        // Attempt to load `ingredient_aliases.json` from bundle first
        if let url = Bundle.main.url(forResource: "ingredient_aliases", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            // Merge, prefer remote entries
            for (k, v) in dict { aliasMap[k.lowercased()] = v }
            return
        }
        // Optionally: fetch from network (placeholder; no-op by default)
    }

    /// Returns a URL for the given ingredient name.
    func url(for ingredientName: String) -> URL? {
        loadRemoteAliasesIfNeeded()
        let slug = slug(from: ingredientName)
        let urlString = "\(baseURLString)/\(slug).webp"
        return URL(string: urlString)
    }

    /// Create a canonical slug from a possibly noisy ingredient name.
    func slug(from name: String) -> String {
        loadRemoteAliasesIfNeeded()
        let lower = name.lowercased()

        // Quick alias override if full string matches
        if let direct = aliasMap[lower] { return direct }

        // Keep alphanumerics and space/hyphen, everything else to space
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "- "))
        let filtered = lower.unicodeScalars.map { allowedChars.contains($0) ? Character($0) : " " }
        var tokens = String(filtered)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .split(separator: " ")
            .map { String($0) }

        // Remove descriptors
        tokens.removeAll { descriptors.contains($0) }

        // Re-join and singularize a few simple cases
        let joined = tokens.joined(separator: " ")

        // Check alias again on joined phrase
        if let alias = aliasMap[joined] { return alias }

        let singular = IngredientImageService.singularize(joined)
            .replacingOccurrences(of: "asparagu", with: "asparagus")
        return singular.replacingOccurrences(of: " ", with: "-")
    }

    /// Very light singularization for common English plural endings.
    private static func singularize(_ word: String) -> String {
        guard !word.isEmpty else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("es") { return String(word.dropLast(2)) }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// Prefetch a set of ingredient names by downloading their images into URLCache.
    func prefetch(ingredientNames: [String]) {
        let slugs = Set(ingredientNames.map { slug(from: $0) })
        let newSlugs = slugs.subtracting(prefetchedSlugs)
        guard !newSlugs.isEmpty else { return }

        for slug in newSlugs {
            guard let url = URL(string: "\(baseURLString)/\(slug).webp") else { continue }
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let data = data, let response = response {
                    let cached = CachedURLResponse(response: response, data: data)
                    URLCache.shared.storeCachedResponse(cached, for: request)
                }
                // Record regardless to avoid reattempt storm; real impl could be smarter
                self?.prefetchedSlugs.insert(slug)
            }
            task.resume()
        }
    }
}



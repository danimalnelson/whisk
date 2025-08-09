import Foundation

enum Config {
    /// Ingredient image CDN base URL. Override via Info.plist key `IngredientImageBaseURL`.
    static var ingredientImageBaseURL: String {
        if let dict = Bundle.main.infoDictionary,
           let value = dict["IngredientImageBaseURL"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        // Default; replace with your CDN
        return "https://whisk-server-git-ingredient-images-dannelson.vercel.app/ingredients"
    }

    /// Cache-busting version for ingredient images to avoid stale 404s from prior deploys.
    /// Override via Info.plist key `IngredientImageAssetsVersion`.
    static var ingredientImageAssetsVersion: String {
        if let dict = Bundle.main.infoDictionary,
           let value = dict["IngredientImageAssetsVersion"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        // Bump this whenever images are added/renamed on the CDN.
        return "2"
    }
}



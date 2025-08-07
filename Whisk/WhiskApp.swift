import SwiftUI
import CoreText

@main
struct WhiskApp: App {
    init() {
        // Register Inter fonts
        registerInterFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.font, .system(.body))
                .preferredColorScheme(.dark)
        }
    }
    
    private func registerInterFonts() {
        // Register all Inter font variants
        let fontNames = [
            "Inter-Thin",
            "Inter-ExtraLight", 
            "Inter-Light",
            "Inter-Regular",
            "Inter-Medium",
            "Inter-SemiBold",
            "Inter-Bold",
            "Inter-ExtraBold",
            "Inter-Black"
        ]
        
        for fontName in fontNames {
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: "otf") {
                var error: Unmanaged<CFError>?
                let success = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
                if !success {
                    if let error = error?.takeRetainedValue() {
                        print("Failed to register font \(fontName): \(error)")
                    } else {
                        print("Failed to register font \(fontName): Unknown error")
                    }
                }
            } else {
                print("Font file not found: \(fontName).otf")
            }
        }
    }
}

import SwiftUI
import CoreText
import UIKit

@main
struct WhiskApp: App {
    init() {
        // Register Inter fonts
        registerInterFonts()

        // Configure navigation bar title font sizes
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        // Apply appearance to all nav bar states
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
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

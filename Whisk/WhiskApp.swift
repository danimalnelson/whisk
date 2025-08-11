import SwiftUI
import CoreText
import UIKit

@main
struct WhiskApp: App {
    init() {
        // Register Inter fonts
        registerInterFonts()

        // Keep scroll/pinned behavior idiomatic: black at top (large), translucent when pinned (inline)
        let standard = UINavigationBarAppearance()
        standard.configureWithTransparentBackground()
        standard.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        let interBold18 = UIFont(name: "Inter-Bold", size: 18) ?? UIFont.systemFont(ofSize: 18, weight: .bold)
        standard.titleTextAttributes = [
            .font: interBold18,
            .foregroundColor: UIColor.white
        ]
        // Show a subtle separator when pinned (inline)
        standard.shadowColor = UIColor.separator

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithOpaqueBackground()
        scrollEdge.backgroundColor = .black
        let interBold34 = UIFont(name: "Inter-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        scrollEdge.largeTitleTextAttributes = [
            .font: interBold34,
            .foregroundColor: UIColor.white
        ]
        scrollEdge.titleTextAttributes = [
            .font: interBold18,
            .foregroundColor: UIColor.white
        ]
        // Remove bottom border when large (not pinned)
        scrollEdge.shadowColor = .clear

        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().compactAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.font, .interBody())
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

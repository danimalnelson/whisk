import SwiftUI

// MARK: - Design System
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Dark theme colors
        static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
        static let surface = Color(red: 0.12, green: 0.12, blue: 0.15)
        static let surfaceSecondary = Color(red: 0.18, green: 0.18, blue: 0.22)
        static let text = Color(red: 0.95, green: 0.95, blue: 0.97)
        static let textSecondary = Color(red: 0.7, green: 0.7, blue: 0.75)
        static let accent = Color(red: 0.2, green: 0.6, blue: 1.0)
        static let accentSecondary = Color(red: 0.15, green: 0.5, blue: 0.9)
        static let success = Color(red: 0.2, green: 0.8, blue: 0.4)
        static let warning = Color(red: 1.0, green: 0.7, blue: 0.2)
        static let error = Color(red: 1.0, green: 0.4, blue: 0.4)
        static let border = Color(red: 0.25, green: 0.25, blue: 0.3)
        static let separator = Color(red: 0.2, green: 0.2, blue: 0.25)
    }
    
    // MARK: - Typography
    struct Typography {
        static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            let fontName: String
            
            switch weight {
            case .ultraLight: fontName = "Inter-Thin"
            case .thin: fontName = "Inter-ExtraLight"
            case .light: fontName = "Inter-Light"
            case .regular: fontName = "Inter-Regular"
            case .medium: fontName = "Inter-Medium"
            case .semibold: fontName = "Inter-SemiBold"
            case .bold: fontName = "Inter-Bold"
            case .heavy: fontName = "Inter-ExtraBold"
            case .black: fontName = "Inter-Black"
            default: fontName = "Inter-Regular"
            }
            
            return Font.custom(fontName, size: size)
        }
        
        // Predefined text styles
        static let title = inter(28, weight: .bold)
        static let headline = inter(20, weight: .semibold)
        static let body = inter(16, weight: .regular)
        static let caption = inter(14, weight: .regular)
        static let small = inter(12, weight: .regular)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }
}

// MARK: - View Modifiers
struct DarkBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(DesignSystem.Colors.background)
    }
}

struct DarkTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundColor(DesignSystem.Colors.text)
    }
}

struct DarkTextSecondaryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundColor(DesignSystem.Colors.textSecondary)
    }
}

// MARK: - View Extensions
extension View {
    func darkBackground() -> some View {
        modifier(DarkBackgroundModifier())
    }
    
    func darkText() -> some View {
        modifier(DarkTextModifier())
    }
    
    func darkTextSecondary() -> some View {
        modifier(DarkTextSecondaryModifier())
    }
}

// MARK: - Text Extensions
extension Text {
    func titleStyle() -> some View {
        self.font(DesignSystem.Typography.title)
            .darkText()
    }
    
    func headlineStyle() -> some View {
        self.font(DesignSystem.Typography.headline)
            .darkText()
    }
    
    func bodyStyle() -> some View {
        self.font(DesignSystem.Typography.body)
            .darkText()
    }
    
    func captionStyle() -> some View {
        self.font(DesignSystem.Typography.caption)
            .darkTextSecondary()
    }
    
    func smallStyle() -> some View {
        self.font(DesignSystem.Typography.small)
            .darkTextSecondary()
    }
}

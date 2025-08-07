import SwiftUI

extension Font {
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        
        switch weight {
        case .ultraLight:
            fontName = "Inter-Thin"
        case .thin:
            fontName = "Inter-ExtraLight"
        case .light:
            fontName = "Inter-Light"
        case .regular:
            fontName = "Inter-Regular"
        case .medium:
            fontName = "Inter-Medium"
        case .semibold:
            fontName = "Inter-SemiBold"
        case .bold:
            fontName = "Inter-Bold"
        case .heavy:
            fontName = "Inter-ExtraBold"
        case .black:
            fontName = "Inter-Black"
        default:
            fontName = "Inter-Regular"
        }
        
        return Font.custom(fontName, size: size)
    }
    
    // Convenience methods for common sizes
    static func interTitle() -> Font {
        return inter(28, weight: .bold)
    }
    
    static func interHeadline() -> Font {
        return inter(20, weight: .semibold)
    }
    
    static func interBody() -> Font {
        return inter(16, weight: .regular)
    }
    
    static func interCaption() -> Font {
        return inter(14, weight: .regular)
    }
    
    static func interSmall() -> Font {
        return inter(12, weight: .regular)
    }
}

# Inter Font Setup

This directory contains the Inter font family for the Whisk iOS app.

## Font Files Included

- **Inter-Regular.otf** - Regular weight
- **Inter-Medium.otf** - Medium weight  
- **Inter-SemiBold.otf** - Semi-bold weight
- **Inter-Bold.otf** - Bold weight
- **Inter-Light.otf** - Light weight
- **Inter-ExtraLight.otf** - Extra light weight
- **Inter-Thin.otf** - Thin weight
- **Inter-Black.otf** - Black weight
- **Inter-ExtraBold.otf** - Extra bold weight
- **Inter.ttf** - Variable font file

Plus all italic variants.

## Usage in SwiftUI

The app includes a `Font+Inter.swift` extension that provides convenient methods:

```swift
// Basic usage
Text("Hello World")
    .font(.inter(16, weight: .regular))

// Convenience methods
Text("Title")
    .font(.interTitle()) // 28pt, bold

Text("Headline") 
    .font(.interHeadline()) // 20pt, semibold

Text("Body text")
    .font(.interBody()) // 16pt, regular

Text("Caption")
    .font(.interCaption()) // 14pt, regular

Text("Small text")
    .font(.interSmall()) // 12pt, regular
```

## Font Registration

Fonts are automatically registered in `WhiskApp.swift` when the app launches. The app also sets Inter as the default font family through the environment.

## Adding to Xcode Project

1. In Xcode, right-click on your project
2. Select "Add Files to [ProjectName]"
3. Select all the `.otf` and `.ttf` files in this directory
4. Make sure "Add to target" is checked for your app target
5. Build and run

## Font Weights Available

- `.ultraLight` → Inter-Thin
- `.thin` → Inter-ExtraLight  
- `.light` → Inter-Light
- `.regular` → Inter-Regular
- `.medium` → Inter-Medium
- `.semibold` → Inter-SemiBold
- `.bold` → Inter-Bold
- `.heavy` → Inter-ExtraBold
- `.black` → Inter-Black

## License

Inter is licensed under the SIL Open Font License, Version 1.1.

# Design System Migration Guide

## Overview
This guide shows how to systematically migrate existing views to use the new design system.

## Migration Patterns

### 1. Text Elements
**Before:**
```swift
Text("Title")
    .font(.title)
    .fontWeight(.bold)
    .foregroundColor(.primary)

Text("Body text")
    .font(.body)
    .foregroundColor(.secondary)
```

**After:**
```swift
Text("Title")
    .titleStyle()

Text("Body text")
    .bodyStyle()
```

### 2. Buttons
**Before:**
```swift
Button("Create List") {
    // action
}
.buttonStyle(.borderedProminent)

Button("Cancel") {
    // action
}
.buttonStyle(.bordered)
```

**After:**
```swift
PrimaryButton("Create List") {
    // action
}

SecondaryButton("Cancel") {
    // action
}
```

### 3. Text Fields
**Before:**
```swift
TextField("Enter text", text: $text)
    .textFieldStyle(RoundedBorderTextFieldStyle())
```

**After:**
```swift
TextField("Enter text", text: $text)
    .textFieldStyle(DarkTextFieldStyle())
```

### 4. Backgrounds
**Before:**
```swift
.background(Color(.systemBackground))
```

**After:**
```swift
.darkBackground()
```

### 5. Colors
**Before:**
```swift
.foregroundColor(.blue)
.foregroundColor(.red)
.foregroundColor(.secondary)
```

**After:**
```swift
.foregroundColor(DesignSystem.Colors.accent)
.foregroundColor(DesignSystem.Colors.error)
.foregroundColor(DesignSystem.Colors.textSecondary)
```

## Systematic Migration Steps

### Step 1: Update Text Elements
Replace all text styling with design system methods:
- `.font(.title)` + `.fontWeight(.bold)` → `.titleStyle()`
- `.font(.headline)` → `.headlineStyle()`
- `.font(.body)` → `.bodyStyle()`
- `.font(.caption)` → `.captionStyle()`

### Step 2: Update Buttons
Replace button styles with design system components:
- `.buttonStyle(.borderedProminent)` → `PrimaryButton`
- `.buttonStyle(.bordered)` → `SecondaryButton`
- Destructive buttons → `DestructiveButton`

### Step 3: Update Text Fields
Replace text field styles:
- `RoundedBorderTextFieldStyle()` → `DarkTextFieldStyle()`

### Step 4: Update Colors
Replace color references:
- `.blue` → `DesignSystem.Colors.accent`
- `.red` → `DesignSystem.Colors.error`
- `.secondary` → `DesignSystem.Colors.textSecondary`
- `.primary` → `DesignSystem.Colors.text`

### Step 5: Update Backgrounds
Replace background colors:
- `Color(.systemBackground)` → `DesignSystem.Colors.surface`
- `.background(Color(.systemBackground))` → `.darkBackground()`

### Step 6: Update Spacing
Replace hardcoded spacing:
- `spacing: 20` → `spacing: DesignSystem.Spacing.lg`
- `padding()` → `padding(DesignSystem.Spacing.lg)`

## Benefits of This Approach

1. **Consistency**: All views use the same design tokens
2. **Maintainability**: Change colors/fonts in one place
3. **Scalability**: Easy to add new components
4. **Type Safety**: Compile-time checking of design tokens
5. **Documentation**: Self-documenting design system

## Example: Complete View Migration

**Before:**
```swift
struct MyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Description")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button("Action") {
                // action
            }
            .buttonStyle(.borderedProminent)
            
            TextField("Input", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
```

**After:**
```swift
struct MyView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Welcome")
                .titleStyle()
            
            Text("Description")
                .bodyStyle()
            
            PrimaryButton("Action") {
                // action
            }
            
            TextField("Input", text: $text)
                .textFieldStyle(DarkTextFieldStyle())
        }
        .padding(DesignSystem.Spacing.lg)
        .darkBackground()
    }
}
```

## Automated Migration Script

You can create a script to automatically replace common patterns:

```bash
# Replace text styles
find . -name "*.swift" -exec sed -i '' 's/\.font(\.title)\.fontWeight(\.bold)/.titleStyle()/g' {} \;
find . -name "*.swift" -exec sed -i '' 's/\.font(\.headline)/.headlineStyle()/g' {} \;
find . -name "*.swift" -exec sed -i '' 's/\.font(\.body)/.bodyStyle()/g' {} \;

# Replace button styles
find . -name "*.swift" -exec sed -i '' 's/\.buttonStyle(\.borderedProminent)/.buttonStyle(PrimaryButtonStyle())/g' {} \;
find . -name "*.swift" -exec sed -i '' 's/\.buttonStyle(\.bordered)/.buttonStyle(SecondaryButtonStyle())/g' {} \;

# Replace colors
find . -name "*.swift" -exec sed -i '' 's/\.foregroundColor(\.blue)/.foregroundColor(DesignSystem.Colors.accent)/g' {} \;
find . -name "*.swift" -exec sed -i '' 's/\.foregroundColor(\.red)/.foregroundColor(DesignSystem.Colors.error)/g' {} \;
```

This systematic approach ensures consistency and makes future updates much easier!

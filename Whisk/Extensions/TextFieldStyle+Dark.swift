import SwiftUI

struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.darkSurfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.darkBorder, lineWidth: 1)
            )
            .foregroundColor(.darkText)
    }
}

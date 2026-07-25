import SwiftUI

/// Matches the mockup's `.card` — surface fill, hairline border, medium radius.
struct CareCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.xl)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func careCard() -> some View {
        modifier(CareCardModifier())
    }
}

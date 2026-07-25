import SwiftUI

/// Matches the mockup's `.card` — surface fill, hairline border, large
/// radius, raised elevation (two-layer shadow, not a flat border-only look).
struct CareCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.xl)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .elevation(.raised)
    }
}

extension View {
    func careCard() -> some View {
        modifier(CareCardModifier())
    }
}

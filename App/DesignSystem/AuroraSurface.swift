import SwiftUI

/// Material surface with fallbacks: a solid `Theme.Color.glass` fill when Reduce
/// Transparency is on, Liquid Glass on macOS 26+, and the system regular material on
/// macOS 14–15. Not applied to any screen yet (PR 2 onward).
struct AuroraSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
#if DEBUG
    /// Debug-only UITest override (PR 0 harness): snapshots can force the
    /// reduced-transparency look even when the system setting is off.
    @Environment(\.uiTestReduceTransparency) private var uiTestReduceTransparency
#endif
    var cornerRadius: CGFloat = Theme.Radius.lg

    private var isReduceTransparencyOn: Bool {
#if DEBUG
        if uiTestReduceTransparency { return true }
#endif
        return reduceTransparency
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isReduceTransparencyOn {
            content.background(Theme.Color.glass, in: shape)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    /// Wraps the view in an `AuroraSurface` with the given corner radius.
    func auroraSurface(cornerRadius: CGFloat = Theme.Radius.lg) -> some View {
        modifier(AuroraSurface(cornerRadius: cornerRadius))
    }
}

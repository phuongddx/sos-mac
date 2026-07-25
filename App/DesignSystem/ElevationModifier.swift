import SwiftUI

/// Matches the mockup's `--elev-raised` / `--elev-float` — two stacked
/// shadows so cards lift instead of reading as a flat 1px border.
struct ElevationModifier: ViewModifier {
    let level: Theme.Elevation.Level
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let (near, far) = Theme.Elevation.layers(for: level, isDark: colorScheme == .dark)
        content
            .shadow(color: far.color, radius: far.radius, x: 0, y: far.y)
            .shadow(color: near.color, radius: near.radius, x: 0, y: near.y)
    }
}

extension View {
    func elevation(_ level: Theme.Elevation.Level) -> some View {
        modifier(ElevationModifier(level: level))
    }
}

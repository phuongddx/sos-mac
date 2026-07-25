import SwiftUI

/// Matches the mockup's `.content::before` — one soft two-stop accent glow
/// behind a module's content area. Non-interactive, sits behind content,
/// stronger in dark mode (0.22) than light (0.1).
struct AuroraBloomModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var strength: Double { colorScheme == .dark ? 0.22 : 0.1 }

    func body(content: Content) -> some View {
        content.background(
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent, .clear], center: .center, startRadius: 0, endRadius: 260))
                    .frame(width: 520, height: 520)
                    .offset(x: 160, y: -220)
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent2, .clear], center: .center, startRadius: 0, endRadius: 220))
                    .frame(width: 440, height: 440)
                    .offset(x: 40, y: -120)
            }
            .opacity(strength)
            .blur(radius: 20)
            .allowsHitTesting(false),
            alignment: .topTrailing
        )
    }
}

extension View {
    func auroraBloom() -> some View {
        modifier(AuroraBloomModifier())
    }
}

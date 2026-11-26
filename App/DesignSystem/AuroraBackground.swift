import SwiftUI

/// The aurora background (spec §4.9), which replaces `.auroraBloom()` on every screen: two
/// non-interactive radial washes behind the content — the module hue at `Glow.auroraAlpha`
/// (upper left) and a brand indigo of the same strength (upper right). It is how the module hue
/// reaches the content area.
///
/// Geometry is the prototype's `.content::before`, in fractions of the content's size: a box from
/// −10 % to 110 % of the width and −20 % to 50 % of the height, holding
/// `radial-gradient(50% 60% at 30% 10%, hue, transparent 70%)` and
/// `radial-gradient(40% 50% at 85% 0%, indigo, transparent 70%)`, clipped to the content.
struct AuroraBackground: View {
    /// Brand indigo of the second bloom (spec §4.9, `#6366F1`). It is not a `Theme.Color` token
    /// yet — it is also the last stop of `Theme.Gradient.soft` and `Theme.Gradient.aurora`.
    /// Proposed as `Theme.Color.indigo`; until then it lives here.
    private static let indigo = Color(hex: "#6366F1")

    let hue: Color

    @Environment(\.colorScheme) private var colorScheme

    init(hue: Color) {
        self.hue = hue
    }

    var body: some View {
        let alpha = Theme.Glow.auroraAlpha(isDark: colorScheme == .dark)
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                bloom(Self.indigo, alpha: alpha, center: (0.92, -0.20), reach: (0.336, 0.245), in: size)
                bloom(hue, alpha: alpha, center: (0.26, -0.13), reach: (0.42, 0.294), in: size)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One wash: the colour at `alpha` in the middle, fading out at `reach` (a fraction of the
    /// content's width and height), centred at `center`. SwiftUI's radial gradient is round, so
    /// it is drawn on a square and stretched to the ellipse.
    private func bloom(_ color: Color, alpha: Double,
                       center: (x: CGFloat, y: CGFloat), reach: (x: CGFloat, y: CGFloat),
                       in size: CGSize) -> some View {
        let side = reach.y * 2 * size.height
        let stretch = size.height > 0 ? reach.x * size.width / (reach.y * size.height) : 1
        return Circle()
            .fill(RadialGradient(colors: [color.opacity(alpha), color.opacity(0)], center: .center, startRadius: 0, endRadius: side / 2))
            .frame(width: side, height: side)
            .scaleEffect(x: stretch, y: 1)
            .position(x: center.x * size.width, y: center.y * size.height)
    }
}

extension View {
    /// Puts the aurora background behind the view, tinted with the module hue.
    func auroraBackground(hue: Color) -> some View {
        background { AuroraBackground(hue: hue) }
    }
}

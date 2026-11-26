import SwiftUI

/// Sidebar group label (spec §3.2): eyebrow style, `textSecondary`. Prototype `.nav-label`.
struct SidebarSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.eyebrow)
            .kerning(0.2)
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.s3 - 2)  // .nav-label: 0 10px 5px
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The 22 pt module tile (prototype `.tile`): the module hue as a top-to-bottom
/// gradient (hue 92 % / white 8 % → hue 78 % / black 22 %), the glyph in the hue's
/// ink colour (spec §2.5), and the idle glow when `glows` (dark only, spec T6).
struct ModuleTile: View {
    let systemImage: String
    let hue: Color
    let ink: Color
    var size: CGFloat = 22
    var glows: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glowAlpha: Double {
        guard glows, !reduceMotion else { return 0 }
        return Theme.Glow.idleAlpha(isDark: colorScheme == .dark)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            // color-mix in sRGB, built as an overlay because `Color.mix(with:by:)` is macOS 15+.
            shape.fill(hue)
            shape.fill(LinearGradient(
                colors: [.white.opacity(0.08), .black.opacity(0.22)],
                startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)
            ))
            // inset 0 0.5px 0 rgba(255,255,255,.35): a hairline highlight on the top edge.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center),
                lineWidth: 0.5
            )
            Image(systemName: systemImage)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(ink)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        .shadow(color: hue.opacity(glowAlpha), radius: 6)
        .accessibilityHidden(true)
    }
}

/// One sidebar row (spec §3.2, prototype `.nav-row`): tile + 13 pt medium label,
/// 32 pt tall, radius 8. Hover = `rowHover`, current = `rowSelected`, and the
/// current row's tile gets the idle glow. No generic accent wash.
struct SidebarNavRow: View {
    let title: String
    let systemImage: String
    let hue: Color
    let ink: Color
    let isActive: Bool
    /// PR 3 (OD-3): a cyan dot while the module is scanning in the background.
    var isScanning: Bool = false

    @State private var isHovering = false

    private var rowFill: Color {
        if isActive { return Theme.Derived.rowSelected }
        if isHovering { return Theme.Derived.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s3 - 2) {  // gap: 10px
            ModuleTile(systemImage: systemImage, hue: hue, ink: ink, glows: isActive)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isScanning {
                Circle()
                    .fill(Theme.Color.neonCyan)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.s2)
        .frame(height: 32)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.quick, value: isHovering)
    }
}

/// Sidebar footer meter (prototype `.meter.sm`): 4 pt, `hairlineStrong` track,
/// `Gradient.soft` fill. No glow — it is a status read-out, not an action.
struct StorageMeterView: View {
    let usedFraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Derived.hairlineStrong)
                Capsule()
                    .fill(Theme.Gradient.soft)
                    .frame(width: geo.size.width * min(max(usedFraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Storage used")
        .accessibilityValue(Text(usedFraction, format: .percent.precision(.fractionLength(0))))
    }
}

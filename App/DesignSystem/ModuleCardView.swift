import SwiftUI

/// Matches the mockup's `.module-card` — used in the Dashboard's module grid.
/// Hue-coded off the module it represents: a soft top wash plus a gradient
/// icon tile, instead of a flat accent tint.
struct ModuleCardView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let stat: String
    let badgeText: String
    let badgeStyle: BadgeStyle
    let hue: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(LinearGradient(colors: [hue, hue.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 38, height: 38)
                            .shadow(color: hue.opacity(0.4), radius: 6, x: 0, y: 3)
                        Image(systemName: systemImage)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                Text(stat)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                BadgeView(text: badgeText, style: badgeStyle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
            .background(
                ZStack(alignment: .top) {
                    Theme.surface
                    LinearGradient(colors: [hue.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .elevation(.raised)
        }
        .buttonStyle(.plain)
    }
}

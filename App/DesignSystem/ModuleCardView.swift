import SwiftUI

/// Matches the mockup's `.module-card` — used in the Dashboard's module grid.
struct ModuleCardView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let stat: String
    let badgeText: String
    let badgeStyle: BadgeStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.accent.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: systemImage)
                            .foregroundStyle(Theme.accent)
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
            .careCard()
        }
        .buttonStyle(.plain)
    }
}

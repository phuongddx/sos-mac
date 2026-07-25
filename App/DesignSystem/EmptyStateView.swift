import SwiftUI

/// Matches the mockup's `.empty-state` — gradient-orb illustration + title +
/// body + CTA, tinted by the module's hue (defaults to the generic accent).
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var hue: Color = Theme.accent
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 34)
                    .fill(LinearGradient(colors: [hue.opacity(0.18), hue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 108, height: 108)
                    .shadow(color: hue.opacity(0.14), radius: 24)
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(hue)
            }
            Text(title)
                .font(.system(size: Theme.TextSize.lg, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text(message)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.giant)
    }
}

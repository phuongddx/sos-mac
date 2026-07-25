import SwiftUI

/// Matches the mockup's `.empty-state` — flat geometric icon + title + body + CTA.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.accent.opacity(0.1))
                    .frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Theme.accent)
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

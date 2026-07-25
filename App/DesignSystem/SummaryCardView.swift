import SwiftUI

/// Matches the mockup's `.summary-success` — reclaimed-space completion card
/// shown by Junk Cleaner / Duplicate Finder / Smart Care after cleaning.
struct SummaryCardView: View {
    let bigNumber: String
    let caption: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.success).frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(bigNumber)
                .font(.system(size: Theme.TextSize.xxxl, weight: .bold))
                .foregroundStyle(Theme.success)
            Text(caption)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxxl)
        .background(Theme.success.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.success.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

import SwiftUI

/// Matches the mockup's `.summary-success` — reclaimed-space completion card
/// shown by Junk Cleaner / Duplicate Finder / Smart Care after cleaning.
struct SummaryCardView: View {
    let bigNumber: String
    let caption: String
    var breakdown: [(num: String, label: String)] = []

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.success, Theme.accent2.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .shadow(color: Theme.success.opacity(0.4), radius: 10, x: 0, y: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(bigNumber)
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(Theme.success)
            Text(caption)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if !breakdown.isEmpty {
                HStack(spacing: Theme.Spacing.xxl) {
                    ForEach(Array(breakdown.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 2) {
                            Text(item.num)
                                .font(.system(size: Theme.TextSize.lg, weight: .bold))
                                .foregroundStyle(Theme.foreground)
                            Text(item.label)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.huge)
        .background(
            LinearGradient(colors: [Theme.success.opacity(0.1), Theme.surface], startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .strokeBorder(Theme.success.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .elevation(.float)
    }
}

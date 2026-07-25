import SwiftUI

/// Matches the mockup's `.sticky-footer` — totals bar pinned above the
/// action button in review/results states (Junk, Duplicates, Cloud Cleanup).
struct StickyFooterView<Trailing: View>: View {
    let totalLabel: String
    let totalValue: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text(totalLabel)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
            Text(totalValue)
                .font(.system(size: Theme.TextSize.lg, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(.regularMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
    }
}

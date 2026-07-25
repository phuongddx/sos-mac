import SwiftUI

/// Matches the mockup's `.sidebar-section-label`.
struct SidebarSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 4)
    }
}

/// Matches the mockup's `.nav-item` — icon + label row, accent-filled when active.
struct SidebarNavRow: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(isActive ? .white : Theme.foreground)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(isActive ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
    }
}

/// Matches the mockup's sidebar-footer `.storage-gauge-mini`.
struct StorageGaugeMiniView: View {
    let usedFraction: Double
    let label: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressBarView(progress: usedFraction)
                .frame(height: 4)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize()
        }
    }
}

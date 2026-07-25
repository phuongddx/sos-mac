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

/// Matches the mockup's `.nav-item` — icon tile hue-coded by module identity
/// (soft wash inactive, solid + glow active); row itself gets a soft
/// generic-accent wash when active, per styles.css.
struct SidebarNavRow: View {
    let title: String
    let systemImage: String
    let hue: Color
    let isActive: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? AnyShapeStyle(hue) : AnyShapeStyle(hue.opacity(0.14)))
                    .frame(width: 24, height: 24)
                    .shadow(color: isActive ? hue.opacity(0.5) : .clear, radius: 5, x: 0, y: 2)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? .white : hue)
            }
            Text(title)
                .font(.system(size: 13.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(isActive ? AnyShapeStyle(Theme.accent.opacity(0.12)) : AnyShapeStyle(.clear))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(isActive ? Theme.accent.opacity(0.22) : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
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

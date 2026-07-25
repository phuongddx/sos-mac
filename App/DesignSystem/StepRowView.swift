import SwiftUI

/// Matches the mockup's `.step-row` — shared scan-progress row used by
/// Junk Cleaner, Duplicate Finder, and Smart Care while scanning.
struct StepRowView: View {
    enum State { case pending, active, done }

    let name: String
    let meta: String?
    let state: State

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .strokeBorder(state == .active ? Theme.accent : Theme.border, lineWidth: 1.5)
                    .background(Circle().fill(state == .done ? Theme.success : Theme.background))
                    .frame(width: 20, height: 20)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if state == .active {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                }
            }
            Text(name)
                .font(.system(size: Theme.TextSize.sm, weight: .medium))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 0)
            if let meta {
                Text(meta)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

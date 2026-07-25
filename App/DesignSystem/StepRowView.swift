import SwiftUI

/// Matches the mockup's `.step-row` — shared scan-progress row used by
/// Junk Cleaner, Duplicate Finder, and Smart Care while scanning.
struct StepRowView: View {
    enum StepState { case pending, active, done }

    let name: String
    let meta: String?
    let state: StepState
    @State private var pulse = false

    init(name: String, meta: String?, state: StepState) {
        self.name = name
        self.meta = meta
        self.state = state
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .strokeBorder(state == .active ? Theme.accent : Theme.border, lineWidth: 1.5)
                    .background(
                        Circle().fill(
                            state == .done
                                ? AnyShapeStyle(LinearGradient(colors: [Theme.success, Theme.success.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Theme.background)
                        )
                    )
                    .frame(width: 20, height: 20)
                    .shadow(color: state == .done ? Theme.success.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if state == .active {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 0.78 : 1)
                        .opacity(pulse ? 0.4 : 1)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }
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
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(state == .active ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .elevation(.raised)
    }
}

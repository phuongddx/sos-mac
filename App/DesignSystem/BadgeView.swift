import SwiftUI

/// Severity language used across every module: safe / attention / risk /
/// neutral / accent — matches the mockup's `.badge-*` classes.
enum BadgeStyle {
    case safe, attention, risk, neutral, accent

    var color: Color {
        switch self {
        case .safe: return Theme.success
        case .attention: return Theme.warn
        case .risk: return Theme.danger
        case .neutral: return Theme.muted
        case .accent: return Theme.accent
        }
    }
}

struct BadgeView: View {
    let text: String
    let style: BadgeStyle

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(style.color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(style.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

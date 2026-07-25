import SwiftUI

/// Matches the mockup's `.progress-track` / `.progress-fill` — gradient fill
/// with a soft accent glow by default; pass `style` to override (e.g. the
/// success gradient for a completed scan).
struct ProgressBarView: View {
    var progress: Double // 0...1
    var style: AnyShapeStyle = AnyShapeStyle(Theme.accentGradient)

    static let successStyle = AnyShapeStyle(
        LinearGradient(colors: [Theme.success, Theme.accent2], startPoint: .leading, endPoint: .trailing)
    )

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(style)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                    .shadow(color: Theme.accent.opacity(0.3), radius: 5)
            }
        }
        .frame(height: 8)
    }
}

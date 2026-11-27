import SwiftUI

/// A progress bar (spec §4.9 "Progress"): a `hairlineStrong` track and a neon cyan fill with a
/// cyan glow, 6 pt tall.
///
/// Determinate only when a total is known — the caller decides that (`ScanningView`).
/// `style` overrides the fill for the pre-redesign meters (Performance); `nil` is the scan fill,
/// the only one that glows, because it is the only neon one (T1).
struct ProgressBarView: View {
    var progress: Double // 0...1
    var style: AnyShapeStyle? = nil
    var height: CGFloat = 6

    static let glowRadius: CGFloat = 5

    /// Fill the pre-redesign layout used for a completed scan.
    static let successStyle = AnyShapeStyle(
        LinearGradient(colors: [Theme.Color.success, Theme.Color.neonCyan], startPoint: .leading, endPoint: .trailing)
    )

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isScanFill = style == nil
        // T6: the glow stays in dark mode only, and off under Reduce Motion.
        let glows = isScanFill && colorScheme == .dark && !reduceMotion
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Derived.hairlineStrong)
                Capsule()
                    .fill(style ?? AnyShapeStyle(Theme.Color.neonCyan))
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                    .shadow(color: glows ? Theme.Color.neonCyan.opacity(Theme.Glow.idleAlpha(isDark: true)) : .clear,
                            radius: Self.glowRadius)
            }
        }
        .frame(height: height)
        // The label next to the bar carries the value; the bar itself is decorative.
        .accessibilityHidden(true)
    }
}

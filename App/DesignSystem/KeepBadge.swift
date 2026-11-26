import SwiftUI

/// The kept-copy badge (spec §4.6): the `keep` kind with its `lock` symbol, reading "Keep".
///
/// It sits next to a locked `SOSCheckbox` in a kept row. For accessibility the badge is
/// decorative: the row itself reads "«name», kept, «size»" (see `rowAccessibilityLabel`).
struct KeepBadge: View {
    var body: some View {
        BadgeView(text: "Keep", style: .keep)
            .accessibilityHidden(true)
    }
}

extension KeepBadge {
    /// What accessibility reads for a kept row (spec §4.6): "«name», kept, «size»".
    static func rowAccessibilityLabel(name: String, size: String) -> String {
        "\(name), kept, \(size)"
    }

    /// Strength of the `success` wash behind a kept row (spec §4.5).
    static let rowBackgroundAlpha: Double = 0.05
}

extension View {
    /// The kept-row treatment (spec §4.5): a 5 % `success` wash behind the row, with its locked
    /// checkbox and `KeepBadge`.
    ///
    /// Apply it *before* the row's hover and focused-row backgrounds. A later `background` sits
    /// behind an earlier one, so the wash stays visible and a kept row never looks selectable.
    func keptRowBackground() -> some View {
        background(Theme.Color.success.opacity(KeepBadge.rowBackgroundAlpha))
    }
}

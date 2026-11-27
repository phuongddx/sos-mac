import SwiftUI

/// Badge kinds of spec §4.4: the colour family a badge belongs to.
enum BadgeStyle: CaseIterable, Sendable {
    case safe
    case caution
    case risky
    case threat
    case keep
    case neutral
    case accent

    /// The kind's colour: its tint, its symbol, and its label (rule T4).
    var color: Color {
        switch self {
        case .safe, .keep: Theme.Color.success
        case .caution: Theme.Color.warning
        case .risky, .threat: Theme.Color.danger
        case .neutral: Theme.Color.textSecondary
        case .accent: Theme.Color.primaryBright
        }
    }

    /// Symbol shown when the caller gives none. Only `keep` has one: the lock.
    var defaultSymbol: String? {
        self == .keep ? "lock" : nil
    }

    /// Strength of the kind's colour in the background: dark 16 %, light 11 %.
    static func tintAlpha(isDark: Bool) -> Double {
        isDark ? 0.16 : 0.11
    }

    /// Label colour. Rule T4: the 11 pt label must reach 4.5:1 on its own tinted background.
    /// With the Designer's final light value `#A14A06`, `warning` in light reaches 5.11:1 on its
    /// 11 % tint, so X4 is withdrawn and every label uses the kind's own colour.
    func labelColor(isDark: Bool) -> Color {
        color
    }
}

/// A badge (spec §4.4): 20 pt tall, 5 pt radius, 7 pt side padding, 11 pt semibold label with an
/// optional 11 pt symbol, on a tint of the kind's colour.
///
/// The prototype's `cyan` kind is not ported (T1: no neon text under 13 pt). A cyan status is a
/// cyan dot with a `textSecondary` label.
struct BadgeView: View {
    static let height: CGFloat = Theme.Spacing.s5
    static let horizontalPadding: CGFloat = 7
    static let symbolSize: CGFloat = 11

    let text: String
    let style: BadgeStyle
    var systemImage: String?

    @Environment(\.colorScheme) private var colorScheme

    init(text: String, style: BadgeStyle, systemImage: String? = nil) {
        self.text = text
        self.style = style
        self.systemImage = systemImage
    }

    var body: some View {
        let isDark = colorScheme == .dark
        HStack(spacing: Theme.Spacing.s1) {
            if let symbol = systemImage ?? style.defaultSymbol {
                Image(systemName: symbol)
                    .font(.system(size: Self.symbolSize, weight: .semibold))
            }
            Text(text)
                .font(Theme.Font.subheadline.weight(.semibold))
        }
        .foregroundStyle(style.labelColor(isDark: isDark))
        .padding(.horizontal, Self.horizontalPadding)
        .frame(height: Self.height)
        .background(
            style.color.opacity(BadgeStyle.tintAlpha(isDark: isDark)),
            in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
        )
        .fixedSize()
        // The symbol is decorative; the text is the label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

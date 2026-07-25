import SwiftUI

/// Matches the mockup's `.hero-panel` — the aurora-lit headline surface on
/// each module screen: eyebrow / title / sub / badge row / one primary CTA,
/// plus an optional stat block or storage bar behind a hairline divider.
struct HeroPanelView<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let hue: Color
    var badges: [(text: String, style: BadgeStyle)] = []
    let primaryActionTitle: String
    let primaryAction: () -> Void
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xxl) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(hue)
                Text(title)
                    .font(.system(size: Theme.TextSize.xxl, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Text(subtitle)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 420, alignment: .leading)
                if !badges.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            BadgeView(text: badge.text, style: badge.style)
                        }
                    }
                }
                HStack(spacing: Theme.Spacing.md) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if Trailing.self != EmptyView.self {
                Rectangle().frame(width: 1).foregroundStyle(Theme.border)
                trailing
            }
        }
        .padding(Theme.Spacing.xxxl)
        .background(
            LinearGradient(colors: [hue.opacity(0.08), Theme.surface], startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .strokeBorder(hue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .elevation(.float)
    }
}

extension HeroPanelView where Trailing == EmptyView {
    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        hue: Color,
        badges: [(text: String, style: BadgeStyle)] = [],
        primaryActionTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            hue: hue,
            badges: badges,
            primaryActionTitle: primaryActionTitle,
            primaryAction: primaryAction,
            secondaryActionTitle: secondaryActionTitle,
            secondaryAction: secondaryAction,
            trailing: { EmptyView() }
        )
    }
}

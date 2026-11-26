import SwiftUI

/// The results head (spec §4.9, prototype `.results-head`): a hue-dot eyebrow, the `title1`
/// headline ("«size» of junk found"), a sub line ("N files in 4 locations · «size» selected"),
/// and trailing tools on the right. Every value is real and comes from the screen.
struct ResultsHeaderView: View {
    static let eyebrowText = "Results"

    let hue: Color
    let title: String
    var sub: String?
    var eyebrow: String
    /// Trailing tools on the right (real values only).
    var right: AnyView

    init(hue: Color,
         title: String,
         sub: String? = nil,
         eyebrow: String = Self.eyebrowText,
         @ViewBuilder right: () -> some View = { EmptyView() }) {
        self.hue = hue
        self.title = title
        self.sub = sub
        self.eyebrow = eyebrow
        self.right = AnyView(right())
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.s5) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.s2 - 2) {
                    Circle().fill(hue).frame(width: 6, height: 6)
                    Text(eyebrow.uppercased())
                }
                .font(Theme.Font.eyebrow)
                .tracking(0.72)
                .foregroundStyle(Theme.Color.textSecondary)
                .accessibilityHidden(true)

                Text(title)
                    .font(Theme.Font.title1)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(.top, Theme.Spacing.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let sub {
                    Text(sub)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            right
        }
        .padding(EdgeInsets(top: Theme.Spacing.s2, leading: 0, bottom: Theme.Spacing.s5, trailing: 0))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results-header")
    }
}

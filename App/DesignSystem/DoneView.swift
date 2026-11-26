import SwiftUI

/// The done card (spec §4.9): radius `xl`, padding 28/32, standard material, `hairline`,
/// `Elevation.raised`, the 180 pt orb with the lime glyph, a lime-dot eyebrow, the title,
/// stats (bytes in `neonLime`), actions, the "everything is in the Trash" hint, and a free
/// slot for a failure banner or the quarantine panel.
///
/// F4: "done" is honest about failures — the screen passes "Couldn't move: n" as a stat and
/// a failure banner in the free slot; nothing here claims files were reclaimed.
struct DoneView: View {
    struct Stat: Identifiable {
        let label: String
        let value: String
        /// The bytes stat — the value is drawn in `neonLime`.
        var isBytes = false
        var id: String { label }

        init(label: String, value: String, isBytes: Bool = false) {
            self.label = label
            self.value = value
            self.isBytes = isBytes
        }
    }

    static let hint = "Everything is in the Trash. To undo, open the Trash in Finder and choose Put Back."
    static let contentWidth: CGFloat = 520

    var symbol: String = "check"
    var eyebrow: String = "Done"
    let title: String
    var sub: String?
    let stats: [Stat]
    /// The card's actions (Open Trash, Scan Again, Back to…) — the dock stays as well; the
    /// screen decides what belongs here.
    var actions: AnyView?
    var hint: String?
    /// Free slot below the card: a failure banner or the quarantine panel.
    var extra: AnyView

    private let hue: Color

    init(hue: Color,
         symbol: String = "check",
         eyebrow: String = "Done",
         title: String,
         sub: String? = nil,
         stats: [Stat],
         actions: AnyView? = nil,
         hint: String? = DoneView.hint,
         @ViewBuilder extra: () -> some View = { EmptyView() }) {
        self.hue = hue
        self.symbol = symbol
        self.eyebrow = eyebrow
        self.title = title
        self.sub = sub
        self.stats = stats
        self.actions = actions
        self.hint = hint
        self.extra = AnyView(extra())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s5 - 2) {
            HStack(alignment: .center, spacing: Theme.Spacing.s8) {
                ModuleOrbView(hue: hue, symbol: symbol, metrics: .done, doneGlyph: true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Theme.Spacing.s2 - 2) {
                        Circle().fill(Theme.Color.neonLime).frame(width: 6, height: 6)
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
                            .frame(maxWidth: Self.contentWidth, alignment: .leading)
                    }

                    if !stats.isEmpty {
                        HStack(alignment: .top, spacing: Theme.Spacing.s8 - 4) {
                            ForEach(stats) { stat in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stat.label)
                                        .font(Theme.Font.callout)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                    Text(stat.value)
                                        .font(Theme.Font.numeralL)
                                        .monospacedDigit()
                                        .foregroundStyle(stat.isBytes ? Theme.Color.neonLime : Theme.Color.textPrimary)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.s3 + 2)
                        .padding(.bottom, Theme.Spacing.s5 - 2)
                    }

                    if let actions {
                        HStack(spacing: Theme.Spacing.s2) { actions }
                    }

                    if let hint {
                        HStack(alignment: .top, spacing: Theme.Spacing.s2) {
                            Image(systemName: "info.circle")
                                .font(.system(size: Theme.TextSize.sm))
                                .foregroundStyle(Theme.Color.textSecondary)
                                .padding(.top, 1)
                            Text(hint)
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.textSecondary)
                                .frame(maxWidth: Self.contentWidth, alignment: .leading)
                        }
                        .padding(.top, Theme.Spacing.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 28, leading: 32, bottom: 28, trailing: 32))
            .auroraSurface(cornerRadius: Theme.Radius.xl)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
            .elevation(.raised)

            extra
        }
        .padding(EdgeInsets(top: Theme.Spacing.s5, leading: 40, bottom: Theme.Spacing.s5, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-view")
    }
}

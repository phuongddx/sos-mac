import SwiftUI

/// The review bar (spec §4.5): 60 tall, 20 side padding, top `hairline`; left meta; the
/// summary "**N items** · **size** selected" or "No items selected"; the CTA.
///
/// `selectedCount` and `selectedSizeText` are the same numbers the confirmation shows
/// (CF-3), computed once by the view model.
struct ReviewBarView: View {
    static let height: CGFloat = 60
    static let horizontalPadding: CGFloat = 20
    static let spacing: CGFloat = 12

    var meta: AnyView?
    var selectedCount: Int = 0
    var selectedSizeText: String?
    /// "item" / "copy" / "file" — pluralised for display.
    var noun: String = "item"
    var ctaLabel: String = "Move to Trash…"
    var isCTAEnabled: Bool = true
    /// Danger style — reserved for the server-side cloud delete (§4.4);
    /// every other review bar keeps the prominent style.
    var isCTADanger: Bool = false
    var ctaAction: (@MainActor () -> Void)?

    var body: some View {
        HStack(spacing: Self.spacing) {
            if let meta { meta }
            Spacer(minLength: 0)
            summary
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Button {
                ctaAction?()
            } label: {
                Text(ctaLabel)
            }
            .sosButton(isCTADanger ? .danger : .prominent)
            .disabled(!isCTAEnabled || ctaAction == nil)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(height: Self.height)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .background(
            ColorMix.mix(Theme.Color.bgBase, Theme.Color.card, fraction: 0.25, in: environment)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-bar")
    }

    @Environment(\.self) private var environment

    /// "**N items** · **size** selected" or "No items selected" (spec §4.5).
    private var summary: Text {
        guard selectedCount > 0 else {
            return Text("No \(Self.plural(noun)) selected")
        }
        var text = Text("\(selectedCount)")
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Color.textPrimary)
            + Text(" \(selectedCount == 1 ? noun : Self.plural(noun))")
        if let selectedSizeText {
            text = text
                + Text(" · ")
                + Text(selectedSizeText).fontWeight(.semibold).foregroundStyle(Theme.Color.textPrimary)
                + Text(" selected")
        } else {
            text = text + Text(" selected")
        }
        return text
    }

    private static func plural(_ noun: String) -> String {
        noun.hasSuffix("y") && noun.count > 1 ? String(noun.dropLast()) + "ies" : noun + "s"
    }
}

import SwiftUI

/// The centred empty / error view (spec §4.9): an icon tile 72 (radius 20, `card`,
/// `hairline`), `title1`, 14/1.5 `textSecondary` text ≤ 440, and centred actions.
///
/// F3: `empty` means "every step succeeded and found nothing" — the all-clear tile is lime.
/// An error uses the danger tile. Any other state uses the neutral tile.
struct StatusStateView: View {
    enum Kind: Equatable, Sendable {
        /// All clear — `neonLime` glyph.
        case ok
        /// Why it stopped — `danger` glyph (F5: a cause the engine can really produce).
        case error
        /// Neutral — `textSecondary` glyph.
        case neutral
    }

    static let textWidth: CGFloat = 440
    static let textLineSpacing: CGFloat = 7

    let kind: Kind
    let symbol: String
    let title: String
    let text: String
    /// Centred actions (Try Again, the one relevant escape).
    var actions: AnyView

    init(kind: Kind,
         symbol: String,
         title: String,
         text: String,
         @ViewBuilder actions: () -> some View = { EmptyView() }) {
        self.kind = kind
        self.symbol = symbol
        self.title = title
        self.text = text
        self.actions = AnyView(actions())
    }

    private var glyphColor: Color {
        switch kind {
        case .ok: Theme.Color.neonLime
        case .error: Theme.Color.danger
        case .neutral: Theme.Color.textSecondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            iconTile
            Text(title)
                .font(Theme.Font.title1)
                .foregroundStyle(Theme.Color.textPrimary)
                .padding(.top, Theme.Spacing.s4)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(Self.textLineSpacing)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(maxWidth: Self.textWidth, alignment: .leading)
                .padding(.top, Theme.Spacing.s2 - 2)
                .padding(.bottom, Theme.Spacing.s4)
            HStack(spacing: Theme.Spacing.s2) { actions }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(EdgeInsets(top: Theme.Spacing.s5, leading: 40, bottom: Theme.Spacing.s5, trailing: 40))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status-state-view")
    }

    private var iconTile: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        return ZStack {
            shape.fill(Theme.Color.card)
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(glyphColor)
        }
        .frame(width: 72, height: 72)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

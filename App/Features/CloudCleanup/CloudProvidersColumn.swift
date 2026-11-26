import SwiftUI

/// Cloud Cleanup's providers column (spec §5.6, prototype `.providers`): the
/// four providers, in every state — iCloud Drive ("Local scan") first, then
/// Google Drive / Dropbox / OneDrive ("Not set up in this build", D5). The
/// selected provider sits on `rowSelected`; the column shares the review
/// groups column's "bgBase 60 % over card" background and hairline divider.
///
/// 240 pt wide, 12/10 padding, "Providers" eyebrow on top; a row is the
/// prototype's `.prov`: a 30 pt card tile with the provider glyph, the name
/// (`headline`) and the sub line (`subheadline`, `textSecondary`).
struct CloudProvidersColumn: View {
    static let width: CGFloat = 240

    let providers: [CloudCleanupViewModel.Provider]
    let selected: CloudCleanupViewModel.Provider
    let onSelect: (CloudCleanupViewModel.Provider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Providers")
                .font(Theme.Font.eyebrow)
                .tracking(0.48)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
            VStack(spacing: 2) {
                ForEach(providers) { provider in
                    ProviderRow(provider: provider,
                                isSelected: provider == selected,
                                onSelect: { onSelect(provider) })
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10))
        .frame(width: Self.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(columnBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Derived.hairline).frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cloud-providers")
    }

    @Environment(\.self) private var environment

    /// "bgBase 60 % over card" (spec §4.5's column recipe).
    private var columnBackground: Color {
        ColorMix.mix(Theme.Color.bgBase, Theme.Color.card, fraction: 0.60, in: environment)
    }
}

/// One provider row (the prototype's `.prov`): selected wins, then hover —
/// the same precedence the review rows use.
private struct ProviderRow: View {
    let provider: CloudCleanupViewModel.Provider
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                iconTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .font(Theme.Font.headline.weight(.medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    Text(provider.columnSub)
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(provider.rawValue), \(provider.columnSub)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("cloud-provider-\(provider.rawValue)")
    }

    private var rowBackground: Color {
        if isSelected { return Theme.Derived.rowSelected }
        return isHovering ? Theme.Derived.rowHover : .clear
    }

    /// The prototype's `.pi`: a 30 pt card tile, hairline ring, neutral glyph.
    private var iconTile: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(Theme.Color.card)
            Image(systemName: provider.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .frame(width: 30, height: 30)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

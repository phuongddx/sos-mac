import SwiftUI

/// A result tile (spec §4.3): a `card` with a hue wash from the top, a 30 pt hue tile and a label,
/// a 40 pt figure with an optional unit, a caption, a free `detail` slot, and a `foot` slot that
/// is pushed to the bottom.
///
/// A tile is **wide** (half of a six-column row, at least 172 pt tall) or **full** (the whole row).
/// `isSelected` adds the lime check disc — "something here is selected". `isSkipped` fades the
/// tile to 55 % and shows "—" as its figure: the step failed or was not run, so no number is
/// shown.
///
/// The screen owns the grid (`LazyVGrid`); the tile only sizes itself. The two slots are
/// type-erased so the tile can keep its metrics as static constants.
struct ResultTileView: View {
    enum Span: Sendable {
        /// Half of the row; at least 172 pt tall.
        case wide
        /// The whole row; as tall as its content.
        case full
    }

    /// Geometry and strengths (spec §4.3).
    enum Metrics {
        static let padding: CGFloat = 18
        static let minimumHeight: CGFloat = 172
        static let washHeight: CGFloat = 90
        static let washAlpha: Double = 0.12
        static let headerSpacing: CGFloat = 10
        static let valueTopSpacing: CGFloat = 18
        static let valueUnitSpacing: CGFloat = 4
        static let captionTopSpacing: CGFloat = 4
        static let footTopSpacing: CGFloat = 14
        static let footSpacing: CGFloat = Theme.Spacing.s2
        static let checkSide: CGFloat = 22
        static let checkInset: CGFloat = Theme.Spacing.s4
        static let skippedOpacity: Double = 0.55
        /// 18 pt semibold unit (spec §4.3). `Theme.Font` has no 18 pt step.
        static let unitFontSize: CGFloat = 18
        /// The figure a skipped tile shows instead of a number.
        static let skippedValue = "—"
    }

    let hue: Color
    let ink: Color
    let symbol: String
    let label: String
    let value: String
    let unit: String?
    let caption: String?
    let span: Span
    let isSelected: Bool
    let isSkipped: Bool
    /// The free slot under the caption (e.g. the three-column health check).
    var detail: AnyView?
    /// Badges and buttons, pushed to the bottom of the tile.
    var foot: AnyView

    @Environment(\.colorScheme) private var colorScheme

    init(hue: Color, ink: Color, symbol: String, label: String, value: String,
         unit: String? = nil, caption: String? = nil, span: Span = .wide,
         isSelected: Bool = false, isSkipped: Bool = false,
         detail: AnyView? = nil, @ViewBuilder foot: () -> some View = { EmptyView() }) {
        self.hue = hue
        self.ink = ink
        self.symbol = symbol
        self.label = label
        self.value = value
        self.unit = unit
        self.caption = caption
        self.span = span
        self.isSelected = isSelected
        self.isSkipped = isSkipped
        self.detail = detail
        self.foot = AnyView(foot())
    }

    /// A skipped step has no figure to show.
    private var displayedValue: String { isSkipped ? Metrics.skippedValue : value }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metrics.headerSpacing) {
                ModuleTileView(hue: hue, ink: ink, symbol: symbol, size: .result)
                Text(label)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Keep the label clear of the check disc.
            .padding(.trailing, isSelected ? Metrics.checkSide : 0)

            // An empty figure (a tile that has none, like the health check) leaves no line behind.
            if !displayedValue.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.valueUnitSpacing) {
                    Text(displayedValue)
                        .font(Theme.Font.numeralXL)
                        .foregroundStyle(Theme.Color.textPrimary)
                    if let unit, !unit.isEmpty, !isSkipped {
                        Text(unit)
                            .font(.system(size: Metrics.unitFontSize, weight: .semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                .padding(.top, Metrics.valueTopSpacing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([displayedValue, isSkipped ? nil : unit].compactMap { $0 }.joined(separator: " "))
            } else {
                Color.clear.frame(height: Metrics.valueTopSpacing)
            }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.top, Metrics.captionTopSpacing)
            }

            if let detail {
                detail
            }

            Spacer(minLength: 0)

            HStack(spacing: Metrics.footSpacing) {
                foot
            }
            .padding(.top, Metrics.footTopSpacing)
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, minHeight: span == .wide ? Metrics.minimumHeight : nil, alignment: .leading)
        .background(alignment: .top) {
            LinearGradient(colors: [hue.opacity(Metrics.washAlpha), hue.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.washHeight)
        }
        .background(Theme.Color.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if isSelected {
                checkDisc
                    .padding(Metrics.checkInset)
            }
        }
        .elevation(.raised)
        .opacity(isSkipped ? Metrics.skippedOpacity : 1)
    }

    /// "Something here is selected": a lime disc with a check in dark ink (white in light).
    private var checkDisc: some View {
        let isDark = colorScheme == .dark
        return Image(systemName: "checkmark")
            .font(Theme.Font.subheadline.weight(.bold))
            .foregroundStyle(isDark ? Theme.Color.bgBase : Theme.Color.onPrimary)
            .frame(width: Metrics.checkSide, height: Metrics.checkSide)
            .background(Circle().fill(Theme.Color.neonLime))
            .accessibilityHidden(true)
    }
}

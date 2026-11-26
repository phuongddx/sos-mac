import SwiftUI

/// The module hue tile (prototype `.tile`; spec §2.5, §3.2, §4.3): a rounded square filled with
/// the module hue — 92 % hue + 8 % white at the top, 78 % hue + 22 % black at the bottom, tilted
/// 160° — a 0.5 pt inner highlight along the top edge, the glyph in the hue's `ink`, and a short
/// drop shadow.
///
/// Hues are fills, not marks (spec T5): a tile is always a `Theme.Hue.*` fill with its matching
/// `Theme.Hue.Ink.*`, which keeps the glyph at 3:1 or better on both ends of the gradient.
///
/// `glow: true` marks the current item (the selected sidebar row, spec §3.2): the drop shadow is
/// replaced by an idle glow in the hue. The glow budget (T6) applies — it is drawn in dark only,
/// never in light and never under Reduce Motion.
///
/// The tile is decorative: its owner (a nav row, a badge, a button) supplies the accessibility
/// label, so the glyph is hidden from accessibility here.
struct ModuleTileView: View {
    /// The four tile sizes the prototype draws.
    enum Size: CaseIterable, Sendable {
        /// Sidebar row: 22 pt, 6 pt radius, 14 pt glyph (spec §3.2).
        case nav
        /// Result-tile header: 30 pt, 8 pt radius, 17 pt glyph (spec §4.3).
        case result
        /// Dashboard module card and Space Lens source row: 34 pt, 9 pt radius, 18 pt glyph.
        case card
        /// Performance maintenance row: 36 pt, 9 pt radius, 18 pt glyph.
        case row

        var side: CGFloat {
            switch self {
            case .nav: 22
            case .result: 30
            case .card: 34
            case .row: 36
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .nav: 6
            case .result: 8
            case .card, .row: 9
            }
        }

        var symbolSize: CGFloat {
            switch self {
            case .nav: 14
            case .result: 17
            case .card, .row: 18
            }
        }

        /// The nav glyph is the one the prototype draws with the heavier stroke (2 of 24).
        var symbolWeight: Font.Weight {
            self == .nav ? .semibold : .medium
        }
    }

    /// Which shadow a tile casts.
    enum Shadow: Equatable, Sendable {
        /// `0 1pt 2pt black 25 %` — every tile that is not current.
        case drop
        /// `0 0 12pt hue @ Glow.idleAlpha` — the current item, dark appearance only.
        case glow
        /// The current item in light: the prototype gives it no shadow at all.
        case none
    }

    let hue: Color
    let ink: Color
    let symbol: String
    let size: Size
    var glow: Bool

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(hue: Color, ink: Color, symbol: String, size: Size, glow: Bool = false) {
        self.hue = hue
        self.ink = ink
        self.symbol = symbol
        self.size = size
        self.glow = glow
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        let fill = Self.fillColors(for: hue, in: environment)
        let shadowStyle = Self.shadowStyle(
            Self.shadow(glow: glow, isDark: colorScheme == .dark, reduceMotion: reduceMotion), hue: hue)
        ZStack {
            shape.fill(LinearGradient(colors: [fill.top, fill.bottom],
                                      startPoint: UnitPoint(x: 0.33, y: 0.03),
                                      endPoint: UnitPoint(x: 0.67, y: 0.97)))
            // Inner highlight: a 0.5 pt line of 35 % white along the top edge.
            Rectangle()
                .fill(Theme.Color.onPrimary.opacity(0.35))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Image(systemName: symbol)
                .font(.system(size: size.symbolSize, weight: size.symbolWeight))
                .foregroundStyle(ink)
        }
        .frame(width: size.side, height: size.side)
        .clipShape(shape)
        .shadow(color: shadowStyle.color, radius: shadowStyle.radius, x: 0, y: shadowStyle.y)
        .accessibilityHidden(true)
    }

    /// The tile fill, top and bottom stop (spec §2.5): `color-mix(in srgb, hue 92 %, white 8 %)`
    /// and `color-mix(in srgb, hue 78 %, black 22 %)`, blended as straight sRGB as CSS does.
    /// `hue` is resolved in `environment`, so an adaptive colour would follow the appearance.
    static func fillColors(for hue: Color, in environment: EnvironmentValues) -> (top: Color, bottom: Color) {
        // `resolve` reports gamma-encoded sRGB whatever the colour was built from.
        let resolved = hue.resolve(in: environment)
        let top = Color(.sRGB,
                        red: Double(resolved.red) * 0.92 + 0.08,
                        green: Double(resolved.green) * 0.92 + 0.08,
                        blue: Double(resolved.blue) * 0.92 + 0.08)
        let bottom = Color(.sRGB,
                           red: Double(resolved.red) * 0.78,
                           green: Double(resolved.green) * 0.78,
                           blue: Double(resolved.blue) * 0.78)
        return (top, bottom)
    }

    /// The glow budget of spec T6: an idle glow only in dark, never under Reduce Motion. A current
    /// tile that cannot glow keeps the ordinary drop shadow in dark so it never reads flatter than
    /// its neighbours; in light the prototype draws no shadow for it.
    static func shadow(glow: Bool, isDark: Bool, reduceMotion: Bool) -> Shadow {
        guard glow else { return .drop }
        guard isDark else { return .none }
        return reduceMotion ? .drop : .glow
    }

    private static func shadowStyle(_ shadow: Shadow, hue: Color) -> (color: Color, radius: CGFloat, y: CGFloat) {
        switch shadow {
        case .drop: (.black.opacity(0.25), 1, 1)
        case .glow: (hue.opacity(Theme.Glow.idleAlpha(isDark: true)), 7, 0)
        case .none: (.clear, 0, 0)
        }
    }
}

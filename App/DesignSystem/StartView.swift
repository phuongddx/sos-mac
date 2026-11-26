import SwiftUI

/// The lifecycle orb (spec §4.9): a radial hue wash over a conic hue wash with an indigo
/// segment, a 1 pt ring at 35 % hue (inset 34), and the module glyph tile. The scanning
/// variant adds a `neonCyan` sweep; the done variant fills the glyph with a lime gradient.
struct ModuleOrbView: View {
    struct Metrics: Sendable {
        let side: CGFloat
        let glyphSide: CGFloat
        let glyphRadius: CGFloat
        let symbolSize: CGFloat

        static let start = Metrics(side: 260, glyphSide: 116, glyphRadius: 30, symbolSize: 56)
        static let scanning = Metrics(side: 240, glyphSide: 116, glyphRadius: 30, symbolSize: 56)
        static let done = Metrics(side: 180, glyphSide: 88, glyphRadius: 24, symbolSize: 44)
    }

    /// The start glyph's bottom stop, `hue 70 % / #1E1B4B 30 %` (spec §4.9, prototype
    /// `.orb .glyph`). `Theme.swift` is outside this PR's write set, so the spec's own
    /// constant is pinned here with its source.
    private static let glyphInk = Color(hex: "#1E1B4B")
    /// The done glyph's spec §4.9 stops (prototype `.orb.done .glyph`).
    private static let doneLightTop = Color(hex: "#4D7C0F")
    private static let doneLightBottom = Color(hex: "#365314")
    private static let doneDarkBottom = Color(hex: "#1A2E05")
    /// The conic wash's indigo segment, `rgba(99,102,241,.12)` — Palette C's Junk hue.
    private static let indigo = Theme.Hue.junk
    /// The ring's inset (spec §4.9 `::after { inset: 34px }`).
    private static let ringInset: CGFloat = 34
    /// The scanning sweep's inset and rotation (spec §4.9, prototype `.orb.scanning::before`).
    private static let sweepInset: CGFloat = 18
    private static let sweepDuration: Double = Theme.Motion.pulseDuration

    let hue: Color
    let symbol: String
    var metrics: Metrics = .start
    var sweep = false
    var doneGlyph = false

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepAngle: Double = 0

    init(hue: Color, symbol: String, metrics: Metrics = .start, sweep: Bool = false, doneGlyph: Bool = false) {
        self.hue = hue
        self.symbol = symbol
        self.metrics = metrics
        self.sweep = sweep
        self.doneGlyph = doneGlyph
    }

    var body: some View {
        ZStack {
            orbBackground
            Circle()
                .stroke(hue.opacity(0.35), lineWidth: 1)
                .padding(Self.ringInset)
            if sweep { sweepLayer }
            glyphTile
        }
        .frame(width: metrics.side, height: metrics.side)
        .accessibilityHidden(true)
    }

    /// Dark: radial hue 28 % + conic hue 22 % with an indigo segment (from 200°). Light:
    /// radial hue 16 % over white only (spec §4.9).
    private var orbBackground: some View {
        ZStack {
            if colorScheme == .dark {
                Circle().fill(
                    AngularGradient(colors: [hue.opacity(0.22), Self.indigo.opacity(0.12), hue.opacity(0.22)],
                                    center: .center,
                                    startAngle: .degrees(200),
                                    endAngle: .degrees(560)))
                Circle().fill(
                    RadialGradient(colors: [hue.opacity(0.28), .clear],
                                   center: .center,
                                   startRadius: 0,
                                   endRadius: metrics.side / 2))
            } else {
                Circle().fill(
                    RadialGradient(colors: [ColorMix.mix(hue, Theme.Color.onPrimary, fraction: 0.84, in: environment),
                                            Theme.Color.onPrimary],
                                   center: .center,
                                   startRadius: 0,
                                   endRadius: metrics.side / 2))
            }
        }
    }

    /// The `neonCyan` sweep (spec §4.9): a 55 % conic arc masked to a ring, spinning 2.4 s.
    /// Under Reduce Motion the arc is drawn but does not spin (T6).
    private var sweepLayer: some View {
        let radius = (metrics.side - Self.sweepInset * 2) / 2
        return Circle()
            .fill(AngularGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.70),
                .init(color: Theme.Color.neonCyan.opacity(0.55), location: 0.95),
                .init(color: .clear, location: 1)
            ], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
            .mask(RadialGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.88),
                .init(color: .black, location: 0.89),
                .init(color: .black, location: 1)
            ], center: .center, startRadius: 0, endRadius: radius))
            .padding(Self.sweepInset)
            .rotationEffect(.degrees(sweepAngle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: Self.sweepDuration).repeatForever(autoreverses: false)) {
                    sweepAngle = 360
                }
            }
    }

    /// The glyph tile: `hue 90 %/white → hue 70 %/#1E1B4B` (160°), a white symbol, a top-edge
    /// highlight, a hue glow in dark and the raised elevation. The done variant uses the
    /// lime gradient (spec §4.9).
    private var glyphTile: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.glyphRadius, style: .continuous)
        return ZStack {
            shape.fill(glyphFill)
            Rectangle()
                .fill(Theme.Color.onPrimary.opacity(0.4))
                .frame(height: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Image(systemName: symbol)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .foregroundStyle(Theme.Color.onPrimary)
        }
        .frame(width: metrics.glyphSide, height: metrics.glyphSide)
        .clipShape(shape)
        .shadow(color: glyphGlow, radius: 40, x: 0, y: 18)
        .elevation(.raised)
    }

    private var glyphFill: LinearGradient {
        if doneGlyph {
            if colorScheme == .dark {
                return LinearGradient(colors: [ColorMix.mix(Theme.Color.neonLime, Self.doneDarkBottom, fraction: 0.30, in: environment),
                                               Self.doneDarkBottom],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            return LinearGradient(colors: [Self.doneLightTop, Self.doneLightBottom],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [ColorMix.mix(hue, Theme.Color.onPrimary, fraction: 0.10, in: environment),
                                       ColorMix.mix(hue, Self.glyphInk, fraction: 0.30, in: environment)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// `0 18px 40px hue @ glow-alpha × 1.2` — dark only, never under Reduce Motion (T6).
    private var glyphGlow: Color {
        guard colorScheme == .dark, !reduceMotion else { return .clear }
        return hue.opacity(Theme.Glow.idleAlpha(isDark: true) * 1.2)
    }
}

/// The start view (spec §4.9): two columns 320 / 1fr, gap 48, the 260 pt orb, eyebrow,
/// `display` title, lede, up to three bullets, an optional note and a free slot below.
/// Every string and number comes from the screen; the view adds none.
struct StartView: View {
    struct Bullet: Identifiable, Sendable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }

        init(symbol: String, title: String, text: String) {
            self.symbol = symbol
            self.title = title
            self.text = text
        }
    }

    static let columnSpacing: CGFloat = 48
    static let ledeWidth: CGFloat = 520
    /// 14 / 1.5 lede (spec §4.9).
    static let ledeLineSpacing: CGFloat = 7

    let module: ModuleIdentity
    let title: String
    let lede: String
    var bullets: [Bullet] = []
    var note: String?
    /// Free slot below the note (a source list, a quarantine panel).
    var extra: AnyView

    init(module: ModuleIdentity,
         title: String,
         lede: String,
         bullets: [Bullet] = [],
         note: String? = nil,
         @ViewBuilder extra: () -> some View = { EmptyView() }) {
        self.module = module
        self.title = title
        self.lede = lede
        self.bullets = bullets
        self.note = note
        self.extra = AnyView(extra())
    }

    var body: some View {
        HStack(alignment: .center, spacing: Self.columnSpacing) {
            ModuleOrbView(hue: module.hue, symbol: module.symbol, metrics: .start)
            VStack(alignment: .leading, spacing: 0) {
                eyebrow(hue: module.hue, text: module.name)
                Text(title)
                    .font(Theme.Font.display)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(.top, Theme.Spacing.s2)
                    .padding(.bottom, Theme.Spacing.s3 - 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(lede)
                    .font(.system(size: Theme.TextSize.sm))
                    .lineSpacing(Self.ledeLineSpacing)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(maxWidth: Self.ledeWidth, alignment: .leading)
                    .padding(.bottom, Theme.Spacing.s5 - 2)
                if !bullets.isEmpty {
                    VStack(spacing: Theme.Spacing.s3 - 2) {
                        ForEach(bullets) { bullet in
                            bulletRow(bullet)
                        }
                    }
                    .frame(maxWidth: Self.ledeWidth, alignment: .leading)
                    .padding(.bottom, Theme.Spacing.s4)
                }
                if let note {
                    noteRow(note)
                }
                extra
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: Theme.Spacing.s6, leading: 56, bottom: Theme.Spacing.s6, trailing: 56))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("start-view")
    }

    /// The shared eyebrow (prototype `.eyebrow`): a 6 pt hue dot and an uppercase module
    /// name in the eyebrow font.
    @ViewBuilder
    private func eyebrow(hue: Color, text: String) -> some View {
        HStack(spacing: Theme.Spacing.s2 - 2) {
            Circle().fill(hue).frame(width: 6, height: 6)
            Text(text.uppercased())
        }
        .font(Theme.Font.eyebrow)
        .tracking(0.72)
        .foregroundStyle(Theme.Color.textSecondary)
        .accessibilityHidden(true)
    }

    private func bulletRow(_ bullet: Bullet) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s3 - 2) {
            bulletIcon(bullet.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(bullet.title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(bullet.text)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A 28 pt icon tile (spec §4.9): `card` fill, `hairline` border, `textSecondary` glyph.
    private func bulletIcon(_ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(Theme.Color.card)
            Image(systemName: symbol)
                .font(.system(size: Theme.TextSize.xs, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(width: 28, height: 28)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func noteRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s2) {
            Image(systemName: "info.circle")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.top, 1)
            Text(note)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(maxWidth: Self.ledeWidth, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// The round dock CTA (spec §4.2): an 80 × 80 circle with a 14 pt semibold `onPrimary` label,
/// an optional progress ring 7 pt outside the button, and a hover/press scale.
///
/// | Mode | Look |
/// |---|---|
/// | `active` | radial `primaryDeep`/`neonMagenta` gradient (dark) or flat `primaryDeep` (light) |
/// | `stop` | `card` fill, `textPrimary` label, 1 pt `hairlineStrong` inner ring |
/// | `moving` | disabled, "Moving", indeterminate ring (drawn by the caller) |
/// | `disabled` | 0.42 opacity, no glow, no ring |
///
/// The ring is 3 pt `neonCyan` on a `hairlineStrong` track, determinate (0…1) or indeterminate
/// (22 % arc, 1.4 s rotation). Its glow and the rotation stop under Reduce Motion; the glow
/// also stops in light (T6).
struct PrimaryCTAView: View {
    enum Ring: Equatable, Sendable {
        case none
        case determinate(Double)
        case indeterminate
    }

    enum Mode: Equatable, Sendable {
        case active
        case stop
        case moving
        case disabled

        var isEnabled: Bool { self == .active || self == .stop }
    }

    // MARK: Metrics (spec §4.2, prototype `.cta`)

    /// 80 × 80 circle, 14 pt semibold label.
    static let side: CGFloat = 80
    static let labelSize: CGFloat = 14
    /// The ring sits 7 pt outside the button (prototype `.ring { inset: −7px }`, r 44, 3 pt).
    static let ringInset: CGFloat = 7
    static let ringWidth: CGFloat = 3
    static let hoverScale: CGFloat = 1.04
    static let pressScale: CGFloat = 0.97
    static let disabledOpacity: Double = 0.42
    static let indeterminateArc: Double = 0.22
    static let indeterminateDuration: Double = 1.4
    /// `drop-shadow(0 0 10px * glow-alpha * 3)` on the ring (dark only).
    static let ringGlowRadius: CGFloat = 10

    let label: String
    var mode: Mode = .active
    var ring: Ring = .none
    var action: (@MainActor () -> Void)?

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var indeterminateAngle: Double = 0

    init(label: String, mode: Mode = .active, ring: Ring = .none,
         action: (@MainActor () -> Void)? = nil) {
        self.label = label
        self.mode = mode
        self.ring = ring
        self.action = action
    }

    private var isDark: Bool { colorScheme == .dark }
    private var showsGlow: Bool { isDark && !reduceMotion && mode.isEnabled }

    var body: some View {
        Button {
            action?()
        } label: {
            ZStack {
                ringView
                circle
            }
        }
        .buttonStyle(CTAButtonStyle(mode: mode, isHovering: isHovering))
        .disabled(!mode.isEnabled)
        .onHover { isHovering = $0 }
        .opacity(mode.isEnabled ? 1 : Self.disabledOpacity)
        .accessibilityLabel(label)
        .accessibilityAddTraits(mode == .stop || mode == .active ? .isButton : [])
    }

    // MARK: - Circle

    /// Radial `color-mix(primaryDeep 70 %, #A78BFA 30 %)` → `primaryDeep`; `#A78BFA` is
    /// Palette C's `neonMagenta` (spec §2.3). Flat `primaryDeep` in light.
    private var fill: AnyShapeStyle {
        if mode == .stop { return AnyShapeStyle(Theme.Color.card) }
        if !isDark { return AnyShapeStyle(Theme.Color.primaryDeep) }
        let top = ColorMix.mix(Theme.Color.primaryDeep, Theme.Color.neonMagenta, fraction: 0.30, in: environment)
        return AnyShapeStyle(RadialGradient(colors: [top, Theme.Color.primaryDeep],
                                            center: UnitPoint(x: 0.3, y: 0.2),
                                            startRadius: 0,
                                            endRadius: Self.side * 1.2))
    }

    private var circle: some View {
        ZStack {
            Circle().fill(fill)
            // "white 25 % inner highlight": a 1 pt line along the top edge.
            Rectangle()
                .fill(Theme.Color.onPrimary.opacity(0.25))
                .frame(height: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Text(label)
                .font(.system(size: Self.labelSize, weight: .semibold))
                .foregroundStyle(mode == .stop ? Theme.Color.textPrimary : Theme.Color.onPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.s2)
                .minimumScaleFactor(0.6)
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(Circle())
        // 1 pt white 8 % ring (stop: 1 pt `hairlineStrong` inner ring).
        .overlay(Circle().strokeBorder(circleRing, lineWidth: 1))
        .shadow(color: glowColor, radius: 28, x: 0, y: 8)
    }

    private var circleRing: Color {
        mode == .stop ? Theme.Derived.hairlineStrong : Theme.Color.onPrimary.opacity(0.08)
    }

    /// 0/8/28 glow in the ring colour at `Glow.idleAlpha` — the ring colour when a ring shows,
    /// otherwise the fill's. Dark only, never under Reduce Motion (T6).
    private var glowColor: Color {
        guard showsGlow else { return .clear }
        let base: Color = ring == .none ? Theme.Color.primaryDeep : Theme.Color.neonCyan
        return base.opacity(Theme.Glow.idleAlpha(isDark: true))
    }

    // MARK: - Ring

    @ViewBuilder
    private var ringView: some View {
        if ring != .none {
            let shape = Circle().inset(by: Self.ringWidth / 2)
            ZStack {
                shape.stroke(Theme.Derived.hairlineStrong, lineWidth: Self.ringWidth)
                switch ring {
                case .none:
                    EmptyView()
                case .determinate(let value):
                    shape
                        .trim(from: 0, to: min(max(value, 0), 1))
                        .stroke(Theme.Color.neonCyan,
                                style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                case .indeterminate:
                    shape
                        .trim(from: 0, to: Self.indeterminateArc)
                        .stroke(Theme.Color.neonCyan,
                                style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(indeterminateAngle))
                }
            }
            .frame(width: Self.side + Self.ringInset * 2, height: Self.side + Self.ringInset * 2)
            .shadow(color: ringGlowColor, radius: Self.ringGlowRadius, x: 0, y: 0)
            .onAppear { startIndeterminateRotation() }
            .animation(ringAnimation, value: ring)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var ringGlowColor: Color {
        guard isDark, !reduceMotion else { return .clear }
        return Theme.Color.neonCyan.opacity(Theme.Glow.idleAlpha(isDark: true) * 3)
    }

    /// The stroke animates with `dur-emphasized ease-out` (prototype's dash-offset transition).
    private var ringAnimation: Animation? {
        reduceMotion ? nil : Theme.Motion.emphasized
    }

    private func startIndeterminateRotation() {
        guard ring == .indeterminate, !reduceMotion else { return }
        withAnimation(.linear(duration: Self.indeterminateDuration).repeatForever(autoreverses: false)) {
            indeterminateAngle = 360
        }
    }
}

/// Hover 1.04, press 0.97, `Motion.quick` with a spring ease (spec §4.2). A disabled CTA
/// never scales.
private struct CTAButtonStyle: ButtonStyle {
    let mode: PrimaryCTAView.Mode
    let isHovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(isPressed: configuration.isPressed))
            .animation(scaleAnimation, value: isHovering)
            .animation(scaleAnimation, value: configuration.isPressed)
    }

    private func scale(isPressed: Bool) -> CGFloat {
        guard mode.isEnabled else { return 1 }
        if isPressed { return PrimaryCTAView.pressScale }
        return isHovering ? PrimaryCTAView.hoverScale : 1
    }

    private var scaleAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(duration: 0.15, bounce: 0.15)
    }
}

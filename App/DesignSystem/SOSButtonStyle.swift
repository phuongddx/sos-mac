import SwiftUI

/// The two button looks a stock macOS style cannot draw (spec §4.4): the plain link-style button
/// and the 34 pt large CTA.
///
/// Every other button — default, prominent, danger — is a stock `.bordered` / `.borderedProminent`
/// at `.controlSize(.large)`, which is the stock size that measures **28 pt tall**, the spec's
/// default height (measured with Xcode 27.1 on macOS 27.0.1: regular 24, large 28, extraLarge 36).
/// Use `sosButton(_:)` for those instead of hand-rolling `.buttonStyle(.bordered).tint(…)`.
///
/// Disabled custom buttons are drawn at 0.42 opacity with no shadow. Stock styles keep the
/// system's own disabled look: layering 0.42 on top of it would dim the label twice.
struct SOSButtonStyle: ButtonStyle {
    enum Emphasis: Equatable, Sendable {
        /// `card` fill, 1 pt `hairlineStrong`, `textPrimary` label.
        case `default`
        /// `primaryDeep` fill, no border, `onPrimary` label, inner highlight and idle glow.
        case prominent
    }

    enum Look: Equatable, Sendable {
        /// No fill, no border, `primaryBright` label, 6 pt side padding — links, "Select All".
        case plain
        /// 34 pt tall, 18 pt side padding, 14 pt label, 9 pt radius — the Dashboard hero button.
        case large(emphasis: Emphasis)
    }

    static let defaultHeight: CGFloat = 28
    static let largeHeight: CGFloat = 34
    static let plainHorizontalPadding: CGFloat = 6
    static let largeHorizontalPadding: CGFloat = 18
    static let radius: CGFloat = Theme.Radius.sm
    static let largeRadius: CGFloat = 9
    static let disabledOpacity: Double = 0.42
    static let pressedOpacity: Double = 0.8
    /// Hover: default mixes 20 % `primaryBright` into `card`; prominent mixes 12 % white into `primaryDeep`.
    static let hoverTintAlpha: Double = 0.20
    static let prominentHoverAlpha: Double = 0.12
    static let highlightAlpha: Double = 0.18

    let look: Look

    @MainActor
    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, look: look)
    }

    struct Body: View {
        let configuration: Configuration
        let look: Look

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        private var isLarge: Bool {
            if case .large = look { return true }
            return false
        }

        private var emphasis: Emphasis? {
            if case .large(let emphasis) = look { return emphasis }
            return nil
        }

        private var isHoverLook: Bool {
            isHovering && isEnabled && !configuration.isPressed
        }

        /// Idle glow of the prominent CTA (T6): dark only, never under Reduce Motion.
        private var glowColor: Color {
            guard emphasis == .prominent, isEnabled, colorScheme == .dark, !reduceMotion else { return .clear }
            return Theme.Color.primaryDeep.opacity(Theme.Glow.idleAlpha(isDark: true))
        }

        private var opacity: Double {
            guard isEnabled else { return SOSButtonStyle.disabledOpacity }
            return configuration.isPressed ? SOSButtonStyle.pressedOpacity : 1
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: isLarge ? SOSButtonStyle.largeRadius : SOSButtonStyle.radius, style: .continuous)
            configuration.label
                .font(isLarge ? .system(size: Theme.TextSize.sm, weight: .medium) : Theme.Font.body.weight(.medium))
                .foregroundStyle(labelColor)
                .padding(.horizontal, isLarge ? SOSButtonStyle.largeHorizontalPadding : SOSButtonStyle.plainHorizontalPadding)
                .frame(minHeight: isLarge ? SOSButtonStyle.largeHeight : SOSButtonStyle.defaultHeight)
                .background { fill.clipShape(shape) }
                .overlay(alignment: .top) {
                    // "white 18 % inner highlight": a 1 pt line of 18 % white along the top edge.
                    if emphasis == .prominent, isEnabled {
                        Rectangle()
                            .fill(Theme.Color.onPrimary.opacity(SOSButtonStyle.highlightAlpha))
                            .frame(height: 1)
                    }
                }
                .overlay {
                    if emphasis == .default {
                        shape.strokeBorder(Theme.Derived.hairlineStrong, lineWidth: 1)
                    }
                }
                .shadow(color: glowColor, radius: 9, x: 0, y: 4)
                .opacity(opacity)
                .onHover { isHovering = $0 }
                .contentShape(.rect)
        }

        private var labelColor: Color {
            switch look {
            case .plain: Theme.Color.primaryBright
            case .large(emphasis: .default): Theme.Color.textPrimary
            case .large(emphasis: .prominent): Theme.Color.onPrimary
            }
        }

        /// Base fill with the hover mix on top (the prototype's `color-mix` on `:hover`).
        @ViewBuilder
        private var fill: some View {
            switch look {
            case .plain:
                if isHoverLook {
                    Theme.Derived.rowHover
                }
            case .large(emphasis: .default):
                Theme.Color.card
                if isHoverLook {
                    Theme.Color.primaryBright.opacity(SOSButtonStyle.hoverTintAlpha)
                }
            case .large(emphasis: .prominent):
                Theme.Color.primaryDeep
                if isHoverLook {
                    Theme.Color.onPrimary.opacity(SOSButtonStyle.prominentHoverAlpha)
                }
            }
        }
    }
}

extension ButtonStyle where Self == SOSButtonStyle {
    /// No fill, no border, `primaryBright` label — links, "Select All", "Deselect All".
    static var sosPlain: SOSButtonStyle { SOSButtonStyle(look: .plain) }

    /// The 34 pt large CTA, prominent unless the screen says otherwise.
    static func sosLarge(_ emphasis: SOSButtonStyle.Emphasis = .prominent) -> SOSButtonStyle {
        SOSButtonStyle(look: .large(emphasis: emphasis))
    }
}

/// The stock macOS button kinds of spec §4.4, configured once so no screen hand-rolls them.
enum SOSButtonKind: CaseIterable, Sendable {
    /// Stock `.bordered` with a neutral label.
    case `default`
    /// Stock `.borderedProminent` in `primaryDeep`. "Move to Trash" stays prominent: the Trash can be restored.
    case prominent
    /// Stock `.borderedProminent` in `dangerFill`. Only for the server-side cloud delete.
    case danger
}

extension View {
    /// A stock macOS button at the spec's 28 pt height (`.controlSize(.large)`), tinted with
    /// Palette C tokens.
    @ViewBuilder
    func sosButton(_ kind: SOSButtonKind) -> some View {
        switch kind {
        case .default:
            buttonStyle(.bordered).controlSize(.large).tint(Theme.Color.textPrimary)
        case .prominent:
            buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Color.primaryDeep)
        case .danger:
            buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Color.dangerFill)
        }
    }
}

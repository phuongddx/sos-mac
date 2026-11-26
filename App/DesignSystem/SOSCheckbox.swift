import SwiftUI

/// A checkbox (spec §4.6): a 16 × 16 visual with a hit target of at least 20 × 20, reached with padding.
///
/// | Value | Look |
/// |---|---|
/// | `off` | 1.5 pt `textSecondary` outline (X2) |
/// | `on` | `primaryDeep` fill, white check (X1) |
/// | `mixed` | `primaryDeep` fill, white minus |
/// | kept item | disabled: 0.35 opacity, dashed outline, never checked, not an accessibility element |
///
/// A kept item cannot be selected by click, Select All or keyboard. `State.toggled(isKept:)`
/// encodes that rule, so screens test their selection logic without a view.
struct SOSCheckbox: View {
    /// Tri-state value of the control.
    enum State: Equatable, Sendable, CaseIterable {
        case off, on, mixed

        init(isSelected: Bool) {
            self = isSelected ? .on : .off
        }

        /// The value after one activation. A mixed box goes to on, as a macOS checkbox does.
        func toggled() -> State {
            switch self {
            case .off, .mixed: .on
            case .on: .off
            }
        }

        /// The value after the user activates this row. A kept item is never selected — by click,
        /// Select All or keyboard (spec §4.6) — so its value never changes.
        func toggled(isKept kept: Bool) -> State {
            kept ? self : toggled()
        }

        /// "Something in this row is selected": on or mixed.
        var isChecked: Bool {
            self != .off
        }

        /// What accessibility reads as the value.
        var accessibilityValue: String {
            switch self {
            case .off: "unchecked"
            case .on: "checked"
            case .mixed: "mixed"
            }
        }
    }

    static let visualSide: CGFloat = 16
    /// HIG minimum for macOS controls (spec §8).
    static let hitSide: CGFloat = 20
    static let cornerRadius: CGFloat = 4
    static let outlineWidth: CGFloat = 1.5
    /// The kept checkbox is dimmer than a disabled button (0.42, spec §4.4): spec §4.6.
    static let keptOpacity: Double = 0.35

    let state: State
    /// The item is the recommended keep: the control is locked and drawn as kept.
    let isKept: Bool
    /// Accessibility label, e.g. "Select DerivedData".
    let label: String
    let action: () -> Void

    init(state: State, isKept: Bool = false, label: String = "Select", action: @escaping () -> Void) {
        self.state = state
        self.isKept = isKept
        self.label = label
        self.action = action
    }

    /// Convenience for a row that knows only whether it is selected.
    init(isSelected: Bool, isKept: Bool = false, label: String = "Select", action: @escaping () -> Void) {
        self.init(state: State(isSelected: isSelected), isKept: isKept, label: label, action: action)
    }

    var body: some View {
        Button(action: action) {
            Self.mark(for: state, isKept: isKept)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(CheckboxButtonStyle())
        .frame(width: Self.hitSide, height: Self.hitSide)
        .disabled(isKept)
        // A kept item's checkbox is not an accessibility element; the row reads "kept" (spec §4.6).
        .accessibilityHidden(isKept)
        .accessibilityLabel(label)
        .accessibilityValue(state.accessibilityValue)
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: - Drawing

    private static func mark(for state: State, isKept: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            if isKept {
                dashedOutline
            } else if state == .off {
                // X2: the outline is `textSecondary`, which holds on a selected row too.
                shape.strokeBorder(Theme.Color.textSecondary, lineWidth: outlineWidth)
            } else {
                // X1: `primaryDeep` in both appearances; a white check on it is 6.29:1.
                shape.fill(Theme.Color.primaryDeep)
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(Theme.Font.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Color.onPrimary)
            }
        }
        .frame(width: visualSide, height: visualSide)
        .opacity(isKept ? keptOpacity : 1)
    }

    /// `border: 1.5px dashed` — SwiftUI has no dashed stroke before macOS 15, so the path is dashed.
    private static var dashedOutline: some View {
        let inset = outlineWidth / 2
        let box = CGRect(x: inset, y: inset, width: visualSide - outlineWidth, height: visualSide - outlineWidth)
        let solid = CGPath(roundedRect: box, cornerWidth: cornerRadius - inset, cornerHeight: cornerRadius - inset, transform: nil)
        let dashed = solid.copy(dashingWithPhase: 1.5, lengths: [3, 2])
        return Path(dashed).stroke(Theme.Color.textSecondary, lineWidth: outlineWidth)
    }

    /// No bezel: the mark is the whole button. Pressing dims it.
    private struct CheckboxButtonStyle: ButtonStyle {
        @MainActor
        @ContentBuilder
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

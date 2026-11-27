import SwiftUI

/// One row of a scan's step list (spec §4.9 "Step row"): a pending, active, done or failed step,
/// shared by every module that scans.
///
/// | State | Dot (18 pt) | Label |
/// |---|---|---|
/// | pending | 1.5 pt `hairlineStrong` ring | `textSecondary` |
/// | active | `neonCyan` ring, a 3 pt cyan halo at 18 %, a 6 pt cyan dot pulsing every 2.4 s | `textPrimary` |
/// | done | `success` disc, check in `bgBase` | `textPrimary` |
/// | failed | `danger` ring, `xmark` in `danger` | `textPrimary` |
///
/// Only the active row gets the `card` fill and 1 pt `hairline`. The pulsing dot stops under
/// Reduce Motion; the cyan ring stays, because it carries state.
struct StepRowView: View {
    enum StepState {
        case pending, active, done, failed
    }

    static let dotSide: CGFloat = 18
    static let dotColumn: CGFloat = 22
    static let spacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 9
    static let outlineWidth: CGFloat = 1.5
    static let haloWidth: CGFloat = 3
    static let haloAlpha: Double = 0.18
    static let pulseDotSide: CGFloat = 6
    /// The pulsing dot's opacity at the middle of each cycle.
    static let pulseLowOpacity: Double = 0.35

    let name: String
    let meta: String?
    let state: StepState
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(name: String, meta: String?, state: StepState) {
        self.name = name
        self.meta = meta
        self.state = state
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            dot
            Text(name)
                .font(Theme.Font.body)
                .foregroundStyle(state == .pending ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let meta {
                Text(meta)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background {
            if state == .active {
                Theme.Color.card
            }
        }
        .overlay {
            if state == .active {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Derived.hairline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Dot

    private var ringColor: Color {
        switch state {
        case .pending: Theme.Derived.hairlineStrong
        case .active: Theme.Color.neonCyan
        case .done: .clear
        case .failed: Theme.Color.danger
        }
    }

    @ViewBuilder
    private var dot: some View {
        ZStack {
            switch state {
            case .pending:
                ring
            case .active:
                // The halo is a 3 pt ring outside the dot; the dot's inside stays clear.
                Circle().strokeBorder(Theme.Color.neonCyan.opacity(Self.haloAlpha), lineWidth: Self.haloWidth)
                    .frame(width: Self.dotSide + Self.haloWidth * 2, height: Self.dotSide + Self.haloWidth * 2)
                ring
                Circle()
                    .fill(Theme.Color.neonCyan)
                    .frame(width: Self.pulseDotSide, height: Self.pulseDotSide)
                    .opacity(pulse ? Self.pulseLowOpacity : 1)
                    .onAppear(perform: startPulsing)
            case .done:
                Circle()
                    .fill(Theme.Color.success)
                    .frame(width: Self.dotSide, height: Self.dotSide)
                Image(systemName: "checkmark")
                    .font(Theme.Font.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Color.bgBase)
            case .failed:
                ring
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Color.danger)
            }
        }
        .frame(width: Self.dotColumn, height: Self.dotSide)
    }

    private var ring: some View {
        Circle().strokeBorder(ringColor, lineWidth: Self.outlineWidth)
            .frame(width: Self.dotSide, height: Self.dotSide)
    }

    /// `pulse 2.4s ease-in-out infinite`: the dot fades to 35 % and back, one full cycle in `Motion.pulseDuration`.
    private func startPulsing() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: Theme.Motion.pulseDuration / 2).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    // MARK: - Accessibility

    private var stateWord: String {
        switch state {
        case .pending: "waiting"
        case .active: "in progress"
        case .done: "done"
        case .failed: "failed"
        }
    }

    private var accessibilityLabel: String {
        [name, stateWord, meta].compactMap { $0 }.joined(separator: ", ")
    }
}

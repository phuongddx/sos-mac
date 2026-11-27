import SwiftUI

/// The scanning view (spec §4.9): two columns 300 / 1fr, gap 40, the 240 pt orb with a
/// `neonCyan` sweep, a "Scanning" eyebrow with a cyan dot, the title, the step list, the
/// progress (determinate only when a total is known — otherwise the count line the screen
/// supplies) and the current path.
struct ScanningView: View {
    struct Step: Identifiable {
        let name: String
        var meta: String?
        let state: StepRowView.StepState
        var id: String { name }

        init(name: String, meta: String? = nil, state: StepRowView.StepState) {
            self.name = name
            self.meta = meta
            self.state = state
        }
    }

    static let columnSpacing: CGFloat = 40
    static let contentWidth: CGFloat = 520

    let module: ModuleIdentity
    let title: String
    var eyebrow: String = "Scanning"
    var lede: String?
    var steps: [Step] = []
    /// Determinate progress 0…1, only when a total is known; `nil` shows `countLine` instead.
    var progress: Double?
    /// The count-only line when no total is known ("Scanned 1.694.000 items…") — always the
    /// engine's real count, never a fabricated percentage.
    var countLine: String?
    /// The progress meta line's left and right labels (real values, e.g. "3 of 4 locations").
    var progressLeading: String?
    var progressTrailing: String?
    /// The path being scanned right now; leading-truncated as the prototype draws it.
    var path: String?
    /// Free slot below the path.
    var extra: AnyView

    init(module: ModuleIdentity,
         title: String,
         eyebrow: String = "Scanning",
         lede: String? = nil,
         steps: [Step] = [],
         progress: Double? = nil,
         countLine: String? = nil,
         progressLeading: String? = nil,
         progressTrailing: String? = nil,
         path: String? = nil,
         @ViewBuilder extra: () -> some View = { EmptyView() }) {
        self.module = module
        self.title = title
        self.eyebrow = eyebrow
        self.lede = lede
        self.steps = steps
        self.progress = progress
        self.countLine = countLine
        self.progressLeading = progressLeading
        self.progressTrailing = progressTrailing
        self.path = path
        self.extra = AnyView(extra())
    }

    var body: some View {
        HStack(alignment: .center, spacing: Self.columnSpacing) {
            ModuleOrbView(hue: module.hue, symbol: module.symbol, metrics: .scanning, sweep: true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.s2 - 2) {
                    Circle().fill(Theme.Color.neonCyan).frame(width: 6, height: 6)
                    Text(eyebrow.uppercased())
                }
                .font(Theme.Font.eyebrow)
                .tracking(0.72)
                .foregroundStyle(Theme.Color.textSecondary)
                .accessibilityHidden(true)

                Text(title)
                    .font(Theme.Font.title1)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(.top, Theme.Spacing.s2)
                    .padding(.bottom, Theme.Spacing.s2 - 2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let lede {
                    Text(lede)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: Self.contentWidth, alignment: .leading)
                        .padding(.bottom, Theme.Spacing.s1)
                }

                if !steps.isEmpty {
                    VStack(spacing: Theme.Spacing.s1) {
                        ForEach(steps) { step in
                            StepRowView(name: step.name, meta: step.meta, state: step.state)
                        }
                    }
                    .frame(maxWidth: Self.contentWidth, alignment: .leading)
                    .padding(.top, Theme.Spacing.s3 + 2)
                    .padding(.bottom, Theme.Spacing.s4)
                }

                progressArea
                    .frame(maxWidth: Self.contentWidth, alignment: .leading)

                if let path {
                    pathLine(path)
                }

                extra
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: Theme.Spacing.s4, leading: 56, bottom: 0, trailing: 56))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanning-view")
    }

    @ViewBuilder
    private var progressArea: some View {
        if let progress {
            VStack(alignment: .leading, spacing: Theme.Spacing.s2 - 2) {
                ProgressBarView(progress: progress)
                HStack {
                    Text(progressLeading ?? "")
                    Spacer(minLength: 0)
                    Text(progressTrailing ?? "")
                }
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
            }
        } else if let countLine {
            Text(countLine)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
        }
    }

    /// The current path (spec §4.9): a `card` line, monospaced, `textSecondary`,
    /// head-truncated so the end of the path stays visible.
    private func pathLine(_ path: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Text(path)
            .font(Theme.Font.mono)
            .foregroundStyle(Theme.Color.textSecondary)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.horizontal, Theme.Spacing.s3 - 2)
            .padding(.vertical, Theme.Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.Color.card))
            .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
            .padding(.top, Theme.Spacing.s3)
    }
}

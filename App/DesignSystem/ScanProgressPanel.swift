import SwiftUI
import CleanCore

/// The one shared "a scan is running" view — composes the existing
/// `ProgressBarView`/`StepRowView` rather than replacing them. Every module
/// with a scanning phase renders this, configured differently:
/// - `progress?.totalItems != nil` → a real percentage bar (Junk Cleaner,
///   Protection, Duplicate Finder's hashing phase, Uninstaller/Updater's
///   aggregate "X of N").
/// - `progress?.totalItems == nil` → a count-only line, never a fabricated
///   percentage (Space Lens, Cloud Cleanup, Duplicate Finder's listing phase).
struct ScanProgressPanel: View {
    struct StepModel: Identifiable {
        let id = UUID()
        let name: String
        let meta: String?
        let state: StepRowView.StepState
    }

    // Every optional/defaultable property below needs an explicit `= nil`/
    // literal default, not just an Optional type — Swift's synthesized
    // memberwise initializer only treats a property as omittable when it has
    // a real default value written. Nearly every call site across this plan
    // omits `ticker`/`etaText`, so skipping the `= nil` here would make this
    // view fail to compile at almost every consumer.
    var progress: ScanProgress? = nil
    var ticker: String? = nil
    var etaText: String? = nil
    var showCurrentPath = false
    var steps: [StepModel] = []
    /// Overridable only so a caller can rename "items" to something more
    /// specific (e.g. "files", "apps") — the default matches Space Lens's
    /// existing count-only copy.
    var countOnlyLabel: (Int) -> String = { "Scanned \($0.formatted()) items…" }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let ticker {
                Text(ticker)
                    .font(.system(size: Theme.TextSize.base, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
            }

            if let progress {
                if let total = progress.totalItems, total > 0 {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressBarView(progress: Double(progress.itemsProcessed) / Double(total))
                        Text(percentageLabel(processed: progress.itemsProcessed, total: total))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.muted)
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                } else {
                    Text(countOnlyLabel(progress.itemsProcessed))
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                }
            }

            if let etaText {
                Text(etaText)
                    .font(.system(size: Theme.TextSize.xs))
                    .foregroundStyle(Theme.muted)
            }

            if !steps.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(steps) { step in
                        StepRowView(name: step.name, meta: step.meta, state: step.state)
                    }
                }
            }

            if showCurrentPath, let path = progress?.currentPath {
                Text(path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func percentageLabel(processed: Int, total: Int) -> String {
        let percent = Int((Double(processed) / Double(total) * 100).rounded())
        return "\(min(max(percent, 0), 100))%"
    }
}

#Preview("Determinate — bar + path (Protection-style)") {
    ScanProgressPanel(
        progress: ScanProgress(itemsProcessed: 640, totalItems: 1000, currentPath: "~/Downloads/invoice.pdf"),
        ticker: "640 files scanned",
        etaText: "~2 minutes remaining",
        showCurrentPath: true
    )
    .padding()
    .frame(width: 420)
}

#Preview("Count-only (Space Lens-style)") {
    ScanProgressPanel(progress: ScanProgress(itemsProcessed: 83000, totalItems: nil))
        .padding()
        .frame(width: 420)
}

#Preview("Step list, no bar yet (Duplicate Finder listing phase)") {
    ScanProgressPanel(steps: [
        .init(name: "Scanning files…", meta: nil, state: .active),
        .init(name: "Hashing files…", meta: "Waiting…", state: .pending)
    ])
    .padding()
    .frame(width: 420)
}

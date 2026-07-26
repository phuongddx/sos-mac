# Phase 2: Shared DesignSystem UI

Back to [plan.md](plan.md). Depends on [Phase 1](phase-01-cleancore-foundation.md) (`ScanProgress`).

**Note on verification in this phase:** the App target has no unit test target (only `SOSMacUITests`, a screenshot-only UI test target — see plan.md's Global Constraints). Both tasks below are pure-Swift/SwiftUI additions with nothing to wire into a live screen yet, so "verification" here is: it compiles, and (Task 8) a `#Preview` renders each configuration correctly. Real behavioral verification happens in Phase 3's Task 9, the first task that actually consumes both types on a live screen.

---

### Task 7: `ScanProgressTracker`

**Files:**
- Create: `App/DesignSystem/ScanProgressTracker.swift`

**Interfaces:**
- Consumes: `ScanProgress` from CleanCore (Phase 1).
- Produces: `@MainActor @Observable final class ScanProgressTracker` with `start()`, `record(_:)`, `reset()`, `progress: ScanProgress?`, `estimatedTimeRemaining: TimeInterval?`, `estimatedTimeRemainingText: String?`. Every per-module ViewModel task in Phases 3–6 owns exactly one instance of this.

- [ ] **Step 1: Implement**

Create `App/DesignSystem/ScanProgressTracker.swift`:

```swift
import Foundation
import Observation
import CleanCore

/// Presentation-layer only — CleanCore has no business estimating wall-clock
/// ETAs. Each feature ViewModel owns one instance: call `start()` when a scan
/// begins and `record(_:)` from inside the engine's `onProgress` closure,
/// hopped to `@MainActor` first — the same pattern `SpaceLensViewModel`
/// already used for its own ad hoc progress callback.
@MainActor
@Observable
final class ScanProgressTracker {
    private(set) var progress: ScanProgress?
    private var startedAt: Date?
    // Injectable for deterministic testing, matching the same pattern
    // `JunkScanner`'s injectable `now` closure already uses in CleanCore —
    // there's no test target wired to this file today, but this keeps the
    // door open at zero cost rather than hardcoding `Date()`.
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func start() {
        startedAt = now()
        progress = nil
    }

    func record(_ progress: ScanProgress) {
        self.progress = progress
    }

    func reset() {
        startedAt = nil
        progress = nil
    }

    /// `nil` until there's enough signal (≥20 items processed) to avoid a
    /// wild first-tick estimate, or whenever `totalItems` isn't known at all.
    var estimatedTimeRemaining: TimeInterval? {
        guard let progress, let total = progress.totalItems, let startedAt,
              progress.itemsProcessed >= 20, progress.itemsProcessed < total else { return nil }
        let elapsed = now().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }
        let rate = Double(progress.itemsProcessed) / elapsed
        guard rate > 0 else { return nil }
        return Double(total - progress.itemsProcessed) / rate
    }

    var estimatedTimeRemainingText: String? {
        guard let seconds = estimatedTimeRemaining else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes <= 0 { return "Less than a minute remaining" }
        return "~\(minutes) minute\(minutes == 1 ? "" : "s") remaining"
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: Succeeds — `project.yml`'s `SOSMac` target already globs `App/` as its source path, so the new file is picked up automatically; this step just refreshes `SOSMac.xcodeproj` to reflect it.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add App/DesignSystem/ScanProgressTracker.swift SOSMac.xcodeproj
git commit -m "feat(design-system): add ScanProgressTracker for ETA/rate math"
```

---

### Task 8: `ScanProgressPanel`

**Files:**
- Create: `App/DesignSystem/ScanProgressPanel.swift`

**Interfaces:**
- Consumes: `ScanProgress` from CleanCore (Phase 1); `ProgressBarView` (`App/DesignSystem/ProgressBarView.swift`, `init(progress: Double, style: AnyShapeStyle = ...)`); `StepRowView` (`App/DesignSystem/StepRowView.swift`, `init(name: String, meta: String?, state: StepRowView.StepState)`, where `StepState` is `.pending`/`.active`/`.done`); `Theme` tokens.
- Produces: `struct ScanProgressPanel: View` with a nested `ScanProgressPanel.StepModel` (`Identifiable`, wraps `name`/`meta`/`state` since `StepRowView` itself has no `Identifiable` model type to reuse directly for a `ForEach`). Every module task in Phases 3–6 renders exactly this view during its scanning phase.

- [ ] **Step 1: Implement**

Create `App/DesignSystem/ScanProgressPanel.swift`:

```swift
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
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`

- [ ] **Step 3: Build, then visually check all three `#Preview`s in Xcode**

Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`. Then open `SOSMac.xcodeproj`, open `App/DesignSystem/ScanProgressPanel.swift`, and check the canvas (⌘⌥P if not already open) renders all three previews without a broken layout: the determinate bar shows a filled gradient + "64%" + ticker + ETA + monospaced path; the count-only preview shows plain muted text with no bar; the step-list preview shows two `StepRowView` rows (one pulsing/active, one pending) and no bar or ticker.

- [ ] **Step 4: Commit**

```bash
git add App/DesignSystem/ScanProgressPanel.swift SOSMac.xcodeproj
git commit -m "feat(design-system): add shared ScanProgressPanel view"
```

---

Phase 2 complete once both tasks are committed and the build is green. Continue to [Phase 3](phase-03-junk-cleaner-and-protection.md).

import Foundation
import Observation
import CleanCore

/// Presentation-layer only — CleanCore has no business estimating wall-clock
/// ETAs. Each feature ViewModel owns one instance: call `start()` when a scan
/// begins and `record(_:generation:)` from inside the engine's `onProgress`
/// closure, hopped to `@MainActor` first — the same pattern
/// `SpaceLensViewModel` already used for its own ad hoc progress callback.
@MainActor
@Observable
final class ScanProgressTracker {
    private(set) var progress: ScanProgress?
    private var startedAt: Date?
    /// Bumped by every `start()`. The MainActor-hop `Task`s that carry engine
    /// progress into this tracker are unstructured and therefore *not*
    /// cancelled along with the scan's own `Task` — so after a
    /// cancel-then-restart, hop-Tasks enqueued by the old scan can still land
    /// here and clobber the new scan's freshly reset state. Every call site
    /// captures the generation `start()` returned and passes it back to
    /// `record(_:generation:)`, which drops anything stale.
    private var generation = 0
    // Injectable for deterministic testing, matching the same pattern
    // `JunkScanner`'s injectable `now` closure already uses in CleanCore —
    // there's no test target wired to this file today, but this keeps the
    // door open at zero cost rather than hardcoding `Date()`.
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// Returns the generation token this scan must tag its progress with.
    @discardableResult
    func start() -> Int {
        generation += 1
        startedAt = now()
        progress = nil
        return generation
    }

    func record(_ progress: ScanProgress, generation: Int) {
        guard generation == self.generation else { return }
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

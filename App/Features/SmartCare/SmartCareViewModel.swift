import Foundation
import Observation
import CleanCore

struct SmartCareReviewItem: Identifiable {
    let sourceModule: String
    let item: ScanItem
    var id: String { item.path }
}

/// A quick, read-only Performance health readout shown alongside the cleanup
/// summary — not part of the reclaimable-items list, since CPU/memory/
/// thermal numbers aren't files to select and delete. Purely a presentation
/// composition of existing CleanCore Performance APIs; no new business logic.
struct PerformanceSnapshot {
    let oneMinuteLoad: Double?
    let memoryUsedBytes: UInt64?
    let memoryTotalBytes: UInt64?
    let thermalState: ThermalState

    static func capture() -> PerformanceSnapshot {
        let memory = MachHostStats.memoryInfo()
        return PerformanceSnapshot(
            oneMinuteLoad: SysctlReader.loadAverages()?.oneMinute,
            memoryUsedBytes: memory?.usedBytes,
            memoryTotalBytes: memory?.totalBytes,
            thermalState: IOKitSensors.thermalState()
        )
    }
}

@MainActor
@Observable
final class SmartCareViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case review
        case cleaning
        case summary(reclaimedBytes: Int64, itemCount: Int, failureCount: Int)
    }

    enum ModuleStatus: Equatable {
        case pending
        case scanning
        case done(count: Int)
        case failed
    }

    static let junkModuleName = "Junk & Cache"
    static let duplicatesModuleName = "Duplicate Files"

    let rootPath: String
    private(set) var phase: Phase = .idle
    private(set) var moduleStatuses: [String: ModuleStatus] = [:]
    private(set) var moduleProgress: [String: ScanProgress] = [:]
    private(set) var reviewItems: [SmartCareReviewItem] = []
    private(set) var performanceSnapshot: PerformanceSnapshot?
    var selectedPaths: Set<String> = []
    private(set) var errorMessage: String?

    private let orchestrator: SmartCareOrchestrator
    private var scanTask: Task<Void, Never>?

    init(rootPath: String = NSHomeDirectory()) {
        self.rootPath = rootPath
        // Only the pre-vetted "safe" subset — see JunkRule.smartCareEligible.
        // Duplicate Finder is deliberately NOT run through this generic
        // orchestrator: its DuplicateGroup structure (which item is the
        // recommended "keep") is needed for correct pre-selection below, and
        // the generic Scanner.scan() interface flattens that away.
        self.orchestrator = SmartCareOrchestrator(scanners: [
            .init(name: Self.junkModuleName, scanner: JunkScanner(rules: JunkRule.smartCareEligible))
        ])
    }

    var totalSelectedBytes: Int64 {
        reviewItems
            .filter { selectedPaths.contains($0.item.path) }
            .reduce(0) { $0 + $1.item.size }
    }

    /// The unweighted mean of each in-flight module's OWN completion
    /// fraction, rendered against a synthetic denominator.
    ///
    /// Summing raw numerators/denominators across modules would be
    /// dimensionally meaningless here: Junk reports in RULE units (3 rules,
    /// done in seconds) while Duplicates reports in FILE units (tens of
    /// thousands, taking minutes), and both stay `.scanning` until *both*
    /// legs resolve. Σ/Σ therefore reads ~100% while Duplicates hasn't
    /// started, then collapses the instant it reports its first huge-
    /// denominator tick. Averaging fractions keeps the bar monotonic-ish and
    /// dimensionless.
    ///
    /// `nil` (no bar, step list only) until EVERY in-flight module has
    /// reported at least once — a fraction covering only some of them would
    /// be built on incomplete information.
    var aggregateProgress: ScanProgress? {
        let inFlightModuleNames = moduleStatuses.filter { $0.value == .scanning }.map(\.key)
        guard !inFlightModuleNames.isEmpty else { return nil }

        let fractions = inFlightModuleNames.compactMap { name -> Double? in
            guard let progress = moduleProgress[name], let total = progress.totalItems, total > 0 else { return nil }
            return min(Double(progress.itemsProcessed) / Double(total), 1)
        }
        guard fractions.count == inFlightModuleNames.count else { return nil }

        let averageFraction = fractions.reduce(0, +) / Double(fractions.count)
        let scaledTotal = 1000
        return ScanProgress(
            itemsProcessed: Int((averageFraction * Double(scaledTotal)).rounded()),
            totalItems: scaledTotal
        )
    }

    func startScan() {
        guard phase != .scanning else { return } // re-entrancy guard: ignore a second tap mid-scan
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
    }

    /// The Duplicate Finder leg here is the exact same full-home-directory
    /// SizeGrouper + streaming-SHA-256 scan as standalone Phase 3 — not
    /// lighter just because it's wrapped in Smart Care. Without this,
    /// navigating away mid-scan would leave it hashing files in the
    /// background with nothing able to stop it, the same class of bug
    /// Space Lens/Duplicate Finder already had to fix.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .idle }
    }

    private func performScan() async {
        phase = .scanning
        errorMessage = nil
        moduleStatuses = [Self.junkModuleName: .pending, Self.duplicatesModuleName: .pending]
        moduleProgress = [:]
        performanceSnapshot = PerformanceSnapshot.capture()

        async let junkReport = orchestrator.run(
            onModuleStart: { [weak self] name in
                Task { @MainActor in self?.moduleStatuses[name] = .scanning }
            },
            onItemProgress: { [weak self] name, progress in
                Task { @MainActor in self?.moduleProgress[name] = progress }
            }
        )

        moduleStatuses[Self.duplicatesModuleName] = .scanning
        async let duplicateResult: DuplicateScanResult? = try? await DuplicateFinder(rootPath: rootPath)
            .findExactDuplicateGroups(onProgress: { [weak self] progress in
                Task { @MainActor in self?.moduleProgress[Self.duplicatesModuleName] = progress }
            })

        let junkResult = await junkReport
        let duplicates = await duplicateResult
        guard !Task.isCancelled else { return }

        // Reconciled directly from the awaited result rather than trusted to
        // a fire-and-forget onModuleFinish callback: that callback only
        // schedules a detached MainActor Task with no ordering guarantee
        // relative to this function resuming, so relying on it alone could
        // leave a module's status stale by the time .review renders.
        for moduleResult in junkResult.moduleResults {
            moduleStatuses[moduleResult.id] = moduleResult.errorMessage != nil
                ? .failed
                : .done(count: moduleResult.items.count)
        }
        if let duplicates {
            moduleStatuses[Self.duplicatesModuleName] = .done(count: duplicates.groups.flatMap(\.items).count)
        } else {
            moduleStatuses[Self.duplicatesModuleName] = .failed
        }

        var items: [SmartCareReviewItem] = []
        var preselected: Set<String> = []
        // A file can legitimately be found by both modules (e.g. a duplicate
        // that also happens to sit in a Junk-eligible cache path) — dedup by
        // path so it's never shown twice, never double-selected, and never
        // trashed twice (which would otherwise report a false "1 item
        // couldn't be removed" for a file that was actually removed fine the
        // first time).
        var seenPaths: Set<String> = []

        for moduleResult in junkResult.moduleResults {
            for item in moduleResult.items {
                guard seenPaths.insert(item.path).inserted else { continue }
                items.append(SmartCareReviewItem(sourceModule: moduleResult.id, item: item))
                // Never auto-select anything requiring the not-yet-built
                // privileged helper, and never anything above "safe" —
                // matches every other module's own pre-selection rule.
                if item.severity == .safe, !item.requiresPrivilegedHelper {
                    preselected.insert(item.path)
                }
            }
        }

        if let duplicates {
            for group in duplicates.groups {
                for item in group.items {
                    guard seenPaths.insert(item.path).inserted else { continue }
                    items.append(SmartCareReviewItem(sourceModule: Self.duplicatesModuleName, item: item))
                    // Pre-select every duplicate EXCEPT the recommended
                    // "keep" copy — never the keeper itself.
                    if item.path != group.recommendedKeepPath {
                        preselected.insert(item.path)
                    }
                }
            }
        }

        reviewItems = items
        selectedPaths = preselected
        phase = .review
    }

    func toggleSelection(for path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// The explicit confirmation step — nothing above this point has
    /// deleted anything. This is the one thing that must never be skipped,
    /// no matter how "smart"/one-click the surrounding flow is.
    func clean() async {
        guard phase != .cleaning else { return } // re-entrancy guard: a fast double-tap shouldn't clean twice
        let toClean = reviewItems.map(\.item).filter { selectedPaths.contains($0.path) }
        guard !toClean.isEmpty else { return }

        phase = .cleaning
        do {
            let result = try await DefaultCleaner().clean(toClean)
            let succeededPaths = Set(result.succeeded.map(\.path))
            reviewItems.removeAll { succeededPaths.contains($0.item.path) }
            selectedPaths.subtract(succeededPaths)
            phase = .summary(
                reclaimedBytes: result.reclaimedBytes,
                itemCount: result.succeeded.count,
                failureCount: result.failed.count
            )
        } catch {
            errorMessage = error.localizedDescription
            phase = .review
        }
    }

    func startNewScan() {
        phase = .idle
        moduleStatuses = [:]
        moduleProgress = [:]
        reviewItems = []
        selectedPaths = []
        performanceSnapshot = nil
        errorMessage = nil
    }
}

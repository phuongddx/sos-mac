import Foundation
import Observation
import CleanCore

/// A one-off, read-only Performance health readout shown in the results' health tile —
/// not part of the reclaimable-items list, since CPU/memory/thermal numbers aren't
/// files to select and delete. Purely a presentation composition of existing CleanCore
/// Performance APIs; no new business logic (§6.4: figures come from `PerformanceSnapshot`).
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

/// Smart Care — junk, duplicates and a read-only health check in one pass (plan PR 7).
///
/// The state table (spec §5.2, normative) this file implements:
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `idle` | "Junk and duplicates, in one pass" · three bullets (junk, duplicates, health) · the folder-access note · **Scan** |
/// | `scanning` | `scanning` | "Looking for junk and duplicates…" · steps Junk & Cache, Duplicate files, Health check (done, "Read") · aggregate progress · **Stop** (N6) |
/// | `results` | `results` (findings) | "Here's what Smart Care found" · tiles Junk & Cache, Duplicate files, Health check (full) · Review Items… · **Clean** · Scan Again |
/// | `error` (partial) | `results` (a module failed) | "Smart Care finished with a problem" · banner with the engine's reason and Try Again · the failed tile is skipped |
/// | `review` | `review` | Two sections — Junk & Cache (by rule), Duplicate files (by set); kept copies locked (§4.6, S4) |
/// | `cleaning` | `cleaning(selectedCount:)` | "Moving n of N items to the Trash…" |
/// | `done` | `done(movedBytes:movedCount:failedCount:)` | stats · a failure banner per failed item (F4) · Open Trash · Scan Again |
/// | `empty` | `results` (nothing found, no failure) | "Nothing to clean" · Scan Again · health tile |
/// | `error` (full) | `failed(message:)` | "Smart Care couldn't start" · Try Again |
///
/// Safety: every local removal goes through `ProgressiveCleaner` → the one
/// `Cleaner.clean(_:)` extension method. Smart Care's junk module uses
/// `JunkRule.smartCareEligible`, so no item ever needs the privileged helper.
@MainActor
@Observable
final class SmartCareViewModel {

    // MARK: - Phase (the screen's whole state)

    /// The state machine contract the shared frame maps from (spec §5.2, normative).
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case review
        case cleaning(selectedCount: Int)
        case done(movedBytes: Int64, movedCount: Int, failedCount: Int)
        case failed(message: String)
    }

    enum ModuleStatus: Equatable {
        case pending
        case scanning
        case done(count: Int)
        case failed
    }

    /// A snapshot of the per-item cleaning loop (spec §6.5): `attemptedCount` is the
    /// number of items tried so far, `totalCount` the selection size the user confirmed.
    struct CleaningProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
    }

    static let junkModuleName = "Junk & Cache"
    static let duplicatesModuleName = "Duplicate files"
    static let healthModuleName = "Health check"

    let rootPath: String
    private(set) var phase: Phase = .idle
    private(set) var moduleStatuses: [String: ModuleStatus] = [:]
    private(set) var moduleProgress: [String: ScanProgress] = [:]
    private(set) var reviewItems: [SmartCareReviewItem] = []
    private(set) var junkGroups: [SmartCareReviewGroup] = []
    private(set) var duplicateGroups: [SmartCareReviewGroup] = []
    private(set) var performanceSnapshot: PerformanceSnapshot?
    private(set) var selectedPaths: Set<String> = []
    /// Per-item failures of the last clean, surfaced on Done (F4) — never dropped.
    private(set) var lastFailedItems: [CleanResult.FailedItem] = []
    /// Real per-item cleaning progress (N5, §6.5); `nil` outside `cleaning`.
    private(set) var cleaningProgress: CleaningProgress?
    /// A junk module's engine reason when its leg failed (partial failure → results
    /// with a skipped tile and a banner; both legs failing is `.failed`, not results).
    private(set) var junkErrorMessage: String?
    /// The duplicate pass's engine reason, same rules as above.
    private(set) var duplicateErrorMessage: String?

    /// Review navigation — per-row UI state, deliberately not part of `Phase` (§6.6
    /// keeps results, selection and phase; the focused row is allowed to reset).
    var currentGroupID: String?
    var focusedItemPath: String?

    private let junkRules: [JunkRule]
    private let orchestrator: SmartCareOrchestrator
    /// The duplicate-pass source: the same full-Home exact-duplicate pass as standalone
    /// Duplicate Finder (spec §5.2). `.custom` is the test seam — fixture doubles never
    /// forward progress, so the seam carries no escaping dance.
    enum DuplicateScanSource {
        case finder(DuplicateFinder)
        case custom(@Sendable (@Sendable (ScanProgress) -> Void) async throws -> DuplicateScanResult)
    }
    private let duplicateScanSource: DuplicateScanSource
    private let cleaner: any Cleaner
    private let progressiveCleaner = ProgressiveCleaner()
    private var scanTask: Task<Void, Never>?
    /// Bumped by every `startScan()` and `cancelScan()`. The `Task { @MainActor … }`
    /// hops that carry engine progress into this view model are unstructured — not
    /// children of the scan task — so cancelling does not stop them, and after a
    /// cancel-then-restart (or Stop alone) hops from the old scan can still land and
    /// clobber reset state or the new scan's progress. Every hop captures the
    /// generation its scan was launched with and drops writes from any other — the
    /// same guard `ScanProgressTracker` uses.
    private var scanGeneration = 0

    init(rootPath: String = NSHomeDirectory(),
         orchestrator: SmartCareOrchestrator? = nil,
         junkRules: [JunkRule] = JunkRule.smartCareEligible,
         cleaner: any Cleaner = DefaultCleaner(),
         duplicateScan: DuplicateScanSource? = nil) {
        self.rootPath = rootPath
        self.junkRules = junkRules
        // Only the pre-vetted "safe" subset — see JunkRule.smartCareEligible. Duplicate
        // Finder is deliberately NOT run through the generic orchestrator: its
        // DuplicateGroup structure (which item is the recommended "keep") is needed for
        // the keep lock, and the generic Scanner.scan() interface flattens that away.
        self.orchestrator = orchestrator ?? SmartCareOrchestrator(scanners: [
            .init(name: Self.junkModuleName, scanner: JunkScanner(rules: junkRules))
        ])
        self.cleaner = cleaner
        self.duplicateScanSource = duplicateScan ?? .finder(DuplicateFinder(rootPath: rootPath))
    }

    // MARK: - Lifecycle mapping (the reference screen's pattern step 3)

    /// The pure mapping the shared frame renders from. F3: `empty` means every step
    /// succeeded and found nothing — a failed module is `results` with a skipped tile
    /// and a banner, never "nothing found"; both modules failing is `.failed`.
    var lifecycle: LifecycleState {
        switch phase {
        case .idle: .start
        case .scanning: .scanning
        case .results: hasModuleFailure || !reviewItems.isEmpty ? .results : .empty
        case .review: .review
        case .cleaning: .cleaning
        case .done: .done
        case .failed: .error
        }
    }

    /// True while files are moving — the re-entrancy guard's input (a second `clean()`
    /// call, a second scan, and the sidebar busy dot all read it).
    var isCleaning: Bool {
        if case .cleaning = phase { return true }
        return false
    }

    /// Whether one of the two scan legs failed in the last completed scan.
    var hasModuleFailure: Bool {
        junkErrorMessage != nil || duplicateErrorMessage != nil
    }

    // MARK: - Derived state (real values only)

    /// The pre-selection rule (spec §5.2, unchanged): junk that is safe and needs no
    /// helper; every duplicate except the newest copy. `Select All` uses the same
    /// predicate — it never widens what the screen pre-selects, and S4's keep lock is
    /// checked first.
    static func isPreSelectable(_ item: SmartCareReviewItem) -> Bool {
        if item.isRecommendedKeep { return false }
        if item.sourceModule == duplicatesModuleName { return true }
        return item.item.severity == .safe && !item.item.requiresPrivilegedHelper
    }

    var selectedItems: [SmartCareReviewItem] {
        reviewItems.filter { selectedPaths.contains($0.id) }
    }

    var totalSelectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.item.size }
    }

    var totalBytes: Int64 {
        reviewItems.reduce(0) { $0 + $1.item.size }
    }

    private var junkItems: [SmartCareReviewItem] {
        reviewItems.filter { $0.sourceModule == Self.junkModuleName }
    }

    private var duplicateItems: [SmartCareReviewItem] {
        reviewItems.filter { $0.sourceModule == Self.duplicatesModuleName }
    }

    var junkTotalBytes: Int64 {
        junkItems.reduce(0) { $0 + $1.item.size }
    }

    var selectedJunkBytes: Int64 {
        junkItems.filter { selectedPaths.contains($0.id) }.reduce(0) { $0 + $1.item.size }
    }

    var junkItemsCount: Int {
        junkItems.count
    }

    var selectedJunkCount: Int {
        junkItems.count { selectedPaths.contains($0.id) }
    }

    /// Selected junk that is not "safe" — the "need a look" half of the junk tile's split.
    var selectedCautionJunkCount: Int {
        junkItems.count { selectedPaths.contains($0.id) && $0.item.severity != .safe }
    }

    /// Caution junk — "need a look", never pre-selected.
    var cautionJunkCount: Int {
        junkItems.count { $0.item.severity != .safe }
    }

    /// The junk tile's "in 3 locations" — the injected rule count, so the copy always
    /// describes the exact set a scan walks.
    var junkLocationCount: Int { junkRules.count }

    var duplicateSetCount: Int { duplicateGroups.count }

    /// Copies the user can move — every duplicate except each set's keep (S4).
    var extraCopyCount: Int {
        duplicateItems.count { !$0.isRecommendedKeep }
    }

    var selectedDuplicateCount: Int {
        duplicateItems.count { selectedPaths.contains($0.id) }
    }

    var selectedDuplicateBytes: Int64 {
        duplicateItems.filter { selectedPaths.contains($0.id) }.reduce(0) { $0 + $1.item.size }
    }

    /// The unweighted mean of each in-flight module's OWN completion fraction,
    /// rendered against a synthetic denominator.
    ///
    /// Summing raw numerators/denominators across modules would be dimensionally
    /// meaningless here: Junk reports in RULE units (3 rules, done in seconds) while
    /// Duplicates reports in FILE units (tens of thousands, taking minutes). Averaging
    /// fractions keeps the bar monotonic-ish and dimensionless. `nil` (no bar, step
    /// list only) until EVERY in-flight module has reported at least once.
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

    var currentGroup: SmartCareReviewGroup? {
        let groups = junkGroups + duplicateGroups
        if let currentGroupID, let found = groups.first(where: { $0.id == currentGroupID }) {
            return found
        }
        return groups.first
    }

    /// The item whose detail the review frame shows: the focused row, or the first row
    /// of the current group (the prototype's fallback), or nothing.
    var focusedItem: SmartCareReviewItem? {
        let group = currentGroup?.items ?? []
        if let focusedItemPath, let found = group.first(where: { $0.id == focusedItemPath }) {
            return found
        }
        return group.first
    }

    // MARK: - Scan

    /// `false` when a scan or clean is already running (PR 3 re-entrancy guard).
    @discardableResult
    func startScan() -> Bool {
        guard phase != .scanning, !isCleaning else { return false }
        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.performScan(generation: generation)
        }
        return true
    }

    /// F2: Stop returns to `start` and discards results — including the previous scan's,
    /// which would otherwise look like the outcome of this one. The duplicate pass is
    /// the same full-home scan as standalone Duplicate Finder; cancelling the task stops
    /// its hashing loop (`Task.checkCancellation`), so nothing keeps running behind a
    /// screen nobody is watching.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        // Drop any progress hops still in flight from the cancelled scan, so they cannot
        // write into the state reset below.
        scanGeneration += 1
        guard phase == .scanning else { return }
        resetScanState()
        phase = .idle
    }

    private func resetScanState() {
        reviewItems = []
        selectedPaths = []
        junkGroups = []
        duplicateGroups = []
        currentGroupID = nil
        focusedItemPath = nil
        lastFailedItems = []
        cleaningProgress = nil
        junkErrorMessage = nil
        duplicateErrorMessage = nil
        moduleStatuses = [:]
        moduleProgress = [:]
        performanceSnapshot = nil
    }

    private func performScan(generation: Int) async {
        phase = .scanning
        lastFailedItems = []
        junkErrorMessage = nil
        duplicateErrorMessage = nil
        moduleStatuses = [Self.junkModuleName: .pending, Self.duplicatesModuleName: .pending]
        moduleProgress = [:]
        performanceSnapshot = PerformanceSnapshot.capture()

        async let junkReport = orchestrator.run(
            onModuleStart: { [weak self] name in
                Task { @MainActor in
                    guard let self, self.scanGeneration == generation else { return }
                    self.moduleStatuses[name] = .scanning
                }
            },
            onItemProgress: { [weak self] name, progress in
                Task { @MainActor in
                    guard let self, self.scanGeneration == generation else { return }
                    self.moduleProgress[name] = progress
                }
            }
        )

        moduleStatuses[Self.duplicatesModuleName] = .scanning
        let duplicateProgressHandler: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.scanGeneration == generation else { return }
                self.moduleProgress[Self.duplicatesModuleName] = progress
            }
        }
        var duplicates: DuplicateScanResult?
        do {
            switch duplicateScanSource {
            case .finder(let finder):
                duplicates = try await finder.findExactDuplicateGroups(onProgress: duplicateProgressHandler)
            case .custom(let scan):
                duplicates = try await scan(duplicateProgressHandler)
            }
        } catch {
            // Stop (F2) lands here as CancellationError — never shown as a failure.
            if !Task.isCancelled {
                duplicateErrorMessage = error.localizedDescription
            }
        }

        let junkResult = await junkReport
        guard !Task.isCancelled, generation == scanGeneration else { return }

        // Reconciled directly from the awaited result rather than trusted to a
        // fire-and-forget onModuleFinish callback (no ordering guarantee relative to
        // this function resuming).
        var junkError: String?
        for moduleResult in junkResult.moduleResults {
            moduleStatuses[moduleResult.id] = moduleResult.errorMessage != nil
                ? .failed
                : .done(count: moduleResult.items.count)
            if let message = moduleResult.errorMessage, junkError == nil {
                junkError = message
            }
        }
        if let duplicates {
            moduleStatuses[Self.duplicatesModuleName] = .done(count: duplicates.groups.flatMap(\.items).count)
        } else {
            moduleStatuses[Self.duplicatesModuleName] = .failed
            if duplicateErrorMessage == nil {
                duplicateErrorMessage = junkError
            }
        }

        // F3: a failed module is results with a skipped tile and a banner — unless both
        // legs failed and nothing usable remains; then the scan itself is the failure.
        junkErrorMessage = junkError
        if junkError != nil && duplicateErrorMessage != nil {
            phase = .failed(message: junkError ?? duplicateErrorMessage ?? "The scan stopped.")
            return
        }

        let built = SmartCareReviewBuilder.build(junkItems: junkResult.moduleResults.flatMap(\.items),
                                                 junkModuleID: Self.junkModuleName,
                                                 duplicatesModuleID: Self.duplicatesModuleName,
                                                 duplicateGroups: duplicates?.groups ?? [])
        reviewItems = built.items
        junkGroups = built.junkGroups
        duplicateGroups = built.duplicateGroups
        // Pre-selection is unchanged (§5.2): safe junk without the helper, every
        // duplicate except the keep.
        selectedPaths = Set(built.items.filter(Self.isPreSelectable).map(\.id))
        currentGroupID = built.junkGroups.first?.id ?? built.duplicateGroups.first?.id
        focusedItemPath = nil
        phase = .results
    }

    // MARK: - Review

    func enterReview() {
        guard phase == .results, !reviewItems.isEmpty else { return }
        phase = .review
        if currentGroupID == nil || (junkGroups + duplicateGroups).first(where: { $0.id == currentGroupID }) == nil {
            currentGroupID = currentGroup?.id
            focusedItemPath = nil
        }
    }

    func backToResults() {
        guard phase == .review else { return }
        phase = .results
    }

    func selectGroup(_ id: String) {
        currentGroupID = id
        focusedItemPath = nil
    }

    func focusItem(path: String) {
        focusedItemPath = path
    }

    /// S4 (§4.6): the keep copy cannot be selected — by click, Select All or keyboard.
    /// The row renders locked; this guard is the model-side half.
    func toggleSelection(path: String) {
        guard let item = reviewItems.first(where: { $0.id == path }), !item.isRecommendedKeep else { return }
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// Select All in the current group — selects only what the screen would pre-select
    /// (§4.5: never a keep, never a caution item). Manual row toggles are still allowed
    /// for caution items; only the bulk action is fenced, and keeps are fenced for both.
    func selectAllEligibleInCurrentGroup() {
        guard let group = currentGroup else { return }
        selectedPaths.formUnion(group.items.filter(Self.isPreSelectable).map(\.id))
    }

    func deselectAllInCurrentGroup() {
        guard let group = currentGroup else { return }
        for item in group.items {
            selectedPaths.remove(item.id)
        }
    }

    /// The confirmation model for both removal entry points (CF-3: the count and size are
    /// the same numbers the review bar shows, computed here once). "Review Items…" is
    /// offered only when the sheet is opened from `results` (§4.8).
    func trashConfirmation(isFromResults: Bool) -> ConfirmSheet.Model {
        let selected = selectedItems
        let count = selected.count
        let sizeText = ConfirmItemList.sizeText(for: selected.reduce(0) { $0 + $1.item.size })
        // Smart Care's rule set excludes helper items; compute anyway so the dialog
        // stays honest if the engine ever changes (fail closed, never guess).
        let includesHelper = selected.contains { $0.item.requiresPrivilegedHelper }
        let items: [ConfirmItem] = selected.map { reviewItem in
            ConfirmItem(id: reviewItem.id,
                        name: (reviewItem.item.path as NSString).lastPathComponent,
                        path: reviewItem.item.path,
                        size: reviewItem.item.size)
        }
        var reviewItemsAction: (@MainActor () -> Void)?
        if isFromResults {
            reviewItemsAction = { [weak self] in self?.enterReview() }
        }
        return ConfirmSheet.Model(
            variant: .trash,
            count: count,
            sizeText: sizeText,
            includesSystemCaches: includesHelper,
            isFromResults: isFromResults,
            items: items,
            hue: Theme.Hue.smartcare,
            confirm: { [weak self] _ in self?.beginClean() },
            cancel: { },
            reviewItems: reviewItemsAction)
    }

    /// Starts the confirmed clean from the sheet's synchronous callback; the sheet is
    /// already dismissed when this runs. This is all the confirm closure does.
    private func beginClean() {
        Task { [weak self] in
            await self?.clean()
        }
    }

    // MARK: - Clean

    /// Moves the confirmed selection. Re-entrant calls are refused while a clean is in
    /// flight (the disabled "Moving" CTA is the same guard's UI half).
    @discardableResult
    func clean() async -> Bool {
        guard !isCleaning else { return false }
        let toClean = selectedItems.map(\.item)
        guard !toClean.isEmpty else { return false }

        phase = .cleaning(selectedCount: toClean.count)
        cleaningProgress = CleaningProgress(attemptedCount: 0,
                                            totalCount: toClean.count,
                                            currentPath: nil)
        lastFailedItems = []

        // Spec §6.5: one `Cleaner.clean([item])` per item through the one trash-routed
        // extension method, with real per-item progress.
        let result = await progressiveCleaner.clean(toClean, using: cleaner) { [weak self] index, item in
            self?.cleaningProgress = CleaningProgress(attemptedCount: index + 1,
                                                      totalCount: toClean.count,
                                                      currentPath: item.path)
        }

        let succeededPaths = Set(result.succeeded.map(\.path))
        reviewItems.removeAll { succeededPaths.contains($0.id) }
        selectedPaths.subtract(succeededPaths)
        rebuildReviewGroups()
        cleaningProgress = nil
        lastFailedItems = result.failed
        phase = .done(movedBytes: result.reclaimedBytes,
                      movedCount: result.succeeded.count,
                      failedCount: result.failed.count)
        return true
    }

    /// Groups are rebuilt from the surviving items after a clean — empty groups drop out
    /// so the review never shows a group whose files have moved.
    private func rebuildReviewGroups() {
        let alive = Set(reviewItems.map(\.id))
        junkGroups = junkGroups.compactMap { group in
            let items = group.items.filter { alive.contains($0.id) }
            return items.isEmpty ? nil : group.withItems(items)
        }
        duplicateGroups = duplicateGroups.compactMap { group in
            let items = group.items.filter { alive.contains($0.id) }
            return items.isEmpty ? nil : group.withItems(items)
        }
        if let id = currentGroupID,
           !junkGroups.contains(where: { $0.id == id }),
           !duplicateGroups.contains(where: { $0.id == id }) {
            currentGroupID = nil
            focusedItemPath = nil
        }
    }

    // MARK: - Fixtures (Debug builds only)

#if DEBUG
    /// Loads one of the lifecycle states (plus Smart Care's partial-failure state) from
    /// the fictional sample data (`UITestFixtures`). Called from the screen's `.task`
    /// when `SOSMAC_UITEST_FIXTURES=1` names this screen and state; never reads the real
    /// file system.
    func loadFixture(_ state: LifecycleState) {
        switch state {
        case .start:
            applyIdleFixture()

        case .scanning:
            applyIdleFixture()
            phase = .scanning
            // Both legs active: junk 2 of 3 rules in, duplicates part-way through the
            // hash pass — real fixture figures, so the aggregate fraction is honest.
            moduleStatuses = [Self.junkModuleName: .scanning, Self.duplicatesModuleName: .scanning]
            moduleProgress[Self.junkModuleName] = ScanProgress(itemsProcessed: 2, totalItems: junkLocationCount)
            moduleProgress[Self.duplicatesModuleName] = ScanProgress(itemsProcessed: 1_240_000, totalItems: 3_400_000)

        case .results:
            applyFixtureResults()

        case .empty:
            // F3: `empty` is `results` with no findings and no failure — no Phase case.
            resetScanState()
            performanceSnapshot = Self.fixtureSnapshot()
            phase = .results

        case .review:
            applyFixtureResults()
            enterReview()
            if let first = currentGroup?.items.first?.id {
                focusItem(path: first)
            }

        case .cleaning:
            applyFixtureResults()
            let count = selectedItems.count
            phase = .cleaning(selectedCount: count)
            cleaningProgress = CleaningProgress(
                attemptedCount: 2,
                totalCount: count,
                currentPath: selectedItems.first?.item.path)

        case .done:
            // As if the pre-selection had just been moved: the moved files are gone,
            // nothing failed.
            applyFixtureResults()
            let moved = selectedItems
            let movedPaths = Set(moved.map(\.id))
            reviewItems.removeAll { movedPaths.contains($0.id) }
            selectedPaths = []
            rebuildReviewGroups()
            phase = .done(movedBytes: moved.reduce(0) { $0 + $1.item.size },
                          movedCount: moved.count,
                          failedCount: 0)

        case .error:
            applyIdleFixture()
            phase = .failed(message: "The file “Downloads” couldn’t be opened because there is no such file.")
        }
    }

    /// The partial-failure state (spec §5.2 `error` (partial)): junk succeeded and
    /// found items, the duplicate pass failed — `results` with a skipped tile, a banner
    /// and Try Again. Not a `LifecycleState` case, so the launch hook names it
    /// `SOSMAC_UITEST_STATE=partial`.
    func loadPartialFailureFixture() {
        let junkItems = Self.fixtureJunkItems()
        applyResults(junkItems: junkItems,
                     duplicateSets: [],
                     junkError: nil,
                     duplicateError: "The file “Downloads” couldn’t be opened because there is no such file.")
        moduleStatuses[Self.junkModuleName] = .done(count: junkItems.count)
        moduleStatuses[Self.duplicatesModuleName] = .failed
    }

    /// The launch-hook half of the fixture convention: applies the state named by
    /// `SOSMAC_UITEST_SCREEN`/`SOSMAC_UITEST_STATE` when fixtures are on. `partial` is
    /// Smart Care's extra state beyond the eight lifecycle states.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .smartCare else { return }
        if hooks.state == "partial" {
            loadPartialFailureFixture()
            return
        }
        guard let raw = hooks.state, let state = LifecycleState(rawValue: raw) else { return }
        loadFixture(state)
    }

    /// Test-only: the completed-scan state over arbitrary items, so clean-path tests
    /// never point the cleaner at the `/Users/sample` fixture paths (they must never
    /// reach `Cleaner.clean` — on a machine that really has such a user they would move
    /// real files). The paths need not exist.
    func loadFixtureResults(junkItems: [ScanItem], duplicateGroups: [DuplicateGroup]) {
        applyResults(junkItems: junkItems,
                     duplicateSets: duplicateGroups,
                     junkError: nil,
                     duplicateError: nil)
        moduleStatuses[Self.junkModuleName] = .done(count: junkItems.count)
        moduleStatuses[Self.duplicatesModuleName] = .done(count: duplicateGroups.flatMap(\.items).count)
    }

    private func applyIdleFixture() {
        resetScanState()
        phase = .idle
    }

    private func applyFixtureResults() {
        let junkItems = Self.fixtureJunkItems()
        let duplicateSets = Self.fixtureDuplicateGroups()
        applyResults(junkItems: junkItems,
                     duplicateSets: duplicateSets,
                     junkError: nil,
                     duplicateError: nil)
        moduleStatuses[Self.junkModuleName] = .done(count: junkItems.count)
        moduleStatuses[Self.duplicatesModuleName] = .done(count: duplicateSets.flatMap(\.items).count)
    }

    private func applyResults(junkItems: [ScanItem],
                              duplicateSets: [DuplicateGroup],
                              junkError: String?,
                              duplicateError: String?) {
        let built = SmartCareReviewBuilder.build(junkItems: junkItems,
                                                 junkModuleID: Self.junkModuleName,
                                                 duplicatesModuleID: Self.duplicatesModuleName,
                                                 duplicateGroups: duplicateSets)
        reviewItems = built.items
        junkGroups = built.junkGroups
        duplicateGroups = built.duplicateGroups
        selectedPaths = Set(built.items.filter(Self.isPreSelectable).map(\.id))
        currentGroupID = built.junkGroups.first?.id ?? built.duplicateGroups.first?.id
        focusedItemPath = nil
        lastFailedItems = []
        cleaningProgress = nil
        junkErrorMessage = junkError
        duplicateErrorMessage = duplicateError
        performanceSnapshot = Self.fixtureSnapshot()
        phase = .results
    }

    /// Smart Care's junk fixture is the helper-free subset — the same subset the
    /// production scan walks (`JunkRule.smartCareEligible`).
    private static func fixtureJunkItems() -> [ScanItem] {
        UITestFixtures.junkRules.filter { !$0.requiresHelper }.flatMap(\.items)
    }

    private static func fixtureDuplicateGroups() -> [DuplicateGroup] {
        UITestFixtures.duplicateSets.map { DuplicateGroup(id: $0.id, items: $0.items) }
    }

    /// Deterministic health figures for snapshots — the fixture metrics' memory parts
    /// summed, never a live read (fixture mode must be reproducible).
    private static func fixtureSnapshot() -> PerformanceSnapshot {
        let metrics = UITestFixtures.metrics
        let used = Int64(metrics.wired + metrics.active + metrics.compressed)
        let total = Int64(metrics.wired + metrics.active + metrics.compressed
                          + metrics.inactive + metrics.free)
        return PerformanceSnapshot(oneMinuteLoad: metrics.loadAverage.first,
                                   memoryUsedBytes: UInt64(used),
                                   memoryTotalBytes: UInt64(total),
                                   thermalState: .nominal)
    }
#endif
}

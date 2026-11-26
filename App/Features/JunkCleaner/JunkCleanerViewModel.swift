import Foundation
import Observation
import SwiftData
import CleanCore

/// Junk & Cache — **the reference screen of the UI migration (plan PR 5)**.
///
/// Every later screen PR copies the pattern set in this file:
///
/// 1. **State table** — spec §5.3's lifecycle → `Phase` → what-is-shown table, restated
///    here so the code and the spec can be checked against each other.
/// 2. **`Phase`** — one enum carrying the whole screen state; no screen-state booleans
///    (per-row state such as the focused review row is a plain stored property).
/// 3. **`lifecycle`** — a pure, unit-tested `Phase → LifecycleState` mapping that the
///    shared `ModuleScreen` frame renders from (`SOSMacTests/LifecycleMappingTests.swift`).
/// 4. **Fixture states** — `loadFixture(_:)` for each lifecycle state, Debug only
///    (`App/Support/UITestFixtures.swift` holds the fictional data).
/// 5. **Snapshots** — the eight states in dark and light, next to the prototype's
///    `index.html?screen=junk&state=…&palette=c`.
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `idle` | "Clear caches and old logs" · one bullet per rule with its root · the helper note · **Scan** |
/// | `scanning` | `scanning` | "Looking for junk files…" · four step rows · "k of 4 locations" + % · **Stop** |
/// | `results` | `results` (items found) | "«size» of junk found" · one wide tile per location · Review Items… · **Clean** · Scan Again |
/// | `empty` | `results` (no items) | "No junk found" · Scan Again |
/// | `review` | `review` | Groups = the four locations · helper banner (S7) · detail with **Ignore** (OD-8) |
/// | `cleaning` | `cleaning(selectedCount:)` | "Moving n of N files to the Trash…" + the current path |
/// | `done` | `done(movedBytes:movedCount:failedCount:)` | stats · a failure banner per failed file (F4) · Open Trash · Scan Again |
/// | `error` | `failed(message:)` | "The scan stopped" + the engine's reason · Try Again (§6.3) |
///
/// Safety: every local removal goes through `ProgressiveCleaner` → the one
/// `Cleaner.clean(_:)` extension method. Root-owned System Caches items are the single
/// documented exception — they go to the privileged helper's `trashSystemPath` (S7).
@MainActor
@Observable
final class JunkCleanerViewModel {

    // MARK: - Phase (the screen's whole state)

    /// The state machine contract the shared frame maps from (spec §5.3, normative).
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case review
        case cleaning(selectedCount: Int)
        case done(movedBytes: Int64, movedCount: Int, failedCount: Int)
        case failed(message: String)
    }

    /// A snapshot of the per-item cleaning loop (spec §6.5): `attemptedCount` is the
    /// number of items tried so far, `totalCount` the selection size the user confirmed.
    struct CleaningProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
    }

    /// One review group = one junk rule's location (spec §5.3: "Groups = the four
    /// locations"). Built by the pure `locations(from:rules:)` builder so the grouping
    /// is unit-testable without a view.
    struct JunkLocation: Identifiable, Equatable, Sendable {
        let id: String
        /// Short display name (the prototype's `short` label).
        let title: String
        /// The rule's root as the user writes it (e.g. `~/Library/Caches`).
        let root: String
        let requiresPrivilegedHelper: Bool
        let items: [ScanItem]
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [ScanItem] = []
    private(set) var selectedPaths: Set<String> = []
    /// Per-file failures of the last clean, surfaced on Done (F4) — never dropped.
    private(set) var lastFailedItems: [CleanResult.FailedItem] = []
    /// Real per-item cleaning progress (N5, §6.5); `nil` outside `cleaning`.
    private(set) var cleaningProgress: CleaningProgress?
    /// Grouped review model, rebuilt whenever `items` changes so 100 k-row result sets
    /// never re-group on the render path.
    private(set) var reviewLocations: [JunkLocation] = []

    /// A non-lifecycle action error (today: the ignore-list save failed). Rendered as a
    /// banner next to the action that caused it (N4), not as a screen state.
    private(set) var actionErrorMessage: String?

    /// Review navigation — per-row UI state, deliberately not part of `Phase` (§6.6
    /// keeps results, selection and phase; the focused row is allowed to reset).
    var currentGroupID: String?
    var focusedItemPath: String?

    let progressTracker = ScanProgressTracker()
    private var scanTask: Task<Void, Never>?

    private let rules: [JunkRule]
    private let scanner: JunkScanner
    private let cleaner: any Cleaner
    private let progressiveCleaner = ProgressiveCleaner()
    private let privilegedHelper: any JunkPrivilegedTrashing
    private let modelContext: ModelContext

    init(modelContext: ModelContext,
         rules: [JunkRule] = JunkRule.allowlist,
         cleaner: any Cleaner = DefaultCleaner(),
         privilegedHelper: any JunkPrivilegedTrashing = PrivilegedHelperClient()) {
        self.modelContext = modelContext
        self.rules = rules
        self.scanner = JunkScanner(rules: rules)
        self.cleaner = cleaner
        self.privilegedHelper = privilegedHelper
    }

    // MARK: - Lifecycle mapping (pattern step 3)

    /// The pure mapping the shared frame renders from. `results` with zero items and no
    /// failure is `empty` (F3: empty means every step succeeded and found nothing — a
    /// scan failure is `.failed`, so it can never look like "nothing found").
    var lifecycle: LifecycleState {
        switch phase {
        case .idle: .start
        case .scanning: .scanning
        case .results: items.isEmpty ? .empty : .results
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

    // MARK: - Derived state (real values only)

    /// The pre-selection rule (spec §6.1): safe junk that needs no helper. `Select All`
    /// uses the same predicate — it never widens what the screen pre-selects.
    static func isPreSelectable(_ item: ScanItem) -> Bool {
        item.severity == .safe && !item.requiresPrivilegedHelper
    }

    var selectedItems: [ScanItem] {
        items.filter { selectedPaths.contains($0.path) }
    }

    var totalSelectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    /// The rule names shown as scanning steps, in scan order.
    var ruleLabels: [String] { rules.map(\.shortLabel) }

    /// The location count the copy uses ("k of 4 locations", "all 4 locations").
    var locationCount: Int { rules.count }

    var currentLocation: JunkLocation? {
        if let currentGroupID, let found = reviewLocations.first(where: { $0.id == currentGroupID }) {
            return found
        }
        return reviewLocations.first
    }

    /// The item whose detail the review frame shows: the focused row, or the first row
    /// of the current group (the prototype's fallback), or nothing.
    var focusedItem: ScanItem? {
        let group = currentLocation?.items ?? []
        if let focusedItemPath, let found = group.first(where: { $0.path == focusedItemPath }) {
            return found
        }
        return group.first
    }

    func selectedCount(in location: JunkLocation) -> Int {
        location.items.count { selectedPaths.contains($0.path) }
    }

    /// Pure grouping (pattern step 3's testable core): one location per rule, in scan
    /// order, plus a fallback group for items whose `sourceLabel` matches no rule — the
    /// production scanner always emits the allowlist label, but fail-closed means an
    /// unexpected label is shown, never silently dropped.
    static func locations(from items: [ScanItem], rules: [JunkRule]) -> [JunkLocation] {
        var locations = rules.map { rule in
            JunkLocation(id: rule.id,
                         title: rule.shortLabel,
                         root: rule.displayRoot,
                         requiresPrivilegedHelper: rule.requiresPrivilegedHelper,
                         items: items.filter { $0.sourceLabel == rule.label })
        }
        let matchedLabels = Set(rules.map(\.label))
        let unmatched = items.filter { item in
            guard let label = item.sourceLabel else { return true }
            return !matchedLabels.contains(label)
        }
        if !unmatched.isEmpty {
            locations.append(JunkLocation(id: "other",
                                          title: unmatched.first?.sourceLabel ?? "Other",
                                          root: "",
                                          requiresPrivilegedHelper: unmatched.allSatisfy(\.requiresPrivilegedHelper),
                                          items: unmatched))
        }
        return locations
    }

    private func rebuildReviewLocations() {
        reviewLocations = Self.locations(from: items, rules: rules)
    }

    // MARK: - Scan

    /// `false` when a scan or clean is already running (PR 3 re-entrancy guard).
    @discardableResult
    func startScan() -> Bool {
        guard phase != .scanning, !isCleaning else { return false }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
        return true
    }

    /// F2: Stop returns to `start` and discards results — including the previous scan's,
    /// which would otherwise look like the outcome of this one. The engine delivers items
    /// only at completion, so nothing partial can leak in.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        guard phase == .scanning else { return }
        items = []
        selectedPaths = []
        reviewLocations = []
        currentGroupID = nil
        focusedItemPath = nil
        progressTracker.reset()
        phase = .idle
    }

    private func performScan() async {
        phase = .scanning
        lastFailedItems = []
        actionErrorMessage = nil
        let generation = progressTracker.start()
        do {
            let ignoredPaths = try fetchIgnoredPaths()
            let scanned = try await scanner.scan(onProgress: { [weak self] progress in
                Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
            })
            guard !Task.isCancelled else { return }
            items = scanned.filter { !ignoredPaths.contains($0.path) }
            // Pre-selection is unchanged (§6.1): safe rules only, helper items never.
            selectedPaths = Set(items.filter(Self.isPreSelectable).map(\.path))
            rebuildReviewLocations()
            currentGroupID = nil
            focusedItemPath = nil
            phase = .results
        } catch {
            guard !Task.isCancelled else { return }
            // §6.3: the truthful error state — the engine's own reason, no invented
            // System Caches story (the scanner skips unreadable roots; it throws only
            // on cancellation or a walker error).
            phase = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Review

    func enterReview() {
        guard phase == .results, !items.isEmpty else { return }
        phase = .review
        if currentGroupID == nil || !reviewLocations.contains(where: { $0.id == currentGroupID }) {
            currentGroupID = reviewLocations.first?.id
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

    func toggleSelection(path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// Select All in the current group — selects only what the screen would pre-select
    /// (§4.5: never a caution/risky item, never a helper item). Manual row toggles are
    /// still allowed; only the bulk action is fenced.
    func selectAllEligibleInCurrentGroup() {
        guard let group = currentLocation else { return }
        selectedPaths.formUnion(group.items.filter(Self.isPreSelectable).map(\.path))
    }

    func deselectAllInCurrentGroup() {
        guard let group = currentLocation else { return }
        for item in group.items {
            selectedPaths.remove(item.path)
        }
    }

    /// The confirmation model for both removal entry points (CF-3: the count and size are
    /// the same numbers the review bar shows, computed here once). "Review Items…" is
    /// offered only when the sheet is opened from `results` (§4.8).
    func trashConfirmation(isFromResults: Bool) -> ConfirmSheet.Model {
        let selected = selectedItems
        let count = selected.count
        let sizeText = ConfirmItemList.sizeText(for: selected.reduce(0) { $0 + $1.size })
        let includesHelper = selected.contains { $0.requiresPrivilegedHelper }
        let items: [ConfirmItem] = selected.map { item in
            ConfirmItem(id: item.path,
                        name: (item.path as NSString).lastPathComponent,
                        path: item.path,
                        size: item.size)
        }
        var reviewItems: (@MainActor () -> Void)?
        if isFromResults {
            reviewItems = { [weak self] in self?.enterReview() }
        }
        return ConfirmSheet.Model(
            variant: .trash,
            count: count,
            sizeText: sizeText,
            includesSystemCaches: includesHelper,
            isFromResults: isFromResults,
            items: items,
            hue: Theme.Hue.junk,
            confirm: { [weak self] _ in self?.beginClean() },
            cancel: { },
            reviewItems: reviewItems)
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
        let toClean = selectedItems
        guard !toClean.isEmpty else { return false }

        phase = .cleaning(selectedCount: toClean.count)
        cleaningProgress = CleaningProgress(attemptedCount: 0,
                                            totalCount: toClean.count,
                                            currentPath: nil)
        lastFailedItems = []

        // Spec §6.5: one `Cleaner.clean([item])` per item through the one trash-routed
        // extension method, with real per-item progress. Helper items are the single
        // documented exception (root-owned paths the user-context Cleaner cannot trash).
        let userItems = toClean.filter { !$0.requiresPrivilegedHelper }
        let helperItems = toClean.filter(\.requiresPrivilegedHelper)

        var succeeded: [ScanItem] = []
        var failed: [CleanResult.FailedItem] = []

        let result = await progressiveCleaner.clean(userItems, using: cleaner) { [weak self] index, item in
            self?.cleaningProgress = CleaningProgress(attemptedCount: index + 1,
                                                       totalCount: toClean.count,
                                                       currentPath: item.path)
        }
        succeeded.append(contentsOf: result.succeeded)
        failed.append(contentsOf: result.failed)

        for (offset, item) in helperItems.enumerated() {
            do {
                try await privilegedHelper.trashSystemPath(item.path)
                succeeded.append(item)
            } catch {
                failed.append(CleanResult.FailedItem(item: item, reason: error.localizedDescription))
            }
            cleaningProgress = CleaningProgress(attemptedCount: userItems.count + offset + 1,
                                                 totalCount: toClean.count,
                                                 currentPath: item.path)
        }

        let succeededPaths = Set(succeeded.map(\.path))
        items.removeAll { succeededPaths.contains($0.path) }
        selectedPaths.subtract(succeededPaths)
        rebuildReviewLocations()
        cleaningProgress = nil
        lastFailedItems = failed
        phase = .done(movedBytes: succeeded.reduce(0) { $0 + $1.size },
                      movedCount: succeeded.count,
                      failedCount: failed.count)
        return true
    }

    // MARK: - Ignore (OD-8: kept as a plain button in the detail panel)

    func ignore(_ item: ScanItem) {
        modelContext.insert(IgnoredItem(path: item.path))
        do {
            try modelContext.save()
        } catch {
            // Don't drop the item from the list on a failed save — the user would believe
            // "ignore" took effect when nothing was persisted, and the item would
            // silently reappear on the next scan.
            actionErrorMessage = "Couldn't save the ignore list: \(error.localizedDescription)"
            return
        }
        actionErrorMessage = nil
        items.removeAll { $0.path == item.path }
        selectedPaths.remove(item.path)
        if focusedItemPath == item.path { focusedItemPath = nil }
        rebuildReviewLocations()
    }

    // MARK: - Fixtures (pattern step 4; Debug builds only)

#if DEBUG
    /// Loads one of the eight lifecycle states from the fictional sample data
    /// (`UITestFixtures.junkRules`). Called from the screen's `.task` when
    /// `SOSMAC_UITEST_FIXTURES=1` names this screen and state; never reads the real
    /// file system.
    func loadFixture(_ state: LifecycleState) {
        switch state {
        case .start:
            applyIdleFixture()

        case .scanning:
            applyIdleFixture()
            phase = .scanning
            // Two of the four locations done: step rows and "2 of 4 locations".
            let generation = progressTracker.start()
            progressTracker.record(ScanProgress(itemsProcessed: 2, totalItems: locationCount),
                                   generation: generation)

        case .results:
            applyFixtureResults()

        case .empty:
            // F3: `empty` is `results` with no items — the Phase has no empty case.
            items = []
            selectedPaths = []
            reviewLocations = []
            currentGroupID = nil
            focusedItemPath = nil
            lastFailedItems = []
            actionErrorMessage = nil
            cleaningProgress = nil
            phase = .results

        case .review:
            applyFixtureResults()
            enterReview()
            if let first = currentLocation?.items.first?.path {
                focusItem(path: first)
            }

        case .cleaning:
            applyFixtureResults()
            let count = selectedItems.count
            phase = .cleaning(selectedCount: count)
            cleaningProgress = CleaningProgress(
                attemptedCount: 2,
                totalCount: count,
                currentPath: currentLocation?.items.first?.path)

        case .done:
            // As if the pre-selection had just been moved: the moved files are gone,
            // the caution and helper files remain, nothing failed.
            applyFixtureResults()
            let moved = selectedItems
            let movedPaths = Set(moved.map(\.path))
            items.removeAll { movedPaths.contains($0.path) }
            selectedPaths = []
            rebuildReviewLocations()
            phase = .done(movedBytes: moved.reduce(0) { $0 + $1.size },
                          movedCount: moved.count,
                          failedCount: 0)

        case .error:
            applyIdleFixture()
            phase = .failed(message: "The file “Caches” couldn’t be opened because there is no such file.")
        }
    }

    /// The launch-hook half of the fixture convention: applies the state named by
    /// `SOSMAC_UITEST_SCREEN`/`SOSMAC_UITEST_STATE` when fixtures are on.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .junkCleaner,
              let raw = hooks.state, let state = LifecycleState(rawValue: raw) else { return }
        loadFixture(state)
    }

    private func applyIdleFixture() {
        items = []
        selectedPaths = []
        lastFailedItems = []
        actionErrorMessage = nil
        cleaningProgress = nil
        currentGroupID = nil
        focusedItemPath = nil
        progressTracker.reset()
        rebuildReviewLocations()
        phase = .idle
    }

    private func applyFixtureResults() {
        items = UITestFixtures.junkRules.flatMap(\.items)
        selectedPaths = Set(items.filter(Self.isPreSelectable).map(\.path))
        currentGroupID = nil
        focusedItemPath = nil
        lastFailedItems = []
        actionErrorMessage = nil
        cleaningProgress = nil
        rebuildReviewLocations()
        phase = .results
    }
#endif

    // MARK: - SwiftData

    private func fetchIgnoredPaths() throws -> Set<String> {
        let descriptor = FetchDescriptor<IgnoredItem>()
        return Set(try modelContext.fetch(descriptor).map(\.path))
    }
}

// MARK: - Privileged helper seam

/// The privileged-helper operation Junk needs (S7): root-owned System Caches items are
/// moved by the helper, never by `Cleaner.clean`. The seam exists so the routing is
/// unit-testable; production always conforms `PrivilegedHelperClient`.
@MainActor
protocol JunkPrivilegedTrashing {
    func trashSystemPath(_ path: String) async throws
}

// MARK: - Rule display names (app-side; CleanCore is untouched)

extension JunkRule {
    /// The short name the UI groups, tiles and step rows show (prototype `data.js`).
    /// Unknown rule ids fall back to the engine's own full label — fail closed, no
    /// invented short name.
    var shortLabel: String {
        switch id {
        case "user-caches": "User App Caches"
        case "user-logs": "User Logs"
        case "app-support-caches": "App Support Caches"
        case "system-caches": "System Caches"
        default: label
        }
    }

    /// The root path as the user writes it. The App Support glob's many concrete roots
    /// are shown as their shared parent — the allowlist's own template, not a guess.
    var displayRoot: String {
        switch kind {
        case .directPath(let template): template
        case .applicationSupportCacheGlob: "~/Library/Application Support"
        }
    }
}

// MARK: - PrivilegedHelperClient conformance (the production route)

extension PrivilegedHelperClient: JunkPrivilegedTrashing {}

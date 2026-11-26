import Foundation
import Observation
import CleanCore

/// Duplicate Finder on the shared lifecycle frame (plan PR 6; spec §5.4). It follows the
/// pattern PR 5 (Junk & Cache) set: one `Phase` enum carrying the whole screen state, a
/// pure `Phase → LifecycleState` mapping, the Debug fixture states, and every removal
/// routed through `ProgressiveCleaner` → the one `Cleaner.clean(_:)` extension method.
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `idle` | Toolbar segment · "Find identical copies" / "Find similar images" · two bullets · hashing note · **Scan** · Similar banner (S3) |
/// | `scanning` | `scanning` | "Scanning for duplicates…" → "Hashing files…" · two steps · bar + % once hashing starts · current path · **Stop** |
/// | `results` | `results` (sets found) | "N sets of identical files" · tiles Sets found / Selected · skipped-files banner · Review Items… · **Clean** · Scan Again |
/// | `empty` | `results` (no sets) | "No duplicates found" · Scan Again |
/// | `review` | `review` | One section of sets · per-set totals (OD-b) · detail with the Keep lock |
/// | `cleaning` | `cleaning(selectedCount:)` | "Moving n of N copies to the Trash…" + the current path |
/// | `done` | `done(movedBytes:movedCount:failedCount:)` | stats · a failure banner per failed copy (S5) · Open Trash · Scan Again |
/// | `error` | `failed(message:)` | "The scan stopped" · the reason + Full Disk Access instruction (OD-18, text only) · Try Again |
///
/// Safety:
/// - The recommended **keep** copy of a set (`DuplicateGroup.recommendedKeepPath`, chosen by
///   `lastModified`, never by `lastAccessed`) can never be selected: `toggleSelection`,
///   `selectAllInCurrentSet` and the pre-selection all skip it, and `clean()` filters it out
///   once more before anything moves.
/// - Pre-selection: Exact mode selects every non-keep copy (today's rule); Similar mode
///   selects **nothing** (OD-a) — near-matches are different pictures until the user says so.
/// - Nothing is hard-deleted; the view asks for a confirmation (S1) before `clean()` runs.
@MainActor
@Observable
final class DuplicateFinderViewModel {

    /// Exact copies (byte-identical) or visually similar images — never blended (the engine
    /// keeps the two passes apart so "similar" is never presented as "identical").
    enum Mode: String, CaseIterable, Hashable, Identifiable {
        case exact = "Exact copies"
        case similarImages = "Similar images"

        var id: String { rawValue }
    }

    /// The state machine contract the shared frame maps from (spec §5.4, normative).
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case review
        case cleaning(selectedCount: Int)
        case done(movedBytes: Int64, movedCount: Int, failedCount: Int)
        case failed(message: String)
    }

    /// A snapshot of the per-item cleaning loop (spec §6.5): `attemptedCount` copies tried so
    /// far out of the `totalCount` the user confirmed.
    struct CleaningProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
    }

    /// One duplicate set as the review frame shows it: the copies and the one that is kept.
    struct DuplicateSet: Identifiable, Equatable, Sendable {
        let id: String
        /// File name of the copy that is kept (the prototype's set title).
        let title: String
        let items: [ScanItem]
        /// The recommended keep copy's path; `nil` only for an empty set.
        let keepPath: String?

        /// Every copy except the kept one — the only copies that can ever be selected.
        var extraItems: [ScanItem] { items.filter { $0.path != keepPath } }
        /// Size of the copies that would be freed (OD-b's per-set total).
        var extraBytes: Int64 { extraItems.reduce(0) { $0 + $1.size } }
        /// Size of one copy as the list head quotes it ("N copies · size each").
        var copySize: Int64 { items.first?.size ?? 0 }
    }

    private(set) var mode: Mode = .exact
    private(set) var phase: Phase = .idle
    private(set) var groups: [DuplicateGroup] = []
    /// The review model, rebuilt whenever `groups` changes (never re-derived per render).
    private(set) var sets: [DuplicateSet] = []
    private(set) var selectedPaths: Set<String> = []
    /// Files that couldn't be hashed/decoded (permission denied, deleted mid-scan, undecodable
    /// image) — surfaced so results never look more exhaustive than they are.
    private(set) var skippedCount = 0
    /// Per-copy failures of the last clean, surfaced on Done (S5) — never dropped.
    private(set) var lastFailedItems: [CleanResult.FailedItem] = []
    /// How many sets lost at least one copy in the last clean (Done's "Kept" stat: each such
    /// set still has its kept copy). Zero until a clean finishes.
    private(set) var lastKeptCount = 0
    /// Real per-copy cleaning progress (S5); `nil` outside `cleaning`.
    private(set) var cleaningProgress: CleaningProgress?

    /// Review navigation — per-row UI state, deliberately not part of `Phase`.
    var currentSetID: String?
    var focusedItemPath: String?

    let rootPath: String
    let progressTracker = ScanProgressTracker()
    private var scanTask: Task<Void, Never>?
    private let cleaner: any Cleaner
    private let progressiveCleaner = ProgressiveCleaner()
    /// Paths that are some set's keep copy. Rebuilt with `sets`; the lock reads it.
    private var keepPaths: Set<String> = []

    init(rootPath: String = NSHomeDirectory(), cleaner: any Cleaner = DefaultCleaner()) {
        self.rootPath = rootPath
        self.cleaner = cleaner
    }

    // MARK: - Lifecycle mapping

    /// The pure mapping the shared frame renders from. `results` with no sets and no failure
    /// is `empty` (F3: empty means the scan finished and found nothing — a failed scan is
    /// `.failed`, so it can never look like "no duplicates").
    var lifecycle: LifecycleState {
        switch phase {
        case .idle: .start
        case .scanning: .scanning
        case .results: sets.isEmpty ? .empty : .results
        case .review: .review
        case .cleaning: .cleaning
        case .done: .done
        case .failed: .error
        }
    }

    /// True while copies are moving — the re-entrancy guard's input.
    var isCleaning: Bool {
        if case .cleaning = phase { return true }
        return false
    }

    /// The engine's reason for a failed scan, `nil` in every other phase. Kept so callers
    /// (and `ModuleStoreTests`) can ask "did the scan fail" without a pattern match.
    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Hashing has started once the engine reports progress: the exact-mode listing pass
    /// reports none, so a non-nil progress means a total is known. Nothing is fabricated for
    /// the listing pass (spec: "bar + % only once hashing starts").
    var isHashing: Bool {
        progressTracker.progress?.totalItems != nil
    }

    // MARK: - Derived state (real values only)

    /// The one rule for "can this copy be selected": it is not a set's keep copy.
    func isKept(path: String) -> Bool {
        keepPaths.contains(path)
    }

    var allItems: [ScanItem] { groups.flatMap(\.items) }

    var selectedItems: [ScanItem] {
        allItems.filter { selectedPaths.contains($0.path) && !keepPaths.contains($0.path) }
    }

    var totalSelectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    /// Number of files across every set (the "N files in total" caption).
    var totalFileCount: Int {
        sets.reduce(0) { $0 + $1.items.count }
    }

    var currentSet: DuplicateSet? {
        if let currentSetID, let found = sets.first(where: { $0.id == currentSetID }) {
            return found
        }
        return sets.first
    }

    /// The copy whose detail the review frame shows: the focused row, or the first row of the
    /// current set, or nothing.
    var focusedItem: ScanItem? {
        let items = currentSet?.items ?? []
        if let focusedItemPath, let found = items.first(where: { $0.path == focusedItemPath }) {
            return found
        }
        return items.first
    }

    /// Selected copies in one set — never counts the keep copy.
    func selectedCount(in set: DuplicateSet) -> Int {
        set.extraItems.count { selectedPaths.contains($0.path) }
    }

    /// Pure grouping (the testable core): one set per engine group, in engine order. A group
    /// with fewer than two copies is not a duplicate set and is dropped.
    static func sets(from groups: [DuplicateGroup]) -> [DuplicateSet] {
        groups.compactMap { group in
            guard group.items.count >= 2 else { return nil }
            let keep = group.recommendedKeepPath
            let title = keep.map { ($0 as NSString).lastPathComponent }
                ?? (group.items.first.map { ($0.path as NSString).lastPathComponent } ?? group.id)
            return DuplicateSet(id: group.id, title: title, items: group.items, keepPath: keep)
        }
    }

    /// OD-a: the paths a finished scan pre-selects. Exact mode: every non-keep copy (today's
    /// rule). Similar mode: nothing.
    static func preSelection(for sets: [DuplicateSet], mode: Mode) -> Set<String> {
        switch mode {
        case .exact:
            Set(sets.flatMap(\.extraItems).map(\.path))
        case .similarImages:
            []
        }
    }

    /// The text of the error state's body (OD-18: instructions in text, no button — Full Disk
    /// Access has no documented URL). The engine's own reason comes first.
    static func failureText(reason: String) -> String {
        "\(reason) If SOS Mac can't read your Home folder, check that it has Full Disk Access in System Settings › Privacy & Security."
    }

    private func install(groups newGroups: [DuplicateGroup]) {
        groups = newGroups
        sets = Self.sets(from: newGroups)
        keepPaths = Set(sets.compactMap(\.keepPath))
    }

    // MARK: - Mode

    /// Switching the match type discards the current results: the two passes are separate
    /// scans, and results of one must never stand in for the other. Refused while files are
    /// moving or a scan runs (the toolbar segment is disabled then, too).
    func setMode(_ newMode: Mode) {
        guard newMode != mode, phase != .scanning, !isCleaning else { return }
        mode = newMode
        resetToStart()
    }

    private func resetToStart() {
        scanTask?.cancel()
        scanTask = nil
        install(groups: [])
        selectedPaths = []
        skippedCount = 0
        lastFailedItems = []
        lastKeptCount = 0
        cleaningProgress = nil
        currentSetID = nil
        focusedItemPath = nil
        progressTracker.reset()
        phase = .idle
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
    /// which would otherwise look like the outcome of this one.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        guard phase == .scanning else { return }
        resetToStart()
    }

    private func performScan() async {
        phase = .scanning
        lastFailedItems = []
        lastKeptCount = 0
        let generation = progressTracker.start()

        let finder = DuplicateFinder(rootPath: rootPath)
        let result: DuplicateScanResult
        do {
            switch mode {
            case .exact:
                result = try await finder.findExactDuplicateGroups(onProgress: { [weak self] progress in
                    Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
                })
            case .similarImages:
                result = try await finder.findSimilarImageGroups(onProgress: { [weak self] progress in
                    Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
                })
            }
        } catch {
            guard !Task.isCancelled else { return }
            // §6.3: the truthful error state — the engine's own reason.
            phase = .failed(message: error.localizedDescription)
            return
        }

        guard !Task.isCancelled else { return }
        applyResults(groups: result.groups, skippedCount: result.skippedCount)
    }

    /// The completed-scan state over a result set, with the mode's pre-selection (OD-a).
    private func applyResults(groups newGroups: [DuplicateGroup], skippedCount skipped: Int) {
        install(groups: newGroups)
        skippedCount = skipped
        selectedPaths = Self.preSelection(for: sets, mode: mode)
        currentSetID = nil
        focusedItemPath = nil
        lastFailedItems = []
        cleaningProgress = nil
        phase = .results
    }

    // MARK: - Review

    func enterReview() {
        guard phase == .results, !sets.isEmpty else { return }
        phase = .review
        if currentSetID == nil || !sets.contains(where: { $0.id == currentSetID }) {
            currentSetID = sets.first?.id
            focusedItemPath = nil
        }
    }

    func backToResults() {
        guard phase == .review else { return }
        phase = .results
    }

    func selectSet(_ id: String) {
        currentSetID = id
        focusedItemPath = nil
    }

    func focusItem(path: String) {
        focusedItemPath = path
    }

    /// The keep copy is never toggled — by click, by keyboard, or by any caller.
    func toggleSelection(path: String) {
        guard !keepPaths.contains(path) else { return }
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// Select All in the current set — every extra copy, never the kept one (§4.6). In Similar
    /// mode this is an explicit bulk action by the user; it is not the pre-selection (OD-a).
    func selectAllInCurrentSet() {
        guard let set = currentSet else { return }
        selectedPaths.formUnion(set.extraItems.map(\.path))
    }

    func deselectAllInCurrentSet() {
        guard let set = currentSet else { return }
        for item in set.items {
            selectedPaths.remove(item.path)
        }
    }

    /// The confirmation model for both removal entry points (S1; CF-3: the count and size are
    /// the numbers the review bar shows, computed here once). "Review Items…" is offered only
    /// when the sheet is opened from `results` (§4.8).
    func trashConfirmation(isFromResults: Bool) -> ConfirmSheet.Model {
        let selected = selectedItems
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
            count: selected.count,
            sizeText: ConfirmItemList.sizeText(for: selected.reduce(0) { $0 + $1.size }),
            isFromResults: isFromResults,
            items: items,
            hue: Theme.Hue.duplicates,
            confirm: { [weak self] _ in self?.beginClean() },
            cancel: { },
            reviewItems: reviewItems)
    }

    /// Starts the confirmed clean from the sheet's synchronous callback; the sheet is already
    /// dismissed when this runs. This is all the confirm closure does.
    private func beginClean() {
        Task { [weak self] in
            await self?.clean()
        }
    }

    // MARK: - Clean

    /// Moves the confirmed selection. Re-entrant calls are refused while a clean is in flight
    /// (the disabled "Moving" CTA is the same guard's UI half).
    @discardableResult
    func clean() async -> Bool {
        guard !isCleaning else { return false }
        // Defence in depth: `selectedItems` already excludes every keep copy, so a stray
        // path in `selectedPaths` can never reach the Cleaner.
        let toClean = selectedItems
        guard !toClean.isEmpty else { return false }

        phase = .cleaning(selectedCount: toClean.count)
        cleaningProgress = CleaningProgress(attemptedCount: 0, totalCount: toClean.count, currentPath: nil)
        lastFailedItems = []

        let result = await progressiveCleaner.clean(toClean, using: cleaner) { [weak self] index, item in
            self?.cleaningProgress = CleaningProgress(attemptedCount: index + 1,
                                                       totalCount: toClean.count,
                                                       currentPath: item.path)
        }

        let succeededPaths = Set(result.succeeded.map(\.path))
        let touchedSets = Set(sets.filter { set in set.items.contains { succeededPaths.contains($0.path) } }.map(\.id))
        // Groups recompute from what is left: a set down to one copy is no longer a duplicate
        // set at all. The keep copy is recomputed too (it can only be the same copy: it was
        // never moved, and it is still the newest of what remains).
        let remainingGroups: [DuplicateGroup] = groups.compactMap { group in
            let remaining = group.items.filter { !succeededPaths.contains($0.path) }
            return remaining.count >= 2 ? DuplicateGroup(id: group.id, items: remaining) : nil
        }
        install(groups: remainingGroups)
        selectedPaths.subtract(succeededPaths)
        selectedPaths.formIntersection(Set(allItems.map(\.path)).subtracting(keepPaths))
        if let currentSetID, !sets.contains(where: { $0.id == currentSetID }) {
            self.currentSetID = nil
            focusedItemPath = nil
        }
        cleaningProgress = nil
        lastFailedItems = result.failed
        lastKeptCount = touchedSets.count
        phase = .done(movedBytes: result.succeeded.reduce(0) { $0 + $1.size },
                      movedCount: result.succeeded.count,
                      failedCount: result.failed.count)
        return true
    }

    // MARK: - Fixtures (Debug builds only)

#if DEBUG
    /// Loads one of the eight lifecycle states, for the current `mode`, from the fictional
    /// sample data (`UITestFixtures.duplicateSets` / `similarSets`). Called from the screen's
    /// `.task` when `SOSMAC_UITEST_FIXTURES=1` names this screen and state; never reads the
    /// real file system.
    func loadFixture(_ state: LifecycleState, mode fixtureMode: Mode = .exact) {
        mode = fixtureMode
        switch state {
        case .start:
            applyIdleFixture()

        case .scanning:
            applyIdleFixture()
            phase = .scanning
            // Hashing under way: 840 of the 1,284 candidates (a fictional, fixed sample).
            let generation = progressTracker.start()
            progressTracker.record(
                ScanProgress(itemsProcessed: 840, totalItems: 1_284,
                             currentPath: "\(UITestFixtures.home)/Documents/Projects/Brand/design-assets-v4.zip"),
                generation: generation)

        case .results:
            applyFixtureResults()

        case .empty:
            // F3: `empty` is `results` with no sets — the Phase has no empty case.
            applyIdleFixture()
            phase = .results

        case .review:
            applyFixtureResults()
            enterReview()
            if let first = currentSet?.items.first?.path {
                focusItem(path: first)
            }

        case .cleaning:
            applyFixtureResults()
            applyFixtureSelectionIfEmpty()
            let count = selectedItems.count
            phase = .cleaning(selectedCount: count)
            cleaningProgress = CleaningProgress(
                attemptedCount: min(2, count),
                totalCount: count,
                currentPath: selectedItems.first?.path)

        case .done:
            // As if the selection had just been moved: the moved copies are gone, nothing failed.
            applyFixtureResults()
            applyFixtureSelectionIfEmpty()
            let pick = selectedItems
            let movedPaths = Set(pick.map(\.path))
            let touched = sets.filter { set in set.items.contains { movedPaths.contains($0.path) } }.count
            install(groups: groups.compactMap { group in
                let remaining = group.items.filter { !movedPaths.contains($0.path) }
                return remaining.count >= 2 ? DuplicateGroup(id: group.id, items: remaining) : nil
            })
            selectedPaths = []
            lastKeptCount = touched
            phase = .done(movedBytes: pick.reduce(0) { $0 + $1.size },
                          movedCount: pick.count,
                          failedCount: 0)

        case .error:
            applyIdleFixture()
            phase = .failed(message: "The file “Documents” couldn’t be opened because you don’t have permission to view it.")
        }
    }

    /// The launch-hook half of the fixture convention. The hooks carry no "mode" field, so a
    /// Similar-mode state is spelled with a `similar` prefix (`similarresults`) — which still
    /// fits `Scripts/ui-snapshots.sh`'s `screen=state` pattern.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .duplicateFinder, let raw = hooks.state else { return }
        let prefix = "similar"
        let isSimilar = raw.hasPrefix(prefix)
        let stateName = isSimilar ? String(raw.dropFirst(prefix.count)) : raw
        guard let state = LifecycleState(rawValue: stateName) else { return }
        loadFixture(state, mode: isSimilar ? .similarImages : .exact)
    }

    private func applyIdleFixture() {
        resetToStart()
    }

    private func applyFixtureResults() {
        let fixtureSets = mode == .exact ? UITestFixtures.duplicateSets : UITestFixtures.similarSets
        applyResults(groups: fixtureSets.map { DuplicateGroup(id: $0.id, items: $0.items) },
                     skippedCount: 14)
    }

    /// Cleaning and Done need a selection to act on. Exact mode already has one; Similar mode
    /// pre-selects nothing (OD-a), so the fixture picks the first set's other images, as if
    /// the user had chosen them.
    private func applyFixtureSelectionIfEmpty() {
        guard selectedPaths.isEmpty, let first = sets.first else { return }
        selectedPaths = Set(first.extraItems.map(\.path))
    }

    /// Test-only: the completed-scan state over arbitrary groups. The paths need not exist —
    /// tests use unique temp paths so a clean over them exercises the real `Cleaner` without
    /// depending on anything in the user's home directory.
    func loadFixtureResults(_ newGroups: [DuplicateGroup], mode fixtureMode: Mode = .exact, skippedCount skipped: Int = 0) {
        mode = fixtureMode
        applyResults(groups: newGroups, skippedCount: skipped)
    }
#endif
}

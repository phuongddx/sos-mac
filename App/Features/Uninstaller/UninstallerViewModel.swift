import AppKit
import Foundation
import Observation
import CleanCore

/// Uninstaller on the shared lifecycle frame (plan PR 9), built exactly like the Junk &
/// Cache reference screen: a state table, one `Phase` enum, a pure `lifecycle` mapping,
/// Debug-only fixture states.
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `browsing` | "Pick an app to see what it left behind" · app rows (**Inspect**) · **Measure All** |
/// | `scanning` | `inspectingAll(currentBundleID:)` | "Inspecting «App»…" · "k of N apps" · rows fill in their size · **Stop** |
/// | `results` | `measured` | rows with sizes and **Review** · **Measure Again** |
/// | `review` | `reviewing(bundleID:)` | Two columns: the app panel + its items · "N items · at least «size» selected" · **Move to Trash…** |
/// | `cleaning` | `cleaning(appName:selectedCount:)` | "Moving n of N items to the Trash…" + the current path |
/// | `done` | `removed(appName:atLeastBytes:itemCount:failedCount:)` | stats · a banner per item that stayed · Open Trash · Back to Apps |
/// | `empty` | `browsing` with no apps | "No apps found" · Check Again |
/// | `error` | `browsing` / `measured` with an `inspectError` row | the row's "Couldn't inspect «App»" banner · Try Again |
///
/// **D1 (engine limit, not hidden):** `BundleAssociatedFilesFinder` reports the size of a
/// directory *entry*, not of what is inside it. So an associated folder never shows a
/// size ("Folder"), and every total that includes one reads "At least …". The app bundle
/// itself is walked by the engine and carries a real size.
///
/// Safety: every removal goes through `ProgressiveCleaner` → the one trash-routed
/// `Cleaner.clean(_:)` extension method; the confirmation (Cancel is the default) always
/// comes first, and a running app blocks it (OD-9).
@MainActor
@Observable
final class UninstallerViewModel {

    // MARK: - Types

    struct AppRow: Identifiable, Equatable {
        let app: InstalledApp
        /// Real bytes only: the app bundle plus associated *files*. Associated folders are
        /// not measured (D1), so they never add to this figure.
        var inspectedSize: Int64?
        /// How many associated folders the inspect found but could not measure (D1). A size
        /// with `> 0` folders reads "At least …".
        var unmeasuredFolderCount = 0
        /// Why the last inspect of this row failed — shown beside the row (N4), cleared by
        /// the next attempt. Busy flags are never part of the row.
        var inspectError: String?
        var id: String { app.id }

        init(app: InstalledApp,
             inspectedSize: Int64? = nil,
             unmeasuredFolderCount: Int = 0,
             inspectError: String? = nil) {
            self.app = app
            self.inspectedSize = inspectedSize
            self.unmeasuredFolderCount = unmeasuredFolderCount
            self.inspectError = inspectError
        }
    }

    /// The state machine contract the shared frame maps from (spec §5.7, normative).
    enum Phase: Equatable {
        case browsing
        case inspectingAll(currentBundleID: String?)
        case measured
        case reviewing(bundleID: String)
        case cleaning(appName: String, selectedCount: Int)
        case removed(appName: String, atLeastBytes: Int64, itemCount: Int, failedCount: Int)
    }

    /// A snapshot of the per-item cleaning loop (spec §6.5).
    struct CleaningProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
    }

    /// The scan seam: production runs `AppUninstaller.scan()`; tests inject their own.
    typealias InspectFunction = @Sendable (InstalledApp) async throws -> [ScanItem]

    // MARK: - State

    private(set) var phase: Phase = .browsing
    private(set) var apps: [AppRow] = []
    /// What the inspect of the reviewed app found — the app bundle first, then its
    /// associated files and folders.
    private(set) var associatedItems: [ScanItem] = []
    private(set) var selectedPaths: Set<String> = []
    /// Per-item failures of the last uninstall, surfaced on Done (F4) — never dropped.
    private(set) var lastFailedItems: [CleanResult.FailedItem] = []
    /// Real per-item cleaning progress (§6.5); `nil` outside `cleaning`.
    private(set) var cleaningProgress: CleaningProgress?
    /// Non-nil while one row's own inspect is in flight — a busy flag, so it stays out of
    /// `Phase`. A second inspect is refused while it is set.
    private(set) var inspectingBundleID: String?
    /// OD-9: the reviewed app was found running at the last check. While true the review
    /// shows "Quit «App» first" and the Move to Trash confirmation is not offered.
    private(set) var isReviewedAppRunning = false
    /// Whether the app bundle itself was among the items the last uninstall moved.
    private(set) var lastRemovalIncludedApp = false
    /// PR 3 (spec §6.6): the store keeps the rows; `loadApps` is first-visit-only so
    /// re-opening the screen never throws away inspected sizes or selection.
    private(set) var hasLoadedApps = false
    /// OD-13: the toolbar's local name filter.
    var filterText = ""

    let progressTracker = ScanProgressTracker()

    private let enumerator: InstalledAppsEnumerator
    private let inspectApp: InspectFunction
    private let isRunning: @MainActor (String) -> Bool
    private let iconLoader: @MainActor (String) -> NSImage?
    private let cleaner: any Cleaner
    private let progressiveCleaner = ProgressiveCleaner()
    private var inspectAllTask: Task<Void, Never>?
    /// Bumped by every start/cancel so a superseded Inspect-All can't change the phase out
    /// from under the run that replaced it.
    private var inspectAllGeneration = 0
    /// Whether a full Measure All has finished since the rows were loaded — decides which
    /// list phase "Back" returns to.
    private var hasMeasuredAll = false
    /// OD-12: one icon load per app (60+ apps would otherwise hit the disk every render).
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    init(enumerator: InstalledAppsEnumerator = InstalledAppsEnumerator(),
         inspect: @escaping InspectFunction = UninstallerViewModel.liveInspect,
         isRunning: @escaping @MainActor (String) -> Bool = UninstallerViewModel.liveIsRunning,
         iconLoader: @escaping @MainActor (String) -> NSImage? = UninstallerViewModel.liveIcon,
         cleaner: any Cleaner = DefaultCleaner()) {
        self.enumerator = enumerator
        self.inspectApp = inspect
        self.isRunning = isRunning
        self.iconLoader = iconLoader
        self.cleaner = cleaner
    }

    // MARK: - Live seams

    static let liveInspect: InspectFunction = { app in
        try await AppUninstaller(appBundlePath: app.bundlePath,
                                 bundleIdentifier: app.bundleIdentifier).scan()
    }

    /// OD-9: the documented API for "is this app running".
    static let liveIsRunning: @MainActor (String) -> Bool = { bundleID in
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// OD-12: the app's own icon, or `nil` when the bundle is not on disk (the letter tile
    /// then stands in — also what the fictional fixture apps get).
    static let liveIcon: @MainActor (String) -> NSImage? = { path in
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    // MARK: - Lifecycle mapping

    /// The pure mapping the shared frame renders from. `browsing` with no apps (after the
    /// first load) is `empty` — "no apps" and "scan failed" never look alike: a failed row
    /// is `error`.
    var lifecycle: LifecycleState {
        switch phase {
        case .browsing:
            if hasLoadedApps && apps.isEmpty { return .empty }
            return hasInspectError ? .error : .start
        case .inspectingAll: return .scanning
        case .measured: return hasInspectError ? .error : .results
        case .reviewing: return .review
        case .cleaning: return .cleaning
        case .removed: return .done
        }
    }

    var hasInspectError: Bool { apps.contains { $0.inspectError != nil } }
    var failedRows: [AppRow] { apps.filter { $0.inspectError != nil } }

    /// `ModuleStore.isScanning(.uninstaller)` reads this (the sidebar busy dot).
    var isInspectingAll: Bool {
        if case .inspectingAll = phase { return true }
        return false
    }

    var isCleaning: Bool {
        if case .cleaning = phase { return true }
        return false
    }

    // MARK: - Rows

    /// The rows the list shows after the name filter (OD-13): a local, case- and
    /// diacritic-insensitive match on the app name.
    var visibleApps: [AppRow] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.app.name.localizedStandardContains(query) }
    }

    func row(forBundleID bundleID: String) -> AppRow? {
        apps.first { $0.app.bundleIdentifier == bundleID }
    }

    /// The app the review shows.
    var reviewedApp: InstalledApp? {
        guard case .reviewing(let bundleID) = phase else { return nil }
        return row(forBundleID: bundleID)?.app
    }

    /// The bundle currently being measured by Inspect All (its row shows the spinner).
    var currentlyMeasuringBundleID: String? {
        if case .inspectingAll(let current) = phase { return current }
        return nil
    }

    /// Apps with a size after Inspect All / single inspects.
    var measuredAppCount: Int { apps.count { $0.inspectedSize != nil } }

    /// OD-12.
    func icon(for app: InstalledApp) -> NSImage? {
        if let cached = iconCache[app.bundlePath] { return cached }
        guard let loaded = iconLoader(app.bundlePath) else { return nil }
        iconCache[app.bundlePath] = loaded
        return loaded
    }

    // MARK: - Load

    /// First-visit-only: `.task` re-fires whenever the view reappears, and rebuilding the
    /// rows would throw away every size already measured.
    func loadApps() {
        guard !hasLoadedApps, !isInspectingAll else { return }
        enumerateApps()
    }

    /// Empty → "Check Again" (and Measure Again's reload path): re-enumerates, dropping
    /// measured sizes — they described the old list.
    func checkAgain() {
        guard phase == .browsing || phase == .measured, inspectingBundleID == nil else { return }
        enumerateApps()
        phase = .browsing
    }

    private func enumerateApps() {
        hasLoadedApps = true
        hasMeasuredAll = false
        apps = enumerator.enumerate()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppRow(app: $0) }
    }

    // MARK: - Inspect one app

    /// Inspects one app and opens its review. Refused (returns `false`) while another
    /// inspect, a Measure All, or an uninstall is running, or outside the app list.
    @discardableResult
    func inspect(_ row: AppRow) async -> Bool {
        guard inspectingBundleID == nil, phase == .browsing || phase == .measured else { return false }
        let bundleID = row.app.bundleIdentifier
        guard let index = apps.firstIndex(where: { $0.app.bundleIdentifier == bundleID }) else { return false }
        apps[index].inspectError = nil
        inspectingBundleID = bundleID
        defer { inspectingBundleID = nil }

        do {
            let items = try await inspectApp(row.app)
            guard let writeIndex = apps.firstIndex(where: { $0.app.bundleIdentifier == bundleID }) else { return false }
            record(items, into: writeIndex, bundlePath: row.app.bundlePath)
            associatedItems = items
            // Pre-selection is unchanged: everything an inspect finds is selected.
            selectedPaths = Set(items.map(\.path))
            lastFailedItems = []
            refreshRunningState(for: row.app)
            phase = .reviewing(bundleID: bundleID)
            return true
        } catch {
            // N4: the failure stays beside its row instead of vanishing.
            if let writeIndex = apps.firstIndex(where: { $0.app.bundleIdentifier == bundleID }) {
                apps[writeIndex].inspectError = error.localizedDescription
            }
            return false
        }
    }

    /// Retries every row whose inspect failed ("Try Again" on the error state): the first
    /// success opens its review, exactly as a fresh Inspect would.
    func retryFailedInspects() async {
        for failed in failedRows {
            guard phase == .browsing || phase == .measured else { return }
            if await inspect(failed) { return }
        }
    }

    /// "Show Apps" on the error state: clears the failure notes so the list shows again.
    func dismissInspectErrors() {
        for index in apps.indices { apps[index].inspectError = nil }
    }

    private func record(_ items: [ScanItem], into index: Int, bundlePath: String) {
        let measured = items.filter { !Self.isUnmeasuredFolder($0, bundlePath: bundlePath) }
        apps[index].inspectedSize = measured.reduce(0) { $0 + $1.size }
        apps[index].unmeasuredFolderCount = items.count - measured.count
    }

    // MARK: - Measure All (Inspect All)

    /// Measures every app in order, filling each row's size as it finishes. One app
    /// failing records its own `inspectError` and the run goes on.
    @discardableResult
    func startInspectAll() -> Bool {
        guard inspectingBundleID == nil, phase == .browsing || phase == .measured, !apps.isEmpty else { return false }
        inspectAllTask?.cancel()
        inspectAllGeneration += 1
        let generation = inspectAllGeneration
        for index in apps.indices {
            apps[index].inspectedSize = nil
            apps[index].unmeasuredFolderCount = 0
            apps[index].inspectError = nil
        }
        phase = .inspectingAll(currentBundleID: nil)
        inspectAllTask = Task { [weak self] in
            await self?.inspectAll(generation: generation)
        }
        return true
    }

    /// Stop: back to the list. Unlike a Junk scan, rows already measured keep their size —
    /// each one is a finished, real result (deviation from F2, reported with PR 9).
    func cancelInspectAll() {
        inspectAllTask?.cancel()
        inspectAllTask = nil
        inspectAllGeneration += 1
        progressTracker.reset()
        guard isInspectingAll else { return }
        phase = .browsing
    }

    private func inspectAll(generation: Int) async {
        let progressGeneration = progressTracker.start()
        // Snapshot the identifiers up front so the denominator is stable; every write
        // re-resolves its row by bundle identifier.
        let targets = apps.map(\.app)

        for (index, app) in targets.enumerated() {
            guard !Task.isCancelled, generation == inspectAllGeneration else { return }
            phase = .inspectingAll(currentBundleID: app.bundleIdentifier)
            progressTracker.record(
                ScanProgress(itemsProcessed: index, totalItems: targets.count, currentPath: app.name),
                generation: progressGeneration)

            let outcome: Result<[ScanItem], Error>
            do {
                outcome = .success(try await inspectApp(app))
            } catch {
                outcome = .failure(error)
            }
            guard !Task.isCancelled, generation == inspectAllGeneration else { return }

            if let writeIndex = apps.firstIndex(where: { $0.app.bundleIdentifier == app.bundleIdentifier }) {
                switch outcome {
                case .success(let items):
                    record(items, into: writeIndex, bundlePath: app.bundlePath)
                case .failure(let error):
                    apps[writeIndex].inspectError = error.localizedDescription
                }
            }
        }
        progressTracker.record(
            ScanProgress(itemsProcessed: targets.count, totalItems: targets.count, currentPath: nil),
            generation: progressGeneration)
        hasMeasuredAll = true
        phase = .measured
    }

    // MARK: - D1 helpers (pure)

    /// D1: an associated *folder* — the engine reports its directory entry, not its
    /// contents, so no size may be shown for it. The app bundle is also a directory, but
    /// the engine walks it, so its size is real.
    static func isUnmeasuredFolder(_ item: ScanItem, bundlePath: String) -> Bool {
        item.kind == .directory && item.path != bundlePath
    }

    func isUnmeasuredFolder(_ item: ScanItem) -> Bool {
        guard let reviewedApp else { return item.kind == .directory }
        return Self.isUnmeasuredFolder(item, bundlePath: reviewedApp.bundlePath)
    }

    func isAppBundle(_ item: ScanItem) -> Bool {
        item.path == reviewedApp?.bundlePath
    }

    /// "N folders not measured yet." (spec §5.7) — over everything the inspect found.
    var unmeasuredFolderCount: Int {
        associatedItems.count { isUnmeasuredFolder($0) }
    }

    // MARK: - Review selection

    var selectedItems: [ScanItem] {
        associatedItems.filter { selectedPaths.contains($0.path) }
    }

    /// Real bytes of the selection — folders contribute nothing (D1).
    var selectedMeasuredBytes: Int64 {
        selectedItems.filter { !isUnmeasuredFolder($0) }.reduce(0) { $0 + $1.size }
    }

    /// "At least" appears only when an associated folder is selected.
    var selectionIncludesUnmeasuredFolder: Bool {
        selectedItems.contains { isUnmeasuredFolder($0) }
    }

    /// The review bar's, the dock's and the confirmation's size text (CF-3): the measured
    /// bytes, prefixed "at least" when a folder is in the selection.
    var selectedSizeText: String {
        guard selectionIncludesUnmeasuredFolder else {
            return ConfirmItemList.sizeText(for: selectedMeasuredBytes)
        }
        guard selectedMeasuredBytes > 0 else { return "size not measured" }
        return "at least \(ConfirmItemList.sizeText(for: selectedMeasuredBytes))"
    }

    func toggleSelection(path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    func selectAll() {
        selectedPaths = Set(associatedItems.map(\.path))
    }

    func deselectAll() {
        selectedPaths = []
    }

    // MARK: - Running app (OD-9)

    /// Re-checks whether the reviewed app is running. Called when the review opens and
    /// again each time Move to Trash… is chosen, so a stale answer never decides.
    @discardableResult
    func refreshRunningState() -> Bool {
        guard let app = reviewedApp else {
            isReviewedAppRunning = false
            return false
        }
        refreshRunningState(for: app)
        return isReviewedAppRunning
    }

    private func refreshRunningState(for app: InstalledApp) {
        isReviewedAppRunning = isRunning(app.bundleIdentifier)
    }

    // MARK: - Navigation

    /// Back from the review (or Done) to the list the user came from.
    func backToApps() {
        switch phase {
        case .reviewing, .removed:
            phase = hasMeasuredAll ? .measured : .browsing
            associatedItems = []
            selectedPaths = []
            lastFailedItems = []
            isReviewedAppRunning = false
        case .browsing, .inspectingAll, .measured, .cleaning:
            break
        }
    }

    // MARK: - Uninstall confirmation

    /// The uninstall confirmation, or `nil` when the app is running (OD-9: "Quit «App»
    /// first" — the review shows why) or nothing is selected. Cancel is the sheet's default
    /// button (CF-1). The title's count is the *related* items when the app itself is in
    /// the selection ("Move «App» and N related items"), exactly as the prototype words it.
    func uninstallConfirmation() -> ConfirmSheet.Model? {
        guard let app = reviewedApp else { return nil }
        refreshRunningState(for: app)
        guard !isReviewedAppRunning else { return nil }
        let selected = selectedItems
        guard !selected.isEmpty else { return nil }

        let includesApp = selected.contains { isAppBundle($0) }
        let items = selected.map { item in
            ConfirmItem(id: item.path,
                        name: Self.confirmationName(for: item, isFolder: isUnmeasuredFolder(item)),
                        path: item.path,
                        size: item.size)
        }
        return ConfirmSheet.Model(
            variant: .uninstall,
            count: includesApp ? selected.count - 1 : selected.count,
            sizeText: selectedSizeText,
            appName: includesApp ? app.name : nil,
            appStoreNote: includesApp && app.isAppStoreDistributed,
            items: items,
            hue: Theme.Hue.uninstaller,
            confirm: { [weak self] _ in self?.beginUninstall() },
            cancel: { })
    }

    /// A folder is named as one in the confirmation list, whose rows always carry a size
    /// column (the engine's entry size — D1 — so the name says what it is).
    private static func confirmationName(for item: ScanItem, isFolder: Bool) -> String {
        let name = (item.path as NSString).lastPathComponent
        return isFolder ? "\(name) (folder)" : name
    }

    /// Starts the confirmed uninstall from the sheet's synchronous callback.
    private func beginUninstall() {
        Task { [weak self] in
            await self?.uninstall()
        }
    }

    // MARK: - Uninstall

    /// Moves the confirmed selection to the Trash, one item at a time (real progress,
    /// §6.5), through `ProgressiveCleaner` → `Cleaner.clean(_:)`. Re-entrant calls are
    /// refused. Items that fail stay listed on Done (F4) — never folded into the figure.
    @discardableResult
    func uninstall() async -> Bool {
        guard case .reviewing(let bundleID) = phase, let app = reviewedApp else { return false }
        let toRemove = selectedItems
        guard !toRemove.isEmpty else { return false }

        phase = .cleaning(appName: app.name, selectedCount: toRemove.count)
        cleaningProgress = CleaningProgress(attemptedCount: 0, totalCount: toRemove.count, currentPath: nil)
        lastFailedItems = []

        let result = await progressiveCleaner.clean(toRemove, using: cleaner) { [weak self] index, item in
            self?.cleaningProgress = CleaningProgress(attemptedCount: index + 1,
                                                       totalCount: toRemove.count,
                                                       currentPath: item.path)
        }

        let movedPaths = Set(result.succeeded.map(\.path))
        let removedApp = movedPaths.contains(app.bundlePath)
        lastRemovalIncludedApp = removedApp
        if removedApp {
            apps.removeAll { $0.app.bundleIdentifier == bundleID }
        }
        associatedItems.removeAll { movedPaths.contains($0.path) }
        selectedPaths.subtract(movedPaths)
        lastFailedItems = result.failed
        cleaningProgress = nil
        // "At least": only the measured bytes are counted — a moved folder adds none (D1).
        let measuredMoved = result.succeeded
            .filter { !Self.isUnmeasuredFolder($0, bundlePath: app.bundlePath) }
            .reduce(Int64(0)) { $0 + $1.size }
        phase = .removed(appName: app.name,
                         atLeastBytes: measuredMoved,
                         itemCount: result.succeeded.count,
                         failedCount: result.failed.count)
        return true
    }

    // MARK: - Fixtures (Debug builds only)

#if DEBUG
    /// Loads one of the eight lifecycle states from the fictional sample data
    /// (`UITestFixtures.apps`). Called from the screen's `.task` when
    /// `SOSMAC_UITEST_FIXTURES=1` names this screen and state; never reads the real
    /// file system or the real app list.
    func loadFixture(_ state: LifecycleState) {
        switch state {
        case .start:
            applyAppsFixture(measured: false)
        case .scanning:
            applyAppsFixture(measured: false)
            // Three of ten apps done; the fourth is being measured.
            for index in 0..<3 { applyMeasuredFixture(at: index) }
            let current = apps[3].app.bundleIdentifier
            phase = .inspectingAll(currentBundleID: current)
            let generation = progressTracker.start()
            progressTracker.record(ScanProgress(itemsProcessed: 3, totalItems: apps.count, currentPath: apps[3].app.name),
                                   generation: generation)
        case .results:
            applyAppsFixture(measured: true)
        case .review:
            applyReviewFixture()
        case .cleaning:
            applyReviewFixture()
            let count = selectedItems.count
            phase = .cleaning(appName: reviewedAppNameFixture, selectedCount: count)
            cleaningProgress = CleaningProgress(attemptedCount: 2, totalCount: count,
                                                currentPath: associatedItems.dropFirst(2).first?.path)
        case .done:
            applyAppsFixture(measured: true)
            let app = apps[0]
            let items = UITestFixtures.uninstallerItems(for: app.app)
            let measured = items.filter { !Self.isUnmeasuredFolder($0, bundlePath: app.app.bundlePath) }
            lastRemovalIncludedApp = true
            apps.removeFirst()
            phase = .removed(appName: app.app.name,
                             atLeastBytes: measured.reduce(0) { $0 + $1.size },
                             itemCount: items.count,
                             failedCount: 0)
        case .empty:
            apps = []
            hasLoadedApps = true
            hasMeasuredAll = false
            resetReviewState()
            phase = .browsing
        case .error:
            applyAppsFixture(measured: true)
            if let index = apps.firstIndex(where: { $0.app.bundleIdentifier == "com.example.containers" }) {
                apps[index].inspectedSize = nil
                apps[index].unmeasuredFolderCount = 0
                apps[index].inspectError = "Some of its files in ~/Library/Containers couldn’t be read."
            }
        }
    }

    /// The launch-hook half of the fixture convention.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .uninstaller,
              let raw = hooks.state, let state = LifecycleState(rawValue: raw) else { return }
        loadFixture(state)
    }

    /// Test-only: the app list over arbitrary apps (no real file system needed), loaded
    /// the way a first `loadApps()` would leave it.
    func loadFixtureApps(_ installed: [InstalledApp]) {
        resetReviewState()
        apps = installed
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppRow(app: $0) }
        hasLoadedApps = true
        hasMeasuredAll = false
        phase = .browsing
    }

    /// Test-only: the review state over arbitrary items (no real file system needed).
    func loadFixtureReview(app: InstalledApp, items: [ScanItem]) {
        apps = [AppRow(app: app)]
        hasLoadedApps = true
        hasMeasuredAll = false
        resetReviewState()
        associatedItems = items
        selectedPaths = Set(items.map(\.path))
        record(items, into: 0, bundlePath: app.bundlePath)
        refreshRunningState(for: app)
        phase = .reviewing(bundleID: app.bundleIdentifier)
    }

    private var reviewedAppNameFixture: String { reviewedApp?.name ?? "" }

    private func resetReviewState() {
        associatedItems = []
        selectedPaths = []
        lastFailedItems = []
        cleaningProgress = nil
        isReviewedAppRunning = false
        lastRemovalIncludedApp = false
        filterText = ""
        progressTracker.reset()
    }

    private func applyAppsFixture(measured: Bool) {
        resetReviewState()
        apps = UITestFixtures.installedApps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppRow(app: $0) }
        hasLoadedApps = true
        hasMeasuredAll = measured
        if measured {
            for index in apps.indices { applyMeasuredFixture(at: index) }
        }
        phase = measured ? .measured : .browsing
    }

    private func applyMeasuredFixture(at index: Int) {
        record(UITestFixtures.uninstallerItems(for: apps[index].app), into: index, bundlePath: apps[index].app.bundlePath)
    }

    private func applyReviewFixture() {
        applyAppsFixture(measured: true)
        guard let app = apps.first(where: { $0.app.bundleIdentifier == "com.example.ide" })?.app ?? apps.first?.app else { return }
        associatedItems = UITestFixtures.uninstallerItems(for: app)
        selectedPaths = Set(associatedItems.map(\.path))
        phase = .reviewing(bundleID: app.bundleIdentifier)
    }
#endif
}

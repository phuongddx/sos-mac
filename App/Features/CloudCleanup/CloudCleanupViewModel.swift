import Foundation
import Observation
import CleanCore

/// Real OAuth client ID/redirect URI per provider — left as placeholders
/// until real apps are registered with Google Cloud Console, Dropbox App
/// Console, and Azure AD. Every API provider fails closed with
/// `.notConfigured` (D5) rather than a doomed request; iCloud Drive needs no
/// registration at all (local scan).
struct CloudCleanupConfig {
    var googleDrive = CloudProviderConfig()
    var dropbox = CloudProviderConfig()
    var oneDrive = CloudProviderConfig()

    static let placeholder = CloudCleanupConfig()
}

/// Cloud Cleanup on the shared lifecycle frame (plan PR 11; spec §5.6). It
/// follows the pattern PR 5–9 set: one `Phase` enum **per provider** carrying
/// the whole screen state (the old per-provider Booleans are gone), a pure
/// `Phase → LifecycleState` mapping, the Debug fixture states, and every
/// removal on a confirmation-first path.
///
/// | Lifecycle | `Phase` (iCloud Drive) | What is shown |
/// |---|---|---|
/// | `start` | `idle` | "Local scan" info banner · "Find duplicates in iCloud Drive" · **Scan** |
/// | `scanning` | `scanning` | "Checking iCloud Drive…" · steps (list, compare) · "N files listed" · **Stop** |
/// | `results` | `results` | "N sets of duplicate files" · tiles Sets found / Selected · Review Items… · **Clean** · Scan Again |
/// | `review` | `review` | Sets with kept copies locked (§4.6); Select All / Deselect All |
/// | `cleaning` | `cleaning(selectedCount:)` | "Moving n of N copies to the Trash…" |
/// | `done` | `done(movedBytes:movedCount:failedCount:)` | "«bytes» moved to the Trash" · Open Trash · Scan Again |
/// | `empty` | `empty` | "No duplicates in iCloud Drive — N files listed" · Scan Again |
/// | `error` | `failed(message:)` | "iCloud Drive isn't available" + the sign-in instruction (OD-18 = 1: text, no button) · Try Again |
///
/// Google Drive / Dropbox / OneDrive start in `notConfigured` (D5: "isn't set
/// up in this build" with a disabled Connect and the path to iCloud Drive).
/// When a provider *is* configured (unit tests with a fake provider; the day
/// OAuth lands), its `results` phase renders the **server-side delete
/// surface** (spec `?screen=cloud&state=drive`): the sets list with nothing
/// selected, the "Deleting here is not Move to Trash" banner, and the danger
/// CTA that opens the **cloud** confirmation with its required
/// acknowledgement. Mapped to `LifecycleState.review` because that surface is
/// a select-and-confirm list with the shared review bar — there are no
/// tiles and no dock CTA on a server-delete screen.
///
/// Safety:
/// - iCloud Drive uses the **local** Trash confirmation and
///   `ProgressiveCleaner` → the one `Cleaner.clean(_:)` extension method, like
///   every local flow (S1; fixes S2 for iCloud).
/// - Server-side deletes go through `CloudProvider.delete(fileIDs:)` only
///   after the cloud confirmation, whose Delete button is disabled until the
///   acknowledgement is ticked (S2).
/// - The recommended **keep** copy of every group (newest by modified date,
///   never last-accessed) can never be selected — by click, Select All or the
///   pre-selection (§4.6).
/// - Pre-selection: **nothing** is pre-selected, iCloud Drive (OD-7, settled)
///   and the server-delete surface (spec: "Results are a list of sets with
///   nothing selected") alike.
/// - After every removal the groups recompute and failures are reported (S6).
@MainActor
@Observable
final class CloudCleanupViewModel {

    // MARK: - Providers and Phase (the screen's whole state)

    /// The four providers of the column (spec §5.6). iCloud Drive is the only
    /// one that works in this build (local scan); the other three are the
    /// real OAuth+REST delete paths, implemented and unit-tested with fakes.
    enum Provider: String, CaseIterable, Identifiable, Hashable {
        case iCloudDrive = "iCloud Drive"
        case googleDrive = "Google Drive"
        case dropbox = "Dropbox"
        case oneDrive = "OneDrive"

        var id: String { rawValue }

        /// The column's sub line (D5): iCloud Drive is a local scan; the API
        /// providers are not set up in this build.
        var columnSub: String {
            self == .iCloudDrive ? "Local scan" : "Not set up in this build"
        }

        /// `icloud` / `externaldrive` / `archivebox` / `cloud` — all in the
        /// spec's symbol list (Appendix B.4).
        var symbol: String {
            switch self {
            case .iCloudDrive: "icloud"
            case .googleDrive: "externaldrive"
            case .dropbox: "archivebox"
            case .oneDrive: "cloud"
            }
        }
    }

    /// The state machine contract per provider (spec §5.6, normative) —
    /// replaces the old per-provider Booleans.
    enum Phase: Equatable {
        case notConfigured
        case idle
        case scanning
        case results
        case review
        case cleaning(selectedCount: Int)
        case done(movedBytes: Int64, movedCount: Int, failedCount: Int)
        case empty
        case failed(message: String)
    }

    /// A snapshot of the per-item iCloud cleaning loop (spec §6.5):
    /// `attemptedCount` copies tried so far out of the `totalCount` the user
    /// confirmed.
    struct CleaningProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
    }

    /// One duplicate set as the review frame shows it — the same shape PR 6
    /// reviews sets with. `Item` is `ScanItem` (iCloud, local paths) or
    /// `CloudFileMetadata` (API providers, server files), so this stays
    /// generic over both legs' row models.
    struct SetSnapshot<Item: Identifiable & Hashable> {
        let id: String
        /// Name of the kept copy (the prototype's set title).
        let title: String
        let items: [Item]
        /// The keep copy's key — its path (iCloud) or file id (API).
        let keepKey: String?
        /// The set's items keyed the way selection stores them.
        let keyOf: (Item) -> String
        let sizeOf: (Item) -> Int64

        /// Every copy except the kept one — the only copies that can ever be
        /// selected.
        var extraItems: [Item] {
            guard let keepKey else { return items }
            return items.filter { keyOf($0) != keepKey }
        }

        /// Size of the copies that would be freed (OD-b's per-set total).
        var extraBytes: Int64 {
            extraItems.reduce(0) { $0 + sizeOf($1) }
        }

        /// Size of one copy as the list head quotes it ("N copies · size each").
        var copySize: Int64 {
            items.first.map(sizeOf) ?? 0
        }
    }

    /// The iCloud duplicate pass's source: the real finder over the locally
    /// synced Mobile Documents tree, or `.custom` — the test seam (fixture
    /// doubles never touch the disk).
    enum ICloudDuplicateSource {
        case finder(DuplicateFinder)
        case custom(@Sendable (@Sendable (ScanProgress) -> Void) async throws -> DuplicateScanResult)
    }

    // MARK: - Stored state (per provider — §6.6 keeps provider states alive)

    /// The provider the main area shows. The column stays in every state.
    var selectedProvider: Provider = .iCloudDrive {
        didSet { overlayConfirmation = nil }
    }

    /// Each provider's phase. iCloud Drive starts usable; the three API
    /// providers start not set up (D5).
    private(set) var phases: [Provider: Phase] = [
        .iCloudDrive: .idle,
        .googleDrive: .notConfigured,
        .dropbox: .notConfigured,
        .oneDrive: .notConfigured,
    ]

    /// Selection per provider — survives switching (§6.6). iCloud keys are
    /// file paths; API keys are file ids.
    private(set) var selectedPaths: [Provider: Set<String>] = [:]

    // iCloud Drive leg (local scan → local Trash).
    private(set) var iCloudGroups: [DuplicateGroup] = []
    private(set) var iCloudListedCount = 0
    /// Copies that couldn't be read while grouping — surfaced when > 0.
    private(set) var iCloudSkippedCount = 0
    /// Per-copy failures of the last clean, surfaced on Done (F4/S6).
    private(set) var lastFailedItems: [CleanResult.FailedItem] = []
    /// Real per-copy cleaning progress (N5); `nil` outside `cleaning`.
    private(set) var cleaningProgress: CleaningProgress?

    // API-provider leg (server listing → server-side delete).
    private(set) var apiFiles: [Provider: [CloudFileMetadata]] = [:]
    private(set) var apiGroups: [Provider: [CloudDuplicateGroup]] = [:]
    private(set) var apiListedCount: [Provider: Int] = [:]
    private(set) var apiProgress: [Provider: ScanProgress] = [:]
    /// Per-file delete failures of the last confirmed delete, per provider
    /// (S6: `failed` is reported for every provider). A whole-call failure
    /// (network, auth) is a message, not per-file rows.
    private(set) var apiDeleteFailures: [Provider: [CloudDeleteFailure]] = [:]
    private(set) var apiDeleteError: [Provider: String] = [:]

    /// Review navigation — per-row UI state, deliberately not part of
    /// `Phase` (§6.6 keeps phase, results and selection; the focused row and
    /// open dialogs reset).
    var currentSetID: String?
    var focusedItemKey: String?

    /// The sheet `CloudCleanupView` presents; kept on the view model so a
    /// provider switch closes it. `nil` presents nothing.
    var overlayConfirmation: ConfirmSheet.Model?

    let progressTracker = ScanProgressTracker()
    private var scanTask: Task<Void, Never>?

    // MARK: - Dependencies (injectable; defaults are the production wiring)

    private let iCloudScanner: any CleanCore.Scanner
    private let iCloudDuplicateSource: ICloudDuplicateSource
    private let iCloudCleaner: any Cleaner
    private let progressiveCleaner = ProgressiveCleaner()
    private let apiProviders: [Provider: any CloudProvider]

    init(config: CloudCleanupConfig = .placeholder,
         apiProviders: [Provider: any CloudProvider]? = nil,
         iCloudScanner: (any CleanCore.Scanner)? = nil,
         iCloudDuplicates: ICloudDuplicateSource? = nil,
         iCloudCleaner: any Cleaner = DefaultCleaner()) {
        self.iCloudScanner = iCloudScanner ?? ICloudLocalScanner()
        self.iCloudDuplicateSource = iCloudDuplicates
            ?? .finder(DuplicateFinder(rootPath: ICloudLocalScanner.mobileDocumentsRoot))
        self.iCloudCleaner = iCloudCleaner
        if let apiProviders {
            self.apiProviders = apiProviders
        } else {
            // Same fail-closed construction the old screen used: placeholder
            // configs make every provider refuse to talk to the network.
            let webPresenter = ASWebAuthSessionPresenter()
            self.apiProviders = [
                .googleDrive: GoogleDriveProvider(config: config.googleDrive, webSession: webPresenter),
                .dropbox: DropboxProvider(config: config.dropbox, webSession: webPresenter),
                .oneDrive: OneDriveProvider(config: config.oneDrive, webSession: webPresenter),
            ]
        }
    }

    // MARK: - Phase access and lifecycle mapping

    func phase(of provider: Provider) -> Phase {
        phases[provider] ?? (provider == .iCloudDrive ? .idle : .notConfigured)
    }

    private func setPhase(_ phase: Phase, for provider: Provider) {
        phases[provider] = phase
    }

    /// The pure mapping the shared frame renders from, for the selected
    /// provider. An API provider's `results` maps to `.review` — the
    /// server-delete surface is the sets list with the shared review bar
    /// (spec §5.6 `?screen=cloud&state=drive`), not a tiles-and-dock screen.
    var lifecycle: LifecycleState {
        switch phase(of: selectedProvider) {
        case .notConfigured, .idle: .start
        case .scanning: .scanning
        case .results:
            switch selectedProvider {
            case .iCloudDrive: iCloudGroups.isEmpty ? .empty : .results
            default: apiGroups[selectedProvider]?.isEmpty != false ? .empty : .review
            }
        case .review: .review
        case .cleaning: .cleaning
        case .done: .done
        case .empty: .empty
        case .failed: .error
        }
    }

    /// Whether the selected provider is mid-scan or mid-removal — the
    /// re-entrancy guard's input.
    func isBusy(_ provider: Provider) -> Bool {
        switch phase(of: provider) {
        case .scanning, .cleaning: true
        default: false
        }
    }

    /// Whether any provider is mid-scan or mid-removal — the sidebar's busy
    /// dot (ModuleStore reads this; a provider keeps running in the
    /// background, OD-3).
    var isAnyProviderBusy: Bool {
        phases.values.contains { phase in
            switch phase {
            case .scanning, .cleaning: true
            default: false
            }
        }
    }

    // MARK: - Provider switching

    /// Switching providers is always allowed: each provider keeps its own
    /// phase and results (a running scan keeps running, OD-3). Any open
    /// confirmation belongs to the old provider and closes.
    func selectProvider(_ provider: Provider) {
        selectedProvider = provider
    }

    // MARK: - Derived state (real values only)

    private var selection: Set<String> {
        selectedPaths[selectedProvider] ?? []
    }

    private func setSelection(_ newValue: Set<String>) {
        selectedPaths[selectedProvider] = newValue
    }

    /// The selected provider's sets, rebuilt on demand from the groups
    /// (small lists; a cloud account's groups arrive in the dozens, not the
    /// 100 k of a Home scan).
    var sets: [SetSnapshot<ScanItem>] {
        guard selectedProvider == .iCloudDrive else { return [] }
        return iCloudGroups.compactMap { group in
            guard group.items.count >= 2 else { return nil }
            return SetSnapshot(
                id: group.id,
                title: keepTitle(for: group),
                items: group.items,
                keepKey: group.recommendedKeepPath,
                keyOf: { $0.path },
                sizeOf: { $0.size })
        }
    }

    var apiSets: [SetSnapshot<CloudFileMetadata>] {
        guard let groups = apiGroups[selectedProvider] else { return [] }
        return groups.compactMap { group in
            guard group.files.count >= 2 else { return nil }
            let keep = group.recommendedKeepID
            return SetSnapshot(
                id: group.id,
                title: group.files.first { $0.id == keep }?.name
                    ?? group.files.first?.name
                    ?? group.id,
                items: group.files,
                keepKey: keep,
                keyOf: { $0.id },
                sizeOf: { $0.size })
        }
    }

    private func keepTitle(for group: DuplicateGroup) -> String {
        let keep = group.recommendedKeepPath
        if let keep {
            return (keep as NSString).lastPathComponent
        }
        return group.items.first.map { ($0.path as NSString).lastPathComponent } ?? group.id
    }

    var currentSet: SetSnapshot<ScanItem>? {
        guard selectedProvider == .iCloudDrive else { return nil }
        let sets = sets
        if let currentSetID, let found = sets.first(where: { $0.id == currentSetID }) {
            return found
        }
        return sets.first
    }

    var currentAPISet: SetSnapshot<CloudFileMetadata>? {
        guard selectedProvider != .iCloudDrive else { return nil }
        let sets = apiSets
        if let currentSetID, let found = sets.first(where: { $0.id == currentSetID }) {
            return found
        }
        return sets.first
    }

    /// The copy whose detail the review frame shows: the focused row, or the
    /// first row of the current set, or nothing.
    var focusedItem: ScanItem? {
        let items = currentSet?.items ?? []
        if let focusedItemKey, let found = items.first(where: { $0.path == focusedItemKey }) {
            return found
        }
        return items.first
    }

    var focusedAPIFile: CloudFileMetadata? {
        let files = currentAPISet?.items ?? []
        if let focusedItemKey, let found = files.first(where: { $0.id == focusedItemKey }) {
            return found
        }
        return files.first
    }

    /// The one rule for "can this copy be selected": it is not a set's keep.
    func isKept(_ key: String) -> Bool {
        switch selectedProvider {
        case .iCloudDrive: currentSet?.keepKey == key || iCloudKeepPaths.contains(key)
        default: apiKeepIDs[selectedProvider]?.contains(key) ?? false
        }
    }

    /// Paths that are some iCloud set's keep copy — rebuilt with the groups.
    private var iCloudKeepPaths: Set<String> {
        Set(iCloudGroups.compactMap(\.recommendedKeepPath))
    }

    private var apiKeepIDs: [Provider: Set<String>] {
        apiGroups.mapValues { groups in
            Set(groups.compactMap(\.recommendedKeepID))
        }
    }

    /// Selected copies of the selected provider — never counts a keep copy.
    var selectedItems: [ScanItem] {
        guard selectedProvider == .iCloudDrive else { return [] }
        return iCloudGroups.flatMap(\.items)
            .filter { selection.contains($0.path) && !iCloudKeepPaths.contains($0.path) }
    }

    var selectedFiles: [CloudFileMetadata] {
        guard selectedProvider != .iCloudDrive else { return [] }
        let keeps = apiKeepIDs[selectedProvider] ?? []
        return (apiFiles[selectedProvider] ?? [])
            .filter { selection.contains($0.id) && !keeps.contains($0.id) }
    }

    var totalSelectedBytes: Int64 {
        switch selectedProvider {
        case .iCloudDrive: selectedItems.reduce(0) { $0 + $1.size }
        default: selectedFiles.reduce(0) { $0 + $1.size }
        }
    }

    var selectedCount: Int {
        switch selectedProvider {
        case .iCloudDrive: selectedItems.count
        default: selectedFiles.count
        }
    }

    /// Files the listing saw — the "N files listed" figure (§6.4).
    var listedFileCount: Int {
        switch selectedProvider {
        case .iCloudDrive: iCloudListedCount
        default: apiListedCount[selectedProvider] ?? 0
        }
    }

    /// Selected copies in one set — never counts the keep copy.
    func selectedCount(in set: SetSnapshot<ScanItem>) -> Int {
        set.extraItems.count { selection.contains($0.path) }
    }

    func selectedAPICount(in set: SetSnapshot<CloudFileMetadata>) -> Int {
        set.extraItems.count { selection.contains($0.id) }
    }

    /// Sets the selected provider currently shows.
    var setCount: Int {
        selectedProvider == .iCloudDrive ? sets.count : apiSets.count
    }

    /// The engine's reason for a failed scan, `nil` in every other phase.
    var errorMessage: String? {
        if case .failed(let message) = phase(of: selectedProvider) { return message }
        return nil
    }

    // MARK: - Scan

    /// Starts the selected provider's scan. `false` when it is already
    /// scanning or removing (PR 3 re-entrancy guard).
    @discardableResult
    func startScan() -> Bool {
        guard !isBusy(selectedProvider) else { return false }
        scanTask?.cancel()
        let provider = selectedProvider
        scanTask = Task { [weak self] in
            await self?.performScan(for: provider)
        }
        return true
    }

    /// F2: Stop returns to `start` and discards partial results — including
    /// the previous scan's, which would otherwise look like the outcome of
    /// this one.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        let provider = selectedProvider
        guard isBusy(provider) else { return }
        resetScanState(for: provider)
        setPhase(provider == .iCloudDrive ? .idle : .notConfigured, for: provider)
    }

    private func resetScanState(for provider: Provider) {
        selectedPaths[provider] = []
        currentSetID = nil
        focusedItemKey = nil
        cleaningProgress = nil
        lastFailedItems = []
        apiDeleteFailures[provider] = []
        apiDeleteError[provider] = nil
        if provider == .iCloudDrive {
            iCloudGroups = []
            iCloudListedCount = 0
            iCloudSkippedCount = 0
            progressTracker.reset()
        } else {
            apiFiles[provider] = []
            apiGroups[provider] = []
            apiListedCount[provider] = 0
            apiProgress[provider] = nil
        }
    }

    private func performScan(for provider: Provider) async {
        if provider == .iCloudDrive {
            await performICloudScan()
        } else {
            await performAPIScan(provider)
        }
    }

    /// iCloud Drive: list the locally synced files, then group them with the
    /// same exact-duplicate pass as Duplicate Finder (the files are already
    /// on disk — no bandwidth cost, unlike the API providers).
    private func performICloudScan() async {
        let provider = Provider.iCloudDrive
        setPhase(.scanning, for: provider)
        lastFailedItems = []
        cleaningProgress = nil
        iCloudSkippedCount = 0
        let generation = progressTracker.start()

        let items: [ScanItem]
        do {
            items = try await iCloudScanner.scan()
        } catch {
            guard !Task.isCancelled else { return }
            setPhase(.failed(message: Self.describe(error)), for: provider)
            return
        }
        guard !Task.isCancelled else { return }
        iCloudListedCount = items.count

        let result: DuplicateScanResult
        do {
            switch iCloudDuplicateSource {
            case .finder(let finder):
                result = try await finder.findExactDuplicateGroups(onProgress: { [weak self] progress in
                    Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
                })
            case .custom(let scan):
                result = try await scan({ [weak self] progress in
                    Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
                })
            }
        } catch {
            guard !Task.isCancelled else { return }
            setPhase(.failed(message: Self.describe(error)), for: provider)
            return
        }

        guard !Task.isCancelled else { return }
        applyICloudResults(groups: result.groups, skippedCount: result.skippedCount)
    }

    /// An API provider: page through the file list (the grouping matches on
    /// the provider's own content hashes — files are never downloaded to
    /// compare them).
    private func performAPIScan(_ provider: Provider) async {
        setPhase(.scanning, for: provider)
        apiDeleteFailures[provider] = []
        guard let apiProvider = apiProviders[provider] else {
            setPhase(.failed(message: "This provider isn't connected."), for: provider)
            return
        }

        var allFiles: [CloudFileMetadata] = []
        var cursor: String?
        var pageCount = 0
        // CloudHTTPClient's backoff only guards against 429/5xx — it bounds
        // nothing about a loop of successful (200) pages. A provider returning
        // a cursor that never advances would otherwise become a tight loop.
        let maxPages = 500
        do {
            repeat {
                let page = try await apiProvider.listFiles(cursor: cursor)
                allFiles.append(contentsOf: page.files)
                cursor = page.nextCursor
                pageCount += 1
                apiProgress[provider] = ScanProgress(itemsProcessed: allFiles.count)
            } while cursor != nil && pageCount < maxPages && !Task.isCancelled

            if cursor != nil {
                setPhase(.failed(message: "Stopped after \(maxPages) pages — this provider may have far more files than expected."), for: provider)
                return
            }
        } catch {
            guard !Task.isCancelled else { return }
            setPhase(.failed(message: Self.describe(error)), for: provider)
            return
        }

        guard !Task.isCancelled else { return }
        applyAPIResults(provider, files: allFiles)
    }

    /// The completed iCloud scan over a result set. Pre-selection is **none**
    /// (OD-7, settled): nothing is selected until the user picks it.
    private func applyICloudResults(groups newGroups: [DuplicateGroup], skippedCount: Int) {
        iCloudGroups = newGroups
        iCloudSkippedCount = skippedCount
        selectedPaths[.iCloudDrive] = []
        currentSetID = nil
        focusedItemKey = nil
        setPhase(newGroups.isEmpty ? .empty : .results, for: .iCloudDrive)
    }

    /// The completed API scan: nothing pre-selected (the server-delete
    /// surface shows "nothing selected" by design).
    private func applyAPIResults(_ provider: Provider, files: [CloudFileMetadata]) {
        apiFiles[provider] = files
        apiGroups[provider] = CloudDuplicateGrouper.findDuplicates(among: files)
        apiListedCount[provider] = files.count
        selectedPaths[provider] = []
        currentSetID = nil
        focusedItemKey = nil
        apiProgress[provider] = nil
        setPhase((apiGroups[provider] ?? []).isEmpty ? .empty : .results, for: provider)
    }

    // MARK: - Review

    /// iCloud only: the tiles-and-dock results step into the review frame.
    /// An API provider's results already are the review surface.
    func enterReview() {
        guard selectedProvider == .iCloudDrive, phase(of: .iCloudDrive) == .results, !sets.isEmpty else { return }
        setPhase(.review, for: .iCloudDrive)
        if currentSetID == nil || !sets.contains(where: { $0.id == currentSetID }) {
            currentSetID = sets.first?.id
            focusedItemKey = nil
        }
    }

    func backToResults() {
        guard selectedProvider == .iCloudDrive, phase(of: .iCloudDrive) == .review else { return }
        setPhase(.results, for: .iCloudDrive)
    }

    func selectSet(_ id: String) {
        currentSetID = id
        focusedItemKey = nil
    }

    func focusItem(key: String) {
        focusedItemKey = key
    }

    /// The keep copy is never toggled — by click, by keyboard, or by any
    /// caller (§4.6).
    func toggleSelection(key: String) {
        guard !isKept(key) else { return }
        var selection = selection
        if selection.contains(key) {
            selection.remove(key)
        } else {
            selection.insert(key)
        }
        setSelection(selection)
    }

    /// Select All in the current set — every extra copy, never the kept one
    /// (§4.6). Nothing is pre-selected on this screen (OD-7; the server
    /// surface by design), so Select All is always an explicit user action.
    func selectAllInCurrentSet() {
        guard let set = selectedProvider == .iCloudDrive
            ? currentSet.map({ set in Set(set.extraItems.map { $0.path }) })
            : currentAPISet.map({ set in Set(set.extraItems.map { $0.id }) })
        else { return }
        var selection = selection
        selection.formUnion(set)
        setSelection(selection)
    }

    func deselectAllInCurrentSet() {
        guard let keys = selectedProvider == .iCloudDrive
            ? currentSet.map({ Set($0.items.map { $0.path }) })
            : currentAPISet.map({ Set($0.items.map { $0.id }) })
        else { return }
        var selection = selection
        selection.subtract(keys)
        setSelection(selection)
    }

    // MARK: - Confirmations (S1/S2 — nothing leaves without one)

    /// iCloud Drive's **local** Trash confirmation (CF-3: the count and size
    /// are the numbers the review bar shows, computed here once).
    /// "Review Items…" is offered only when the sheet is opened from
    /// `results` (§4.8).
    func iCloudTrashConfirmation(isFromResults: Bool) -> ConfirmSheet.Model {
        let selected = selectedItems
        var reviewItems: (@MainActor () -> Void)?
        if isFromResults {
            reviewItems = { [weak self] in self?.enterReview() }
        }
        return ConfirmSheet.Model(
            variant: .trash,
            count: selected.count,
            sizeText: ConfirmItemList.sizeText(for: selected.reduce(0) { $0 + $1.size }),
            isFromResults: isFromResults,
            items: selected.map { item in
                ConfirmItem(id: item.path,
                            name: (item.path as NSString).lastPathComponent,
                            path: item.path,
                            size: item.size)
            },
            hue: Theme.Hue.cloud,
            confirm: { [weak self] _ in self?.beginICloudClean() },
            cancel: { },
            reviewItems: reviewItems)
    }

    /// The server-side **cloud** confirmation (§4.8): the Delete button is
    /// disabled until the acknowledgement is ticked — the shared
    /// `ConfirmSheetState` gate. The sheet's cloud copy names the provider.
    func cloudConfirmation(for provider: Provider) -> ConfirmSheet.Model {
        let selected = selectedFiles
        return ConfirmSheet.Model(
            variant: .cloud,
            count: selected.count,
            items: selected.map { file in
                ConfirmItem(id: file.id, name: file.name, size: file.size)
            },
            hue: Theme.Hue.cloud,
            providerName: provider.rawValue,
            confirm: { [weak self] _ in self?.beginAPIDelete(provider) },
            cancel: { })
    }

    /// Starts the confirmed iCloud clean from the sheet's synchronous
    /// callback; the sheet is already dismissed when this runs.
    private func beginICloudClean() {
        Task { [weak self] in
            await self?.cleanICloud()
        }
    }

    /// Starts the confirmed server-side delete the same way.
    private func beginAPIDelete(_ provider: Provider) {
        Task { [weak self] in
            await self?.deleteFromAPI(provider)
        }
    }

    // MARK: - iCloud clean (local Trash)

    /// Moves the confirmed iCloud selection to the local Trash, one
    /// `Cleaner.clean([item])` per copy (spec §6.5). Re-entrant calls are
    /// refused while a removal is in flight.
    @discardableResult
    func cleanICloud() async -> Bool {
        let provider = Provider.iCloudDrive
        guard !isBusy(provider) else { return false }
        // Defence in depth: `selectedItems` already excludes every keep copy,
        // so a stray path can never reach the Cleaner.
        let toClean = selectedItems
        guard !toClean.isEmpty else { return false }

        setPhase(.cleaning(selectedCount: toClean.count), for: provider)
        cleaningProgress = CleaningProgress(attemptedCount: 0, totalCount: toClean.count, currentPath: nil)
        lastFailedItems = []

        let result = await progressiveCleaner.clean(toClean, using: iCloudCleaner) { [weak self] index, item in
            self?.cleaningProgress = CleaningProgress(attemptedCount: index + 1,
                                                      totalCount: toClean.count,
                                                      currentPath: item.path)
        }

        // S6: groups recompute from what is left — a set down to one copy is
        // no longer a duplicate set, and the keep copy is recomputed with it.
        let succeededPaths = Set(result.succeeded.map(\.path))
        iCloudGroups = iCloudGroups.compactMap { group in
            let remaining = group.items.filter { !succeededPaths.contains($0.path) }
            return remaining.count >= 2 ? DuplicateGroup(id: group.id, items: remaining) : nil
        }
        var selection = selection
        selection.subtract(succeededPaths)
        selection.formIntersection(Set(iCloudGroups.flatMap(\.items).map(\.path)))
        selectedPaths[provider] = selection
        if let currentSetID, !iCloudGroups.contains(where: { $0.id == currentSetID }) {
            self.currentSetID = nil
            focusedItemKey = nil
        }
        cleaningProgress = nil
        lastFailedItems = result.failed
        setPhase(.done(movedBytes: result.succeeded.reduce(0) { $0 + $1.size },
                       movedCount: result.succeeded.count,
                       failedCount: result.failed.count),
                 for: provider)
        return true
    }

    // MARK: - API delete (server-side)

    /// Deletes the confirmed selection on the provider's servers. The Delete
    /// button only reaches here once the acknowledgement was ticked; the
    /// guard refuses while another removal is in flight.
    @discardableResult
    func deleteFromAPI(_ provider: Provider) async -> Bool {
        guard !isBusy(provider) else { return false }
        let keeps = apiKeepIDs[provider] ?? []
        let toDelete = selectedFiles.filter { !keeps.contains($0.id) }
        guard !toDelete.isEmpty, let apiProvider = apiProviders[provider] else { return false }

        setPhase(.cleaning(selectedCount: toDelete.count), for: provider)
        let deletedBytes = toDelete.reduce(0) { $0 + $1.size }
        let ids = toDelete.map(\.id)

        let result: CloudDeleteResult
        do {
            result = try await apiProvider.delete(fileIDs: ids)
        } catch {
            // S6: the failure is reported, never folded into a success count.
            apiDeleteError[provider] = Self.describe(error)
            apiDeleteFailures[provider] = []
            setPhase(.done(movedBytes: 0, movedCount: 0, failedCount: toDelete.count), for: provider)
            return false
        }
        apiDeleteError[provider] = nil

        // S6: recompute the groups from the files that remain.
        let succeeded = Set(result.succeededIDs)
        let remainingFiles = (apiFiles[provider] ?? []).filter { !succeeded.contains($0.id) }
        apiFiles[provider] = remainingFiles
        apiGroups[provider] = CloudDuplicateGrouper.findDuplicates(among: remainingFiles)
        var selection = selectedPaths[provider] ?? []
        selection.subtract(succeeded)
        selection.formIntersection(Set(remainingFiles.map(\.id)))
        selectedPaths[provider] = selection
        if let id = currentSetID, !(apiGroups[provider] ?? []).contains(where: { $0.id == id }) {
            currentSetID = nil
            focusedItemKey = nil
        }
        apiDeleteFailures[provider] = result.failed
        setPhase(.done(movedBytes: deletedBytes,
                       movedCount: result.succeededIDs.count,
                       failedCount: result.failed.count),
                 for: provider)
        return true
    }

    private static func describe(_ error: Error) -> String {
        if let cloudError = error as? CloudProviderError {
            switch cloudError {
            case .notConfigured:
                return "This provider isn't configured yet — needs a registered OAuth app's client ID and redirect URI."
            case .notAuthenticated:
                return "Not connected."
            case .rateLimited:
                return "Rate limited — try again shortly."
            case .requestFailed(let statusCode):
                return "Request failed (HTTP \(statusCode))."
            }
        }
        if let stub = error as? LocalizedError, let message = stub.errorDescription, !message.isEmpty {
            return message
        }
        return error.localizedDescription
    }

    // MARK: - Fixtures (Debug builds only)

#if DEBUG
    /// Loads one of the eight lifecycle states for iCloud Drive from the
    /// fictional sample data (`UITestFixtures+CloudCleanup`). Called from the
    /// screen's `.task` when `SOSMAC_UITEST_FIXTURES=1` names this screen;
    /// never reads the real file system.
    func loadFixture(_ state: LifecycleState) {
        selectProvider(.iCloudDrive)
        switch state {
        case .start:
            resetScanState(for: .iCloudDrive)
            setPhase(.idle, for: .iCloudDrive)

        case .scanning:
            resetScanState(for: .iCloudDrive)
            setPhase(.scanning, for: .iCloudDrive)
            // The compare pass part-way through the fixture tree (a
            // fictional, fixed sample — real fixture figures only).
            let generation = progressTracker.start()
            progressTracker.record(
                ScanProgress(itemsProcessed: 96, totalItems: 148,
                             currentPath: "\(UITestFixtures.iCloudHome)/Documents/Brand/brand-guidelines-v2.pdf"),
                generation: generation)

        case .results:
            applyICloudFixtureResults()

        case .review:
            applyICloudFixtureResults()
            enterReview()
            if let first = currentSet?.items.first?.path {
                focusItem(key: first)
            }

        case .cleaning:
            applyICloudFixtureResults()
            applyICloudFixtureSelectionIfEmpty()
            let count = selectedItems.count
            setPhase(.cleaning(selectedCount: count), for: .iCloudDrive)
            cleaningProgress = CleaningProgress(
                attemptedCount: min(2, count),
                totalCount: count,
                currentPath: selectedItems.first?.path)

        case .done:
            // As if the selection had just been moved: the moved copies are
            // gone, the groups recomputed, nothing failed (S6).
            applyICloudFixtureResults()
            applyICloudFixtureSelectionIfEmpty()
            let pick = selectedItems
            let movedPaths = Set(pick.map(\.path))
            iCloudGroups = iCloudGroups.compactMap { group in
                let remaining = group.items.filter { !movedPaths.contains($0.path) }
                return remaining.count >= 2 ? DuplicateGroup(id: group.id, items: remaining) : nil
            }
            selectedPaths[.iCloudDrive] = []
            lastFailedItems = []
            setPhase(.done(movedBytes: pick.reduce(0) { $0 + $1.size },
                           movedCount: pick.count,
                           failedCount: 0),
                     for: .iCloudDrive)

        case .empty:
            resetScanState(for: .iCloudDrive)
            iCloudListedCount = UITestFixtures.iCloudListedFileCount
            setPhase(.empty, for: .iCloudDrive)

        case .error:
            resetScanState(for: .iCloudDrive)
            setPhase(.failed(message: "The file “Mobile Documents” couldn’t be opened because you don’t have permission to view it."),
                     for: .iCloudDrive)
        }
    }

    /// The three "not set up in this build" states (D5): selects the provider
    /// and puts it in `notConfigured`.
    func loadNotConfiguredFixture(_ provider: Provider) {
        selectProvider(provider)
        resetScanState(for: provider)
        setPhase(.notConfigured, for: provider)
    }

    /// The server-delete design target (`?screen=cloud&state=drive`): Google
    /// Drive's results as the sets list with nothing selected, the warn
    /// banner and the danger CTA. Fixture data only — no network call.
    func loadDriveFixture() {
        let provider = Provider.googleDrive
        selectProvider(provider)
        applyAPIResults(provider, files: UITestFixtures.driveFiles)
    }

    /// The launch-hook half of the fixture convention. iCloud's eight
    /// lifecycle states are spelled as-is (`cloud=results`); the extra
    /// states are lowercase provider words: `drive` (the Google Drive target)
    /// and `gdrive` / `dropbox` / `onedrive` (their not-configured states).
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .cloudCleanup, let raw = hooks.state else { return }
        switch raw {
        case "drive":
            loadDriveFixture()
        case Provider.googleDrive.fixtureKey:
            loadNotConfiguredFixture(.googleDrive)
        case Provider.dropbox.fixtureKey:
            loadNotConfiguredFixture(.dropbox)
        case Provider.oneDrive.fixtureKey:
            loadNotConfiguredFixture(.oneDrive)
        default:
            guard let state = LifecycleState(rawValue: raw) else { return }
            loadFixture(state)
        }
    }

    /// Test-only: the completed iCloud scan over arbitrary groups. The paths
    /// need not exist — clean-path tests use hermetic temp files.
    func loadFixtureResults(_ newGroups: [DuplicateGroup], listedCount: Int = 0, skippedCount: Int = 0) {
        selectProvider(.iCloudDrive)
        iCloudListedCount = listedCount
        applyICloudResults(groups: newGroups, skippedCount: skippedCount)
    }

    /// Test-only: a completed API scan over arbitrary files, as if the
    /// provider had been listed successfully.
    func loadFixtureAPIResults(_ provider: Provider, files: [CloudFileMetadata]) {
        selectProvider(provider)
        applyAPIResults(provider, files: files)
    }

    private func applyICloudFixtureResults() {
        loadFixtureResults(UITestFixtures.iCloudDuplicateSets.map { DuplicateGroup(id: $0.id, items: $0.items) },
                           listedCount: UITestFixtures.iCloudListedFileCount,
                           skippedCount: 0)
    }

    /// Cleaning and Done need a selection to act on. iCloud pre-selects
    /// nothing (OD-7), so the fixture picks the first set's extra copies, as
    /// if the user had chosen them.
    private func applyICloudFixtureSelectionIfEmpty() {
        guard (selectedPaths[.iCloudDrive] ?? []).isEmpty, let first = sets.first else { return }
        selectedPaths[.iCloudDrive] = Set(first.extraItems.map(\.path))
    }
#endif
}

#if DEBUG
extension CloudCleanupViewModel.Provider {
    /// The lowercase fixture key (`SOSMAC_UITEST_STATE=…`): the enum's raw
    /// value lowercased without spaces — "google drive" → "gdrive" is the
    /// prototype's own key, spelled out here.
    var fixtureKey: String {
        switch self {
        case .iCloudDrive: "icloud"
        case .googleDrive: "gdrive"
        case .dropbox: "dropbox"
        case .oneDrive: "onedrive"
        }
    }
}
#endif

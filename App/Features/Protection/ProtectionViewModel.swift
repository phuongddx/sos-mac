import Foundation
import Observation
import os
import SwiftData
import CleanCore

/// Protection on the shared lifecycle frame (plan PR 13, spec §5.10).
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `idle` | disclaimer · "Check for known malware" · the six location names · quarantine panel (when it has entries) · **Scan** |
/// | `scanning` | `scanning` | "Checking files…" · six step rows · "n of N files" + ETA · current path · **Stop** |
/// | `results` | `results` (findings) | tiles **Known threats** / **Already in quarantine** · Review Items… · Scan Again |
/// | `empty` | `results` (no findings) | "No known threats found" + the engine's file count · Scan Again |
///
/// `results` and `empty` also carry a banner naming any location the engine could not read
/// (D10), and say "N files checked in 5 of 6 locations" when there is one. If *no* location
/// could be read the scan is `failed`, never an empty "all clear".
/// | `review` | `review` | groups = locations with findings · detail (Detection, Identifier, Found, Path, Size) · **Quarantine…** |
/// | `cleaning` | `quarantining(selectedCount:)` | "Moving n of N items to quarantine…" |
/// | `done` | `done(quarantinedCount:failedCount:)` | stats · failure banners (F4) · quarantine panel · Scan Again |
/// | `error` | `failed(message:)` | "The scan stopped" + the engine's reason · Try Again |
/// | sub-screen | any non-busy phase + `isShowingQuarantine` | the **Quarantine** panel in a scroll view (N8) · back to Protection |
///
/// Safety: nothing is ever pre-selected, and nothing is removed — a finding moves to
/// `QuarantineManager`'s app-managed folder (reversible) with a persisted `QuarantineRecord`.
/// There is no hard-delete path here. "Check VirusTotal" is gone (OD-15): it did nothing
/// without an API key, and Protection never claims more than a known-signature scan.
@MainActor
@Observable
final class ProtectionViewModel {

    // MARK: - Phase (the screen's whole state)

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case review
        case quarantining(selectedCount: Int)
        case done(quarantinedCount: Int, failedCount: Int)
        case failed(message: String)
    }

    /// One scan location: its allowlist name and, once a scan has resolved them, the
    /// concrete roots it walks. The roots drive the scanning step rows (which location the
    /// engine's current path is in) and the review groups.
    struct LocationSummary: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        var roots: [String]
    }

    /// One review group: the findings under one location.
    struct FindingGroup: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let findings: [ThreatFinding]
    }

    /// A snapshot of the per-item quarantine loop: `attemptedCount` items tried so far out of
    /// the `totalCount` the user confirmed.
    struct QuarantineProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
    }

    /// One file that did not end up cleanly quarantined, surfaced on Done (F4) with a reason.
    struct QuarantineFailure: Equatable, Sendable {
        let name: String
        let reason: String
    }

    /// A location the last scan could not read, with the engine's own reasons (one per
    /// unreadable root). `id` is the location's id; a root no location claims (never expected)
    /// is listed under its own path so it is shown, never dropped.
    struct UnreadableLocation: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let reasons: [String]
    }

    /// A restore (or record-save) problem, drawn as a banner next to the quarantine list.
    struct ActionError: Equatable, Sendable {
        let title: String
        let text: String
    }

    static let fallbackGroupID = "other"

    // MARK: - State

    private(set) var phase: Phase = .idle
    private(set) var findings: [ThreatFinding] = []
    private(set) var selectedPaths: Set<String> = []
    private(set) var quarantinedRecords: [QuarantineRecord] = []
    private(set) var lastFailures: [QuarantineFailure] = []
    private(set) var quarantineProgress: QuarantineProgress?
    private(set) var actionError: ActionError?
    /// The engine's own count of files walked by the last scan (0 until one finishes).
    private(set) var checkedFileCount = 0
    private(set) var locationSummaries: [LocationSummary]
    /// Locations the last scan could not read (empty when every one was checked).
    private(set) var unreadableLocations: [UnreadableLocation] = []
    /// The home folder the displayed paths are abbreviated against (`~/Downloads`).
    private(set) var homeDirectory: String = NSHomeDirectory()
    /// The Quarantine sub-screen (toolbar back button "Protection"). Independent of `phase`,
    /// so a running scan or quarantine keeps its state while the list is open.
    private(set) var isShowingQuarantine = false

    /// Review navigation — per-row UI state, deliberately outside `Phase`.
    var currentGroupID: String?
    var focusedPath: String?

    private(set) var progressTracker: ScanProgressTracker

    private let modelContext: ModelContext
    private let locations: [ProtectionLocation]
    private let scanner: ProtectionScanner
    private let quarantineManager: QuarantineManager
    private let persistQuarantine: (@MainActor (QuarantinedFile) throws -> Void)?
    private var scanTask: Task<Void, Never>?

    /// `persistQuarantine` is a test seam for the record-save step: `nil` (the default) inserts
    /// a `QuarantineRecord` into `modelContext` and saves it.
    init(
        modelContext: ModelContext,
        locations: [ProtectionLocation] = ProtectionLocation.allowlist,
        signatureDatabase: SignatureDatabase = .bundledBaseline,
        quarantineManager: QuarantineManager = QuarantineManager(),
        progressTracker: ScanProgressTracker = ScanProgressTracker(),
        persistQuarantine: (@MainActor (QuarantinedFile) throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.locations = locations
        self.scanner = ProtectionScanner(locations: locations, signatureDatabase: signatureDatabase)
        self.quarantineManager = quarantineManager
        self.progressTracker = progressTracker
        self.persistQuarantine = persistQuarantine
        self.locationSummaries = locations.map { LocationSummary(id: $0.id, label: $0.label, roots: []) }
        self.quarantinedRecords = Self.fetchRecords(from: modelContext)
    }

    // MARK: - Lifecycle mapping

    /// The pure mapping the shared frame renders from. `results` with no finding and no
    /// failure is `empty` (F3: a failed scan is `.failed`, so it can never read as "nothing
    /// found").
    var lifecycle: LifecycleState {
        switch phase {
        case .idle: .start
        case .scanning: .scanning
        case .results: findings.isEmpty ? .empty : .results
        case .review: .review
        case .quarantining: .cleaning
        case .done: .done
        case .failed: .error
        }
    }

    var isQuarantining: Bool {
        if case .quarantining = phase { return true }
        return false
    }

    /// A scan or a quarantine is running — the re-entrancy guard's input and the sidebar's
    /// busy dot.
    var isBusy: Bool { phase == .scanning || isQuarantining }

    // MARK: - Derived state (real values only)

    /// The location count the copy uses ("6 locations").
    var locationCount: Int { locations.count }

    /// How many locations the last scan really looked into: a location with any unreadable
    /// root does not count.
    var checkedLocationCount: Int {
        let known = Set(locationSummaries.map(\.id))
        return max(0, locationCount - unreadableLocations.filter { known.contains($0.id) }.count)
    }

    var selectedFindings: [ThreatFinding] {
        findings.filter { selectedPaths.contains($0.path) }
    }

    var selectedBytes: Int64 {
        selectedFindings.reduce(0) { $0 + $1.size }
    }

    var findingGroups: [FindingGroup] {
        Self.groups(from: findings, locations: locationSummaries)
    }

    var currentGroup: FindingGroup? {
        let groups = findingGroups
        if let currentGroupID, let found = groups.first(where: { $0.id == currentGroupID }) {
            return found
        }
        return groups.first
    }

    /// The finding whose detail the review shows: the focused row, else the group's first.
    var focusedFinding: ThreatFinding? {
        let group = currentGroup?.findings ?? []
        if let focusedPath, let found = group.first(where: { $0.path == focusedPath }) {
            return found
        }
        return group.first
    }

    /// The scanning step rows, in scan order. The engine reports the file it is on, not a
    /// location, so the active step is the location whose roots contain that path: earlier
    /// locations are done, later ones pending. Before the first report the first is active.
    var scanStepStates: [(label: String, state: StepProgress)] {
        let active: Int?
        if let progress = progressTracker.progress {
            active = progress.currentPath.flatMap { Self.locationIndex(forPath: $0, in: locationSummaries) }
        } else {
            active = 0
        }
        return locationSummaries.enumerated().map { index, location in
            guard let active else { return (location.label, .pending) }
            return (location.label, index < active ? .done : (index == active ? .active : .pending))
        }
    }

    enum StepProgress: Equatable, Sendable { case done, active, pending }

    // MARK: - Pure helpers (unit-tested)

    /// The index of the location whose root contains `path`, matched on a path boundary
    /// (`/a/Downloads` does not contain `/a/Downloads2/x`).
    static func locationIndex(forPath path: String, in locations: [LocationSummary]) -> Int? {
        locations.firstIndex { location in
            location.roots.contains { root in
                let base = root.hasSuffix("/") ? String(root.dropLast()) : root
                return path == base || path.hasPrefix(base + "/")
            }
        }
    }

    /// One group per location that has findings, in scan order, plus a fallback group for a
    /// finding no location claims — fail closed: an unexpected path is shown, never dropped.
    static func groups(from findings: [ThreatFinding], locations: [LocationSummary]) -> [FindingGroup] {
        var buckets = [[ThreatFinding]](repeating: [], count: locations.count)
        var unmatched: [ThreatFinding] = []
        for finding in findings {
            if let index = locationIndex(forPath: finding.path, in: locations) {
                buckets[index].append(finding)
            } else {
                unmatched.append(finding)
            }
        }
        var groups = locations.enumerated().compactMap { index, location -> FindingGroup? in
            buckets[index].isEmpty ? nil : FindingGroup(id: location.id, label: location.label, findings: buckets[index])
        }
        if !unmatched.isEmpty {
            groups.append(FindingGroup(id: fallbackGroupID, label: "Other", findings: unmatched))
        }
        return groups
    }

    /// Groups the engine's unreadable roots by the location that owns them, in scan order,
    /// keeping the engine's own reasons. A root no location claims is listed under its path.
    static func unreadableLocations(from roots: [UnreadableRoot],
                                    locations: [LocationSummary]) -> [UnreadableLocation] {
        var reasonsByLocation = [[String]](repeating: [], count: locations.count)
        var unmatched: [UnreadableLocation] = []
        for root in roots {
            if let index = locationIndex(forPath: root.path, in: locations) {
                reasonsByLocation[index].append(root.reason)
            } else {
                unmatched.append(UnreadableLocation(id: root.path, label: root.path, reasons: [root.reason]))
            }
        }
        let matched = locations.enumerated().compactMap { index, location -> UnreadableLocation? in
            reasonsByLocation[index].isEmpty
                ? nil
                : UnreadableLocation(id: location.id, label: location.label, reasons: reasonsByLocation[index])
        }
        return matched + unmatched
    }

    /// `/Users/me/Downloads/a.zip` → `~/Downloads/a.zip` against `home`; any other path as is.
    static func displayPath(_ path: String, home: String) -> String {
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !base.isEmpty else { return path }
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~" + path.dropFirst(base.count) }
        return path
    }

    func displayPath(_ path: String) -> String {
        Self.displayPath(path, home: homeDirectory)
    }

    /// The folder a file sits in, as the user reads it (`~/Downloads`).
    func displayFolder(of path: String) -> String {
        displayPath((path as NSString).deletingLastPathComponent)
    }

    // MARK: - Scan

    /// `false` when a scan or a quarantine is already running (re-entrancy guard).
    @discardableResult
    func startScan() -> Bool {
        guard !isBusy else { return false }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
        // Set synchronously so a second call before the task starts is refused too.
        phase = .scanning
        return true
    }

    /// F2: Stop returns to `start` and discards results — including the previous scan's,
    /// which would otherwise look like this scan's outcome.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        guard phase == .scanning else { return }
        resetResults()
        progressTracker.reset()
        phase = .idle
    }

    private func performScan() async {
        resetResults()
        lastFailures = []
        actionError = nil
        isShowingQuarantine = false
        locationSummaries = locations.map { location in
            LocationSummary(id: location.id, label: location.label, roots: location.resolvedPaths())
        }
        let generation = progressTracker.start()
        // The engine's last report is exact (the final file always reports), but the hops that
        // carry reports to the main actor are unstructured Tasks that may land after the scan
        // returns — so the file count is tracked here, not read back from the tracker.
        let reported = OSAllocatedUnfairLock(initialState: 0)
        do {
            let outcome = try await scanner.scan(onProgress: { [weak self] progress in
                reported.withLock { $0 = max($0, progress.itemsProcessed) }
                Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
            })
            guard !Task.isCancelled else { return }
            let unreadable = Self.unreadableLocations(from: outcome.unreadableRoots, locations: locationSummaries)
            if !outcome.unreadableRoots.isEmpty,
               outcome.unreadableRoots.count >= locationSummaries.flatMap(\.roots).count {
                // Every root failed to open, so nothing was looked into and an empty list would
                // read as an all-clear. §6.3: the engine's own reason, nothing invented.
                let reason = outcome.unreadableRoots.first?.reason ?? ""
                phase = .failed(message: "None of the locations could be read. \(reason)"
                    .trimmingCharacters(in: .whitespaces))
                return
            }
            unreadableLocations = unreadable
            findings = outcome.findings
            selectedPaths = [] // never auto-select a quarantine target
            checkedFileCount = reported.withLock { $0 }
            currentGroupID = nil
            focusedPath = nil
            phase = .results
        } catch {
            guard !Task.isCancelled else { return }
            // §6.3: the engine's own reason, nothing invented.
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func resetResults() {
        findings = []
        selectedPaths = []
        currentGroupID = nil
        focusedPath = nil
        quarantineProgress = nil
        checkedFileCount = 0
        unreadableLocations = []
    }

    // MARK: - Review

    func enterReview() {
        guard phase == .results, !findings.isEmpty else { return }
        phase = .review
        if currentGroupID == nil || !findingGroups.contains(where: { $0.id == currentGroupID }) {
            currentGroupID = findingGroups.first?.id
            focusedPath = nil
        }
    }

    func backToResults() {
        guard phase == .review else { return }
        phase = .results
    }

    func selectGroup(_ id: String) {
        currentGroupID = id
        focusedPath = nil
    }

    func focusFinding(path: String) {
        focusedPath = path
    }

    func toggleSelection(for path: String) {
        guard findings.contains(where: { $0.path == path }) else { return }
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// Select All in the current group — an explicit user action; nothing is selected for you.
    func selectAllInCurrentGroup() {
        selectedPaths.formUnion((currentGroup?.findings ?? []).map(\.path))
    }

    func deselectAllInCurrentGroup() {
        for finding in currentGroup?.findings ?? [] {
            selectedPaths.remove(finding.path)
        }
    }

    // MARK: - Quarantine confirmation

    /// The one confirmation before anything moves (CF-1: Cancel is the default button). The
    /// count is the same number the review bar shows (CF-3). `nil` when nothing is selected.
    func quarantineConfirmation() -> ConfirmSheet.Model? {
        let selected = selectedFindings
        guard !selected.isEmpty, !isBusy else { return nil }
        let items = selected.map { finding in
            ConfirmItem(id: finding.path,
                        name: (finding.path as NSString).lastPathComponent,
                        size: finding.size)
        }
        return ConfirmSheet.Model(
            variant: .quarantine,
            count: selected.count,
            items: items,
            hue: Theme.Hue.protection,
            confirm: { [weak self] _ in self?.beginQuarantine() },
            cancel: { })
    }

    /// Starts the confirmed move from the sheet's synchronous callback.
    private func beginQuarantine() {
        Task { [weak self] in
            await self?.quarantineSelected()
        }
    }

    // MARK: - Quarantine

    /// Moves the confirmed selection into quarantine, one finding at a time with real
    /// progress. Re-entrant calls are refused while a quarantine runs. Every move goes
    /// through `QuarantineManager` (a tracked, reversible move); a file that moved but could
    /// not be recorded is reported as a failure and removed from the findings, because it is
    /// no longer at its original path.
    @discardableResult
    func quarantineSelected() async -> Bool {
        guard !isBusy else { return false }
        let toQuarantine = selectedFindings
        guard !toQuarantine.isEmpty else { return false }

        phase = .quarantining(selectedCount: toQuarantine.count)
        quarantineProgress = QuarantineProgress(attemptedCount: 0, totalCount: toQuarantine.count, currentPath: nil)
        lastFailures = []
        actionError = nil

        var succeeded = 0
        var failures: [QuarantineFailure] = []
        var movedPaths: Set<String> = []

        for (index, finding) in toQuarantine.enumerated() {
            quarantineProgress = QuarantineProgress(attemptedCount: index + 1,
                                                    totalCount: toQuarantine.count,
                                                    currentPath: finding.path)
            // Let the progress frame render between moves.
            await Task.yield()
            let name = (finding.path as NSString).lastPathComponent
            do {
                let quarantined = try quarantineManager.quarantine(finding)
                movedPaths.insert(finding.path)
                do {
                    try persist(quarantined)
                    succeeded += 1
                } catch {
                    // The file WAS moved — never report a clean success (nothing tracks it
                    // for restore), and never pretend it is still where it was.
                    failures.append(QuarantineFailure(
                        name: name,
                        reason: "Moved to quarantine, but SOS Mac couldn't save it for restore. Find it in the Quarantine folder."))
                }
            } catch {
                failures.append(QuarantineFailure(name: name, reason: Self.reason(for: error)))
            }
        }

        // Only what really moved leaves the findings; a failed file stays listed.
        findings.removeAll { movedPaths.contains($0.path) }
        selectedPaths.subtract(movedPaths)
        quarantinedRecords = Self.fetchRecords(from: modelContext)
        quarantineProgress = nil
        lastFailures = failures
        phase = .done(quarantinedCount: succeeded, failedCount: failures.count)
        return true
    }

    private static func reason(for error: Error) -> String {
        guard let quarantineError = error as? QuarantineError else { return error.localizedDescription }
        switch quarantineError {
        case .sourceFileMissing: return "The file is no longer at its original location."
        case .moveFailed(let detail): return "The file couldn't be moved: \(detail)"
        case .restoreTargetOccupied: return "Something already exists at the original location."
        }
    }

    // MARK: - Quarantine list

    func showQuarantine() {
        guard !isBusy else { return }
        isShowingQuarantine = true
    }

    func hideQuarantine() {
        isShowingQuarantine = false
    }

    /// Re-reads the persisted records (the list can change outside this view model).
    func refreshQuarantineRecords() {
        guard !isBusy else { return }
        quarantinedRecords = Self.fetchRecords(from: modelContext)
    }

    /// Puts a quarantined file back at its original path and drops its record. A failed
    /// restore keeps the record (the file is still in quarantine) and says why.
    @discardableResult
    func restore(_ record: QuarantineRecord) -> Bool {
        guard !isBusy else { return false }
        let name = (record.originalPath as NSString).lastPathComponent
        let file = QuarantinedFile(
            originalPath: record.originalPath,
            quarantinePath: record.quarantinePath,
            threatIdentifier: record.threatIdentifier,
            quarantinedAt: record.quarantinedAt
        )
        do {
            try quarantineManager.restore(file)
        } catch {
            actionError = ActionError(title: "Couldn't restore \(name)", text: Self.reason(for: error))
            return false
        }
        modelContext.delete(record)
        do {
            try modelContext.save()
            actionError = nil
        } catch {
            actionError = ActionError(
                title: "Restored \(name), but the quarantine list didn't update",
                text: error.localizedDescription)
        }
        quarantinedRecords = Self.fetchRecords(from: modelContext)
        return true
    }

    func dismissActionError() {
        actionError = nil
    }

    // MARK: - SwiftData

    private func persist(_ file: QuarantinedFile) throws {
        if let persistQuarantine {
            try persistQuarantine(file)
            return
        }
        let record = QuarantineRecord(
            originalPath: file.originalPath,
            quarantinePath: file.quarantinePath,
            threatIdentifier: file.threatIdentifier,
            quarantinedAt: file.quarantinedAt
        )
        modelContext.insert(record)
        try modelContext.save()
    }

    private static func fetchRecords(from modelContext: ModelContext) -> [QuarantineRecord] {
        let descriptor = FetchDescriptor<QuarantineRecord>(sortBy: [SortDescriptor(\.quarantinedAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Fixtures (Debug builds only)

#if DEBUG
    /// The launch-hook half of the fixture convention: applies the state named by
    /// `SOSMAC_UITEST_SCREEN`/`SOSMAC_UITEST_STATE` when fixtures are on. `quarantine` is the
    /// sub-screen, which is not a lifecycle state.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .protection, let raw = hooks.state else { return }
        if raw == "quarantine" {
            loadFixture(.start)
            quarantinedRecords = UITestFixtures.protectionQuarantineRecords(count: 9)
            isShowingQuarantine = true
        } else if let state = LifecycleState(rawValue: raw) {
            loadFixture(state)
        }
    }

    /// Loads one lifecycle state from the fictional sample data. Never reads the real file
    /// system or the real quarantine list.
    func loadFixture(_ state: LifecycleState) {
        homeDirectory = UITestFixtures.home
        locationSummaries = UITestFixtures.protectionLocations.map { location in
            LocationSummary(id: location.id, label: location.label, roots: location.resolvedPaths())
        }
        resetResults()
        lastFailures = []
        actionError = nil
        isShowingQuarantine = false
        progressTracker.reset()
        quarantinedRecords = UITestFixtures.protectionQuarantineRecords(count: 2)

        switch state {
        case .start:
            phase = .idle

        case .scanning:
            phase = .scanning
            // A steady fixture clock gives the ETA tracker a believable rate: 9,700 of
            // 19,388 files in 90 s → about two minutes left. Nothing here is measured.
            let clock = FixtureClock()
            progressTracker = ScanProgressTracker(now: { clock.now })
            let generation = progressTracker.start()
            clock.now = clock.now.addingTimeInterval(90)
            progressTracker.record(
                ScanProgress(itemsProcessed: 9_700,
                             totalItems: UITestFixtures.protectionFileCount,
                             currentPath: "/Library/LaunchDaemons/com.example.updater.plist"),
                generation: generation)

        case .results:
            applyFixtureFindings()

        case .empty:
            checkedFileCount = UITestFixtures.protectionFileCount
            phase = .results

        case .review:
            applyFixtureFindings()
            enterReview()
            focusedPath = findings.first?.path

        case .cleaning:
            applyFixtureFindings()
            selectedPaths = Set(findings.map(\.path))
            phase = .quarantining(selectedCount: selectedPaths.count)
            quarantineProgress = QuarantineProgress(attemptedCount: 1,
                                                    totalCount: selectedPaths.count,
                                                    currentPath: findings.first?.path)

        case .done:
            // As if the one finding had just been quarantined: it is gone from the findings
            // and joins the two records already in quarantine.
            quarantinedRecords = UITestFixtures.protectionQuarantineRecords(count: 2, includingJustQuarantined: true)
            phase = .done(quarantinedCount: 1, failedCount: 0)

        case .error:
            phase = .failed(message: "The folder “LaunchDaemons” couldn’t be opened because you don’t have permission to view it.")
        }
    }

    private func applyFixtureFindings() {
        findings = UITestFixtures.protectionFindings
        selectedPaths = []
        checkedFileCount = UITestFixtures.protectionFileCount
        phase = .results
    }

    /// Test-only: the completed-scan state over arbitrary findings (the paths need not exist).
    func loadFixtureResults(_ newFindings: [ThreatFinding], checkedFileCount count: Int = 0) {
        findings = newFindings
        selectedPaths = []
        checkedFileCount = count
        unreadableLocations = []
        currentGroupID = nil
        focusedPath = nil
        lastFailures = []
        phase = .results
    }

    private final class FixtureClock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }
#endif
}

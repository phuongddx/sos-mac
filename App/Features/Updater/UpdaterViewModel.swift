import AppKit
import Foundation
import Observation
import CleanCore

/// Updater on the shared lifecycle frame (plan PR 10, spec §5.8): read-only — nothing is
/// ever installed. One `Phase` enum, a pure `lifecycle` mapping, Debug-only fixture states.
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `idle` | "See which apps have updates" · **Check** (no check runs on its own — OD-10) |
/// | `scanning` | `checking` | "Checking «App»…" · "k of N apps" · **Stop** (discards: back to `start`, F2) |
/// | `results` | `results` | groups: Updates available · Update in the App Store · Up to date · No update feed (+ Couldn't check; Not checked yet only before a check) |
/// | `empty` | `empty` | "All apps are up to date" — only when every app is checkable **and** was checked (no App Store, no-feed or failed row) |
/// | `error` | `failed(message:)` | "Couldn't check for updates" · Try Again |
///
/// **Stop** returns to `start` and discards partial results (spec §4.1 F2: a partial list
/// would look complete). **Check Again** (a full check) re-reads the installed apps first, so
/// installed versions are fresh and apps installed or removed since appear; **Try Again**
/// (failed feeds only) keeps every result already in hand and does not re-read.
///
/// One feed failing is **not** a phase of its own (OD-10 / D3): the row gets a
/// `checkError`, reads "Couldn't check", and a banner offers Try Again. A failed check is
/// never rendered as "Up to date".
///
/// Safety: the only network call is the injected `feed` (production: the Sparkle appcast
/// check). Tests and fixtures inject their own; nothing here installs, moves or deletes.
@MainActor
@Observable
final class UpdaterViewModel {

    // MARK: - Types

    struct AppUpdateRow: Identifiable, Equatable {
        let app: InstalledApp
        /// The newest version the app's feed reported — a real feed result, or `nil`.
        var latestVersion: String?
        /// The installed version `latestVersion` was compared with: the marketing version, or
        /// — for a feed that only carries a build number — the build number (D3). `nil` before
        /// a verdict; `UpdaterGroups` then falls back to the marketing version.
        var installedBasis: String?
        /// Busy flag for the row's own feed request (drives the spinner).
        var isChecking = false
        /// Why the last check of this row failed (OD-10); cleared by the next attempt.
        var checkError: String?
        var id: String { app.id }

        init(app: InstalledApp, latestVersion: String? = nil, installedBasis: String? = nil,
             isChecking: Bool = false, checkError: String? = nil) {
            self.app = app
            self.latestVersion = latestVersion
            self.installedBasis = installedBasis
            self.isChecking = isChecking
            self.checkError = checkError
        }

        /// Has a feed and an installed version, so a check can say something about it.
        var isCheckable: Bool { app.sparkleFeedURL != nil && app.version != nil }
        /// The check reached a verdict for this row — a feed result or a failure.
        var hasVerdict: Bool { latestVersion != nil || checkError != nil }
    }

    /// The state machine contract the shared frame maps from (spec §5.8, normative).
    enum Phase: Equatable {
        case idle
        case checking
        case results
        case empty
        /// The whole check failed: every feed that was tried failed.
        case failed(message: String)
    }

    /// The network seam: the newest release a feed lists (marketing version and/or build
    /// number), `nil` when the feed carries no version. `installedVersion` is the app's
    /// marketing version, for test closures that answer relative to it; the comparison itself
    /// happens in the view model (`AppcastRelease.verdict`). Production runs the Sparkle
    /// appcast check; tests and fixtures inject their own, so no test ever reaches the network.
    typealias FeedFunction = @Sendable (_ feedURL: URL, _ installedVersion: String) async throws -> AppcastRelease?

    /// Why a feed that answered still proves nothing about the app (shown as "Couldn't check").
    enum FeedError: LocalizedError {
        case noVersion
        /// The feed's versions and the app's are not the same kind (build-only feed, app
        /// without `CFBundleVersion`): comparing would be a guess, so fail closed (D3).
        case notComparable

        var errorDescription: String? {
            switch self {
            case .noVersion: "The update feed has no version information."
            case .notComparable: "The update feed's version can't be compared with this app's."
            }
        }
    }

    // MARK: - State

    private(set) var phase: Phase = .idle
    private(set) var rows: [AppUpdateRow] = []
    /// PR 3 (spec §6.6): rows live in the store; `loadApps` is first-visit-only.
    private(set) var hasLoadedApps = false
    let progressTracker = ScanProgressTracker()

    private let enumerate: () -> [InstalledApp]
    private let feed: FeedFunction
    private let iconLoader: @MainActor (String) -> NSImage?
    private var checkTask: Task<Void, Never>?
    /// Bumped by every start/stop so a superseded run can't touch rows or the phase of the
    /// run that replaced it (a cancelled feed request still resumes after `await`).
    private var checkGeneration = 0
    /// OD-12: one icon load per app.
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    convenience init(enumerator: InstalledAppsEnumerator = InstalledAppsEnumerator(),
                     feed: @escaping FeedFunction = UpdaterViewModel.liveFeed,
                     iconLoader: @escaping @MainActor (String) -> NSImage? = UpdaterViewModel.liveIcon) {
        self.init(enumerate: { enumerator.enumerate() }, feed: feed, iconLoader: iconLoader)
    }

    /// The installed-apps seam itself, for tests that need the list to change between checks.
    init(enumerate: @escaping () -> [InstalledApp],
         feed: @escaping FeedFunction = UpdaterViewModel.liveFeed,
         iconLoader: @escaping @MainActor (String) -> NSImage? = UpdaterViewModel.liveIcon) {
        self.enumerate = enumerate
        self.feed = feed
        self.iconLoader = iconLoader
    }

    // MARK: - Live seams

    static let liveFeed: FeedFunction = { feedURL, _ in
        try await SparkleAppcastChecker.latestRelease(feedURL: feedURL)
    }

    /// OD-12: the app's own icon, or `nil` when the bundle is not on disk (the letter tile
    /// then stands in — also what the fictional fixture apps get).
    static let liveIcon: @MainActor (String) -> NSImage? = { path in
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    // MARK: - Lifecycle mapping

    /// The pure mapping the shared frame renders from.
    var lifecycle: LifecycleState {
        switch phase {
        case .idle: .start
        case .checking: .scanning
        case .results: .results
        case .empty: .empty
        case .failed: .error
        }
    }

    /// `ModuleStore.isScanning(.updater)` reads this (the sidebar busy dot).
    var isCheckingAll: Bool { phase == .checking }

    // MARK: - Derived

    func isUpdateAvailable(_ row: AppUpdateRow) -> Bool {
        if case .updateAvailable = UpdaterGroups.status(of: row) { return true }
        return false
    }

    var hasAnyUpdate: Bool { rows.contains(where: isUpdateAvailable) }
    var updatesAvailableCount: Int { rows.count(where: isUpdateAvailable) }
    var groups: [UpdaterGroup] { UpdaterGroups.groups(for: rows) }
    var failedRows: [AppUpdateRow] { rows.filter { $0.checkError != nil } }
    var hasCheckError: Bool { rows.contains { $0.checkError != nil } }
    /// Apps the check reached a verdict for (a real feed result or a failure).
    var checkedCount: Int { rows.count(where: \.hasVerdict) }
    var checkableCount: Int { rows.count(where: \.isCheckable) }
    var appStoreCount: Int { rows.count { UpdaterGroups.status(of: $0) == .appStore } }
    var upToDateCount: Int { rows.count { UpdaterGroups.status(of: $0) == .upToDate } }
    var noFeedCount: Int { rows.count { UpdaterGroups.status(of: $0) == .noFeed } }

    /// The row whose feed request is in flight.
    var currentlyCheckingRow: AppUpdateRow? { rows.first { $0.isChecking } }

    /// OD-12.
    func icon(for app: InstalledApp) -> NSImage? {
        if let cached = iconCache[app.bundlePath] { return cached }
        guard let loaded = iconLoader(app.bundlePath) else { return nil }
        iconCache[app.bundlePath] = loaded
        return loaded
    }

    // MARK: - Load

    /// First-visit-only: lists the installed apps (a local read — no network, OD-10).
    /// `.task` re-fires whenever the view reappears; rebuilding would drop every result.
    /// A full check (Check / Check Again) re-reads the list itself (`begin(only: nil)`).
    func loadApps() {
        guard !hasLoadedApps, phase == .idle else { return }
        enumerateApps()
    }

    private func enumerateApps() {
        hasLoadedApps = true
        rows = enumerate()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppUpdateRow(app: $0) }
    }

    // MARK: - Check

    /// Starts a check of every app that has a feed, after re-reading the installed apps (so
    /// installed versions are current and new or removed apps are reflected). Refused
    /// (returns `false`) while one is already running or when there are no apps. A second
    /// start can never interleave its progress with a running one.
    @discardableResult
    func startCheck() -> Bool {
        begin(only: nil)
    }

    /// "Try Again" on the failed-check banner: re-checks only the rows whose feed failed,
    /// keeping every result already in hand.
    @discardableResult
    func retryFailedChecks() -> Bool {
        let failed = Set(failedRows.map(\.id))
        guard !failed.isEmpty else { return false }
        return begin(only: failed)
    }

    private func begin(only ids: Set<String>?) -> Bool {
        guard phase != .checking else { return false }
        // A full check starts from what is installed now; a retry keeps the rows in hand.
        if ids == nil {
            enumerateApps()
            if rows.isEmpty { phase = .idle }
        }
        guard !rows.isEmpty else { return false }
        let targetIDs = rows.filter { $0.isCheckable && (ids?.contains($0.id) ?? true) }.map(\.id)
        for index in rows.indices where ids == nil || ids!.contains(rows[index].id) {
            rows[index].latestVersion = nil
            rows[index].installedBasis = nil
            rows[index].checkError = nil
            rows[index].isChecking = false
        }
        checkTask?.cancel()
        checkGeneration += 1
        let generation = checkGeneration
        phase = .checking
        checkTask = Task { [weak self] in
            await self?.runCheck(targetIDs: targetIDs, generation: generation)
        }
        return true
    }

    /// Stop (spec §4.1 F2): back to the start, discarding partial results — a half-checked list
    /// under an "N apps checked" subtitle would look like an outcome. The app list itself
    /// stays (Stop is not an uninstall); Check is one click away.
    func stopCheck() {
        guard phase == .checking else { return }
        checkTask?.cancel()
        checkTask = nil
        checkGeneration += 1
        progressTracker.reset()
        for index in rows.indices {
            rows[index].latestVersion = nil
            rows[index].installedBasis = nil
            rows[index].checkError = nil
            rows[index].isChecking = false
        }
        phase = .idle
    }

    private func runCheck(targetIDs: [String], generation: Int) async {
        let progressGeneration = progressTracker.start()
        for (position, id) in targetIDs.enumerated() {
            guard !Task.isCancelled, generation == checkGeneration else { return }
            guard let index = rows.firstIndex(where: { $0.id == id }),
                  let feedURL = rows[index].app.sparkleFeedURL,
                  let installed = rows[index].app.version else { continue }
            rows[index].isChecking = true
            progressTracker.record(
                ScanProgress(itemsProcessed: position, totalItems: targetIDs.count, currentPath: rows[index].app.name),
                generation: progressGeneration)

            let outcome: Result<AppcastRelease?, Error>
            do {
                outcome = .success(try await feed(feedURL, installed))
            } catch {
                outcome = .failure(error)
            }
            // A stopped or superseded run must not write: Stop already cleared the busy flags.
            guard !Task.isCancelled, generation == checkGeneration else { return }

            if let writeIndex = rows.firstIndex(where: { $0.id == id }) {
                rows[writeIndex].isChecking = false
                switch outcome {
                case .success(let release?):
                    // Marketing vs marketing, build vs build; an incomplete pair is a failure.
                    let app = rows[writeIndex].app
                    if let verdict = release.verdict(installedVersion: app.version, installedBuild: app.buildVersion) {
                        rows[writeIndex].latestVersion = verdict.latestVersion
                        rows[writeIndex].installedBasis = verdict.installedBasis
                    } else {
                        rows[writeIndex].checkError = FeedError.notComparable.localizedDescription
                    }
                case .success(nil):
                    // A feed with no version proves nothing — not "Up to date".
                    rows[writeIndex].checkError = FeedError.noVersion.localizedDescription
                case .failure(let error):
                    // OD-10 / D3: the failure stays with its row; the rest of the list goes on.
                    rows[writeIndex].checkError = error.localizedDescription
                }
            }
        }
        progressTracker.record(
            ScanProgress(itemsProcessed: targetIDs.count, totalItems: targetIDs.count, currentPath: nil),
            generation: progressGeneration)
        finishCheck()
    }

    /// Chooses the phase a finished check lands in — only ever from real results.
    private func finishCheck() {
        let checkable = rows.filter(\.isCheckable)
        let failures = checkable.filter { $0.checkError != nil }
        if !checkable.isEmpty, failures.count == checkable.count {
            let reason = failures.first?.checkError ?? "No update feed answered."
            phase = .failed(message: checkable.count == 1
                ? reason
                : "None of the \(checkable.count) update feeds answered. \(reason)")
            return
        }
        // "All apps are up to date" needs every app checkable and checked (F3): every row a
        // real verdict, at least one up-to-date result, no newer version, no failed feed,
        // nothing left to open in the App Store and no app without a readable feed.
        let anyUpdate = rows.contains(where: isUpdateAvailable)
        let anyUpToDate = rows.contains { UpdaterGroups.status(of: $0) == .upToDate }
        let fullyChecked = checkedCount == checkableCount
        phase = (!anyUpdate && failures.isEmpty && anyUpToDate && appStoreCount == 0 && noFeedCount == 0 && fullyChecked)
            ? .empty : .results
    }

    // MARK: - Fixtures (Debug builds only)

#if DEBUG
    /// Loads one lifecycle state from the fictional sample data (`UITestFixtures`). Called
    /// from the screen's `.task` when `SOSMAC_UITEST_FIXTURES=1` names this screen. It never
    /// reads the real file system, the real app list or the network (the feed is not called).
    ///
    /// States: `start`, `scanning`, `results`, `empty`, `error` (the whole check failed) and
    /// `checkfailed` (results with one feed that failed — OD-10).
    func loadFixture(state: String) {
        switch state {
        case "start":
            applyFixture(UITestFixtures.updaterApps, phase: .idle)
        case "scanning":
            applyFixture(UITestFixtures.updaterApps, phase: .idle)
            let targets = rows.filter(\.isCheckable).map(\.id)
            let doneCount = 2
            for id in targets.prefix(doneCount) { applyFixtureVerdict(id: id) }
            if let currentID = targets.dropFirst(doneCount).first,
               let index = rows.firstIndex(where: { $0.id == currentID }) {
                rows[index].isChecking = true
                let generation = progressTracker.start()
                progressTracker.record(
                    ScanProgress(itemsProcessed: doneCount, totalItems: targets.count, currentPath: rows[index].app.name),
                    generation: generation)
            }
            phase = .checking
        case "results":
            applyFixture(UITestFixtures.updaterApps, phase: .results)
            for id in rows.map(\.id) { applyFixtureVerdict(id: id) }
        case "checkfailed":
            applyFixture(UITestFixtures.updaterApps, phase: .results)
            for id in rows.map(\.id) { applyFixtureVerdict(id: id) }
            if let index = rows.firstIndex(where: { UpdaterGroups.status(of: $0) == .upToDate }) {
                rows[index].latestVersion = nil
                rows[index].checkError = "The update feed didn’t answer in time."
            }
        case "empty":
            applyFixture(UITestFixtures.updaterEmptyApps, phase: .empty)
            // Every feed answers with the installed version itself: nothing newer anywhere.
            for index in rows.indices { rows[index].latestVersion = rows[index].app.version }
        case "error":
            applyFixture(UITestFixtures.updaterApps, phase: .idle)
            for index in rows.indices where rows[index].isCheckable {
                rows[index].checkError = "The network connection was lost."
            }
            phase = .failed(message: "None of the \(rows.count(where: \.isCheckable)) update feeds answered. The network connection was lost.")
        default:
            break
        }
    }

    /// The launch-hook half of the fixture convention.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .updater, let state = hooks.state else { return }
        loadFixture(state: state.lowercased())
    }

    /// Test-only: the rows over arbitrary apps (no real file system needed), loaded the way a
    /// first `loadApps()` would leave them.
    func loadFixtureApps(_ installed: [InstalledApp]) {
        applyFixture(installed, phase: .idle)
    }

    private func applyFixture(_ installed: [InstalledApp], phase newPhase: Phase) {
        checkTask?.cancel()
        checkTask = nil
        checkGeneration += 1
        progressTracker.reset()
        rows = installed
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppUpdateRow(app: $0) }
        hasLoadedApps = true
        phase = newPhase
    }

    /// Gives a fixture row the verdict its fixture kind describes — a made-up feed answer.
    private func applyFixtureVerdict(id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              let latest = UITestFixtures.updaterLatestVersion(forBundlePath: rows[index].app.bundlePath) else { return }
        rows[index].latestVersion = latest
    }
#endif
}

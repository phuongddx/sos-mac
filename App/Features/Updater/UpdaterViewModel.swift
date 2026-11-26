import Foundation
import Observation
import CleanCore

@MainActor
@Observable
final class UpdaterViewModel {
    struct AppUpdateRow: Identifiable {
        let app: InstalledApp
        var latestVersion: String?
        var isChecking = false
        var id: String { app.id }
    }

    private(set) var rows: [AppUpdateRow] = []
    private(set) var isCheckingAll = false
    /// PR 3 (spec §6.6): rows live in the store; `loadApps` is first-visit-only
    /// and the auto-check runs once per session, not on every re-visit.
    private(set) var hasLoadedApps = false
    private(set) var hasAutoChecked = false
    let progressTracker = ScanProgressTracker()
    private let enumerator: InstalledAppsEnumerator

    init(enumerator: InstalledAppsEnumerator = InstalledAppsEnumerator()) {
        self.enumerator = enumerator
    }

    var hasAnyUpdate: Bool {
        rows.contains { row in
            guard let latest = row.latestVersion, let installed = row.app.version else { return false }
            return latest.compare(installed, options: .numeric) == .orderedDescending
        }
    }

    func loadApps() {
        guard !hasLoadedApps else { return }
        hasLoadedApps = true
        rows = enumerator.enumerate()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppUpdateRow(app: $0) }
    }

    /// The one automatic check per session (PR 3); explicit checks still go
    /// through `checkAll()` from the buttons.
    func autoCheckIfNeeded() async {
        guard !hasAutoChecked else { return }
        hasAutoChecked = true
        await checkAll()
    }

    /// Reachable from three places (`.task`, the empty state's action, and
    /// "Check Again"), so two overlapping runs would otherwise both call
    /// `progressTracker.start()` and interleave their `record(_:)` calls,
    /// making the progress bar jump backwards.
    func checkAll() async {
        guard !isCheckingAll else { return }
        isCheckingAll = true
        defer { isCheckingAll = false }

        let generation = progressTracker.start()
        for index in rows.indices {
            await checkSingle(at: index)
            guard rows.indices.contains(index) else { continue }
            progressTracker.record(
                ScanProgress(itemsProcessed: index + 1, totalItems: rows.count, currentPath: rows[index].app.name),
                generation: generation
            )
        }
    }

    func checkSingle(at index: Int) async {
        guard rows.indices.contains(index) else { return }
        guard let feedURL = rows[index].app.sparkleFeedURL, let installed = rows[index].app.version else { return }
        rows[index].isChecking = true
        defer { rows[index].isChecking = false }
        do {
            if let result = try await SparkleAppcastChecker.checkForUpdate(feedURL: feedURL, installedVersion: installed) {
                rows[index].latestVersion = result.latestVersion
            }
        } catch {
            // A single feed failing (network error, malformed XML) shouldn't
            // block checking the rest of the list.
        }
    }

    func isUpdateAvailable(_ row: AppUpdateRow) -> Bool {
        guard let latest = row.latestVersion, let installed = row.app.version else { return false }
        return latest.compare(installed, options: .numeric) == .orderedDescending
    }
}

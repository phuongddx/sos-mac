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
        rows = enumerator.enumerate()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppUpdateRow(app: $0) }
    }

    func checkAll() async {
        for index in rows.indices {
            await checkSingle(at: index)
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

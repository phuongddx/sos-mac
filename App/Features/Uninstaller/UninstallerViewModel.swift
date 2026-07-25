import Foundation
import Observation
import CleanCore

@MainActor
@Observable
final class UninstallerViewModel {
    struct AppRow: Identifiable {
        let app: InstalledApp
        var id: String { app.id }
    }

    enum Phase: Equatable {
        case browsing
        case inspecting(bundleID: String)
        case removed(appName: String, reclaimedBytes: Int64)
    }

    private(set) var phase: Phase = .browsing
    private(set) var apps: [AppRow] = []
    private(set) var associatedItems: [ScanItem] = []
    var selectedPaths: Set<String> = []
    private(set) var errorMessage: String?
    /// Non-nil while a bundle walk is in flight — lets the view disable the
    /// row's Inspect button so a second tap (on the same or a different row)
    /// can't race a first scan and land a stale/mismatched associated-file
    /// list.
    private(set) var inspectingBundleID: String?

    private let enumerator: InstalledAppsEnumerator

    init(enumerator: InstalledAppsEnumerator = InstalledAppsEnumerator()) {
        self.enumerator = enumerator
    }

    func loadApps() {
        apps = enumerator.enumerate()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(AppRow.init)
    }

    func inspect(_ row: AppRow) async {
        guard inspectingBundleID == nil else { return }
        errorMessage = nil
        inspectingBundleID = row.app.bundleIdentifier
        defer { inspectingBundleID = nil }

        let uninstaller = AppUninstaller(appBundlePath: row.app.bundlePath, bundleIdentifier: row.app.bundleIdentifier)
        do {
            associatedItems = try await uninstaller.scan()
            selectedPaths = Set(associatedItems.map(\.path))
            phase = .inspecting(bundleID: row.app.bundleIdentifier)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmUninstall(appName: String) async {
        guard case .inspecting(let bundleID) = phase else { return }
        let toRemove = associatedItems.filter { selectedPaths.contains($0.path) }
        // clean(_:) is the shared trash-routed extension method and needs no
        // instance state — DefaultCleaner avoids constructing an AppUninstaller
        // with a throwaway/empty bundle path just to reach it.
        do {
            let result = try await DefaultCleaner().clean(toRemove)
            apps.removeAll { $0.app.bundleIdentifier == bundleID }
            phase = .removed(appName: appName, reclaimedBytes: result.reclaimedBytes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelInspection() {
        phase = .browsing
        associatedItems = []
        selectedPaths = []
    }

    func backToBrowsing() {
        phase = .browsing
    }
}

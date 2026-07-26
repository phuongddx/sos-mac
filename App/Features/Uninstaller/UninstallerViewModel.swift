import Foundation
import Observation
import CleanCore

@MainActor
@Observable
final class UninstallerViewModel {
    struct AppRow: Identifiable {
        let app: InstalledApp
        var inspectedSize: Int64?
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
    let progressTracker = ScanProgressTracker()
    private(set) var isInspectingAll = false

    private let enumerator: InstalledAppsEnumerator
    private var inspectAllTask: Task<Void, Never>?
    /// Bumped by every start/cancel so a superseded Inspect-All can't clear
    /// `isInspectingAll` out from under the run that replaced it.
    private var inspectAllGeneration = 0

    init(enumerator: InstalledAppsEnumerator = InstalledAppsEnumerator()) {
        self.enumerator = enumerator
    }

    func loadApps() {
        // `.task` re-fires whenever the view reappears; rebuilding `apps`
        // mid-Inspect-All would throw away every size already computed and
        // desync the run from the list it's writing back into.
        guard !isInspectingAll else { return }
        apps = enumerator.enumerate()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { AppRow(app: $0) }
    }

    var totalInspectedBytes: Int64 {
        apps.compactMap(\.inspectedSize).reduce(0, +)
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

    /// Proactively runs the same per-app `AppUninstaller.scan()` the
    /// existing per-row "Inspect" button already uses, for every installed
    /// app in order, caching each app's total reclaimable size onto its row.
    /// One app's scan failing (`try?` → `nil`) doesn't abort the rest — same
    /// partial-failure handling every other batch operation in this codebase
    /// already uses. Purely additive: doesn't select anything, doesn't
    /// delete anything, and doesn't touch the existing per-row `inspect(_:)`
    /// flow used to actually review and confirm an uninstall.
    ///
    /// Cancellation is checked between apps, not inside a single app's bundle
    /// walk — `AppUninstaller.scan()` is left untouched, so one very large
    /// app's walk still runs to completion before the loop can bail.
    func startInspectAll() {
        inspectAllTask?.cancel()
        inspectAllGeneration += 1
        let generation = inspectAllGeneration
        isInspectingAll = true
        inspectAllTask = Task { [weak self] in
            await self?.inspectAll(generation: generation)
        }
    }

    func cancelInspectAll() {
        inspectAllTask?.cancel()
        inspectAllTask = nil
        inspectAllGeneration += 1
        isInspectingAll = false
        progressTracker.reset()
    }

    private func inspectAll(generation: Int) async {
        let progressGeneration = progressTracker.start()
        // Only the newest run owns the flag: a superseded run resuming late
        // must not report "finished" for the one that replaced it.
        defer { if generation == inspectAllGeneration { isInspectingAll = false } }

        // Snapshot the identifiers up front so the denominator is stable, then
        // re-resolve each row by bundle identifier before writing back — a
        // mid-loop mutation of `apps` can't then land a size on the wrong row
        // or index out of bounds.
        let bundleIdentifiers = apps.map(\.app.bundleIdentifier)

        for (index, bundleIdentifier) in bundleIdentifiers.enumerated() {
            guard !Task.isCancelled else { return }
            guard let currentIndex = apps.firstIndex(where: { $0.app.bundleIdentifier == bundleIdentifier }) else { continue }
            let row = apps[currentIndex]

            let uninstaller = AppUninstaller(appBundlePath: row.app.bundlePath, bundleIdentifier: row.app.bundleIdentifier)
            let items = try? await uninstaller.scan()
            guard !Task.isCancelled else { return }

            if let items, let writeIndex = apps.firstIndex(where: { $0.app.bundleIdentifier == bundleIdentifier }) {
                apps[writeIndex].inspectedSize = items.reduce(0) { $0 + $1.size }
            }
            progressTracker.record(
                ScanProgress(itemsProcessed: index + 1, totalItems: bundleIdentifiers.count, currentPath: row.app.name),
                generation: progressGeneration
            )
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

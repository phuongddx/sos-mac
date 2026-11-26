import AppKit
import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Uninstaller view-model tests (plan PR 9): the D1 "At least" rule, per-row inspect
/// errors (N4), pre-selection, the inspect re-entrancy guard, the running-app check
/// (OD-9), Measure All, the lifecycle mapping and a real trash-routed uninstall. Real
/// removals follow `ProgressiveCleanerTests`: real temp files, the real trash route, no
/// debris left in the user's Trash. Fixture paths under `/Users/sample` never reach the
/// cleaner.
@Suite("UninstallerViewModel")
@MainActor
struct UninstallerViewModelTests {

    // MARK: - Fixtures

    private struct InspectFailure: LocalizedError {
        var errorDescription: String? { "Couldn’t read its Library folders." }
    }

    private nonisolated static func app(_ name: String, appStore: Bool = false) -> InstalledApp {
        InstalledApp(name: name,
                     bundleIdentifier: "com.test.\(name.lowercased())",
                     version: "1.0",
                     sparkleFeedURL: nil,
                     bundlePath: "/Applications/\(name).app",
                     isAppStoreDistributed: appStore)
    }

    /// The bundle (a walked directory), one associated file and two associated folders —
    /// what the engine reports for an installed app (D1).
    private nonisolated static func items(for app: InstalledApp) -> [ScanItem] {
        [
            ScanItem(path: app.bundlePath, size: 1_000_000, kind: .directory, sourceLabel: "Application bundle"),
            ScanItem(path: "/Users/sample/Library/Preferences/\(app.bundleIdentifier).plist", size: 2_000, kind: .file,
                     sourceLabel: "Associated with \(app.bundleIdentifier)"),
            ScanItem(path: "/Users/sample/Library/Caches/\(app.bundleIdentifier)", size: 64, kind: .directory,
                     sourceLabel: "Associated with \(app.bundleIdentifier)"),
            ScanItem(path: "/Users/sample/Library/Application Support/\(app.name)", size: 64, kind: .directory,
                     sourceLabel: "Associated with \(app.bundleIdentifier)"),
        ]
    }

    private static func makeViewModel(
        apps: [InstalledApp],
        inspect: @escaping UninstallerViewModel.InspectFunction = { app in UninstallerViewModelTests.items(for: app) },
        isRunning: @escaping @MainActor (String) -> Bool = { _ in false }
    ) -> UninstallerViewModel {
        let viewModel = UninstallerViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: []),
            inspect: inspect,
            isRunning: isRunning,
            iconLoader: { _ in nil })
        viewModel.loadFixtureApps(apps)
        return viewModel
    }

    private func wait<T: Equatable>(until expected: T, _ value: () -> T, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if value() == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return value() == expected
    }

    /// Holds an inspect open until released — the re-entrancy test's gate.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    // MARK: - D1: "At least"

    @Test("“At least” appears only when a directory is selected")
    func atLeastOnlyWithADirectory() async {
        let alpha = Self.app("Alpha")
        let viewModel = Self.makeViewModel(apps: [alpha])
        _ = await viewModel.inspect(viewModel.apps[0])
        #expect(viewModel.phase == .reviewing(bundleID: alpha.bundleIdentifier))

        // Everything selected includes two associated folders → "at least".
        #expect(viewModel.selectionIncludesUnmeasuredFolder)
        #expect(viewModel.selectedSizeText.hasPrefix("at least "))
        // Folders add nothing: the bytes are the bundle plus the plist.
        #expect(viewModel.selectedMeasuredBytes == 1_002_000)

        // Only files / the bundle selected → a plain, exact size.
        viewModel.deselectAll()
        viewModel.toggleSelection(path: alpha.bundlePath)
        viewModel.toggleSelection(path: "/Users/sample/Library/Preferences/com.test.alpha.plist")
        #expect(!viewModel.selectionIncludesUnmeasuredFolder)
        #expect(!viewModel.selectedSizeText.lowercased().contains("at least"))
        #expect(viewModel.selectedMeasuredBytes == 1_002_000)

        // A folder alone has no measured size at all.
        viewModel.deselectAll()
        viewModel.toggleSelection(path: "/Users/sample/Library/Caches/com.test.alpha")
        #expect(viewModel.selectionIncludesUnmeasuredFolder)
        #expect(viewModel.selectedMeasuredBytes == 0)
        #expect(viewModel.selectedSizeText == "size not measured")
    }

    @Test("the app bundle is a directory but its size is real; associated folders are not measured")
    func bundleIsMeasuredFoldersAreNot() async {
        let alpha = Self.app("Alpha")
        let viewModel = Self.makeViewModel(apps: [alpha])
        _ = await viewModel.inspect(viewModel.apps[0])

        let all = viewModel.associatedItems
        let bundle = all.first { $0.path == alpha.bundlePath }
        #expect(bundle.map(viewModel.isUnmeasuredFolder) == false)
        #expect(viewModel.unmeasuredFolderCount == 2)
        // The row's size is real bytes only, with the folder count kept for "At least".
        #expect(viewModel.apps[0].inspectedSize == 1_002_000)
        #expect(viewModel.apps[0].unmeasuredFolderCount == 2)
    }

    // MARK: - Pre-selection

    @Test("pre-selection after an inspect is every item found")
    func preSelectionIsAllItems() async {
        let alpha = Self.app("Alpha")
        let viewModel = Self.makeViewModel(apps: [alpha])
        _ = await viewModel.inspect(viewModel.apps[0])

        #expect(viewModel.selectedPaths == Set(viewModel.associatedItems.map(\.path)))
        #expect(viewModel.selectedItems.count == 4)

        viewModel.deselectAll()
        #expect(viewModel.selectedPaths.isEmpty)
        viewModel.selectAll()
        #expect(viewModel.selectedPaths.count == 4)
    }

    // MARK: - inspectError (N4)

    @Test("an inspect failure surfaces on its row in browsing, as the error state")
    func inspectErrorSurfacesInBrowsing() async {
        let broken = Self.app("Broken")
        let fine = Self.app("Fine")
        let viewModel = Self.makeViewModel(apps: [broken, fine]) { app in
            if app.bundleIdentifier == broken.bundleIdentifier { throw InspectFailure() }
            return Self.items(for: app)
        }
        #expect(viewModel.lifecycle == .start)

        let opened = await viewModel.inspect(viewModel.row(forBundleID: broken.bundleIdentifier)!)

        #expect(!opened)
        #expect(viewModel.phase == .browsing)
        #expect(viewModel.row(forBundleID: broken.bundleIdentifier)?.inspectError == "Couldn’t read its Library folders.")
        #expect(viewModel.row(forBundleID: fine.bundleIdentifier)?.inspectError == nil)
        #expect(viewModel.lifecycle == .error)
        #expect(viewModel.failedRows.map(\.app.name) == ["Broken"])
        // Busy flags stay out of the enum, and the busy flag is released.
        #expect(viewModel.inspectingBundleID == nil)

        // A later success clears the note; dismissing clears it without a retry.
        viewModel.dismissInspectErrors()
        #expect(viewModel.lifecycle == .start)
    }

    // MARK: - Re-entrancy

    @Test("a second inspect is refused while one is running")
    func secondInspectIsRefused() async {
        let first = Self.app("First")
        let second = Self.app("Second")
        let gate = Gate()
        let viewModel = Self.makeViewModel(apps: [first, second]) { app in
            await gate.wait()
            return Self.items(for: app)
        }
        let firstRow = viewModel.row(forBundleID: first.bundleIdentifier)!
        let secondRow = viewModel.row(forBundleID: second.bundleIdentifier)!

        let running = Task { await viewModel.inspect(firstRow) }
        #expect(await wait(until: first.bundleIdentifier, { viewModel.inspectingBundleID ?? "" }))

        let refused = await viewModel.inspect(secondRow)
        #expect(!refused)
        #expect(viewModel.inspectingBundleID == first.bundleIdentifier)
        // Measure All is refused too while an inspect runs.
        #expect(!viewModel.startInspectAll())

        await gate.open()
        let opened = await running.value
        #expect(opened)
        #expect(viewModel.phase == .reviewing(bundleID: first.bundleIdentifier))
        #expect(viewModel.inspectingBundleID == nil)
        // And inspect is refused outside the app list (during the review).
        #expect(await viewModel.inspect(secondRow) == false)
    }

    // MARK: - Measure All

    @Test("Measure All fills every size, reaches measured, and one failure doesn't stop it")
    func measureAll() async {
        let alpha = Self.app("Alpha")
        let broken = Self.app("Broken")
        let gamma = Self.app("Gamma")
        let viewModel = Self.makeViewModel(apps: [alpha, broken, gamma]) { app in
            if app.bundleIdentifier == broken.bundleIdentifier { throw InspectFailure() }
            return Self.items(for: app)
        }

        #expect(viewModel.startInspectAll())
        #expect(viewModel.lifecycle == .scanning)
        #expect(await wait(until: UninstallerViewModel.Phase.measured) { viewModel.phase })

        #expect(viewModel.row(forBundleID: alpha.bundleIdentifier)?.inspectedSize == 1_002_000)
        #expect(viewModel.row(forBundleID: gamma.bundleIdentifier)?.inspectedSize == 1_002_000)
        #expect(viewModel.row(forBundleID: broken.bundleIdentifier)?.inspectedSize == nil)
        #expect(viewModel.row(forBundleID: broken.bundleIdentifier)?.inspectError != nil)
        #expect(viewModel.measuredAppCount == 2)
        // A failed row turns the measured screen into the error state until dismissed.
        #expect(viewModel.lifecycle == .error)
        viewModel.dismissInspectErrors()
        #expect(viewModel.lifecycle == .results)
    }

    @Test("Stop returns to the list and keeps the sizes already measured")
    func stopKeepsMeasuredSizes() async {
        let alpha = Self.app("Alpha")
        let beta = Self.app("Beta")
        let gate = Gate()
        let viewModel = Self.makeViewModel(apps: [alpha, beta]) { app in
            if app.bundleIdentifier == beta.bundleIdentifier { await gate.wait() }
            return Self.items(for: app)
        }

        #expect(viewModel.startInspectAll())
        #expect(await wait(until: .inspectingAll(currentBundleID: beta.bundleIdentifier)) { viewModel.phase })

        viewModel.cancelInspectAll()
        await gate.open()

        #expect(viewModel.phase == .browsing)
        #expect(viewModel.lifecycle == .start)
        #expect(viewModel.row(forBundleID: alpha.bundleIdentifier)?.inspectedSize == 1_002_000)
        #expect(viewModel.row(forBundleID: beta.bundleIdentifier)?.inspectedSize == nil)
        // The superseded run must not flip the phase afterwards.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.phase == .browsing)
    }

    // MARK: - Running app (OD-9)

    @Test("a running app blocks the confirmation; once it quits, the sheet is offered")
    func runningAppBlocksConfirmation() async {
        let alpha = Self.app("Alpha")
        var running = true
        let viewModel = Self.makeViewModel(apps: [alpha], isRunning: { _ in running })
        _ = await viewModel.inspect(viewModel.apps[0])

        #expect(viewModel.isReviewedAppRunning)
        #expect(viewModel.uninstallConfirmation() == nil)

        running = false
        #expect(!viewModel.refreshRunningState())
        #expect(!viewModel.isReviewedAppRunning)
        #expect(viewModel.uninstallConfirmation() != nil)
    }

    // MARK: - Confirmation

    @Test("the confirmation names the app, counts related items and says at least")
    func confirmationContent() async throws {
        let alpha = Self.app("Alpha", appStore: true)
        let viewModel = Self.makeViewModel(apps: [alpha])
        _ = await viewModel.inspect(viewModel.apps[0])

        let model = try #require(viewModel.uninstallConfirmation())
        #expect(model.appName == "Alpha")
        // Four items selected: the app plus 3 related.
        #expect(model.count == 3)
        #expect(model.sizeText?.hasPrefix("at least ") == true)
        #expect(model.appStoreNote)
        #expect(model.items.count == 4)

        // Without the bundle the sheet counts the items it lists and names no app.
        viewModel.toggleSelection(path: alpha.bundlePath)
        let leftovers = try #require(viewModel.uninstallConfirmation())
        #expect(leftovers.appName == nil)
        #expect(leftovers.count == 3)
        #expect(!leftovers.appStoreNote)

        // Nothing selected → no sheet at all.
        viewModel.deselectAll()
        #expect(viewModel.uninstallConfirmation() == nil)
    }

    // MARK: - Uninstall (real trash route)

    @Test("uninstall moves the selection to the Trash and reports at-least bytes")
    func uninstallMovesToTrash() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("uninstaller-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let token = UUID().uuidString
        let bundle = dir.appendingPathComponent("Temp-\(token).app")
        let plist = dir.appendingPathComponent("temp-\(token).plist")
        let folder = dir.appendingPathComponent("temp-\(token)-support")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: plist, atomically: true, encoding: .utf8)

        let app = InstalledApp(name: "Temp", bundleIdentifier: "com.test.temp-\(token)", version: nil,
                               sparkleFeedURL: nil, bundlePath: bundle.path, isAppStoreDistributed: false)
        let items = [
            ScanItem(path: bundle.path, size: 5_000, kind: .directory, sourceLabel: "Application bundle"),
            ScanItem(path: plist.path, size: 300, kind: .file),
            ScanItem(path: folder.path, size: 64, kind: .directory),
        ]
        let viewModel = Self.makeViewModel(apps: [app]) { _ in items }
        _ = await viewModel.inspect(viewModel.apps[0])

        let moved = await viewModel.uninstall()

        #expect(moved)
        // Folders add no bytes: "at least" 5,000 + 300.
        #expect(viewModel.phase == .removed(appName: "Temp", atLeastBytes: 5_300, itemCount: 3, failedCount: 0))
        #expect(viewModel.lifecycle == .done)
        #expect(viewModel.lastRemovalIncludedApp)
        #expect(viewModel.apps.isEmpty)
        for url in [bundle, plist, folder] {
            #expect(!fm.fileExists(atPath: url.path))
        }
        // Don't leave debris in the real Trash.
        let trash = try fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        for url in [bundle, plist, folder] {
            try? fm.removeItem(at: trash.appendingPathComponent(url.lastPathComponent))
        }
    }

    @Test("an item that can't be moved is reported, not folded into the figure")
    func uninstallReportsFailures() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("uninstaller-missing-\(UUID().uuidString)")
        let app = InstalledApp(name: "Ghost", bundleIdentifier: "com.test.ghost", version: nil,
                               sparkleFeedURL: nil, bundlePath: missing.appendingPathComponent("Ghost.app").path,
                               isAppStoreDistributed: false)
        let items = [
            ScanItem(path: app.bundlePath, size: 9_000, kind: .directory),
            ScanItem(path: missing.appendingPathComponent("a.plist").path, size: 100, kind: .file),
        ]
        let viewModel = Self.makeViewModel(apps: [app]) { _ in items }
        _ = await viewModel.inspect(viewModel.apps[0])

        _ = await viewModel.uninstall()

        #expect(viewModel.phase == .removed(appName: "Ghost", atLeastBytes: 0, itemCount: 0, failedCount: 2))
        #expect(viewModel.lastFailedItems.count == 2)
        #expect(!viewModel.lastRemovalIncludedApp)
        // The app stayed, so it is still in the list.
        #expect(viewModel.apps.count == 1)
    }

    @Test("uninstall is refused outside the review and with nothing selected")
    func uninstallIsGuarded() async {
        let alpha = Self.app("Alpha")
        let viewModel = Self.makeViewModel(apps: [alpha])
        #expect(await viewModel.uninstall() == false)   // browsing

        _ = await viewModel.inspect(viewModel.apps[0])
        viewModel.deselectAll()
        #expect(await viewModel.uninstall() == false)   // nothing selected
        #expect(viewModel.phase == .reviewing(bundleID: alpha.bundleIdentifier))
    }

    // MARK: - Navigation, filter, lifecycle

    @Test("Back from the review returns to the list the user came from")
    func backReturnsToTheList() async {
        let alpha = Self.app("Alpha")
        let viewModel = Self.makeViewModel(apps: [alpha])
        _ = await viewModel.inspect(viewModel.apps[0])
        viewModel.backToApps()
        #expect(viewModel.phase == .browsing)
        #expect(viewModel.associatedItems.isEmpty)
        #expect(viewModel.selectedPaths.isEmpty)
        // The measured size stays on the row.
        #expect(viewModel.apps[0].inspectedSize == 1_002_000)
    }

    @Test("the name filter is local, case- and diacritic-insensitive")
    func nameFilter() {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Café"), Self.app("Gamma")])
        #expect(viewModel.visibleApps.count == 3)
        viewModel.filterText = "  CAFE "
        #expect(viewModel.visibleApps.map(\.app.name) == ["Café"])
        viewModel.filterText = "zzz"
        #expect(viewModel.visibleApps.isEmpty)
        viewModel.filterText = ""
        #expect(viewModel.visibleApps.count == 3)
    }

    @Test("an empty enumeration is the empty state, after the first load only")
    func emptyState() {
        let viewModel = UninstallerViewModel(enumerator: InstalledAppsEnumerator(searchDirectories: []),
                                             iconLoader: { _ in nil })
        #expect(viewModel.lifecycle == .start)       // nothing loaded yet
        viewModel.loadApps()
        #expect(viewModel.hasLoadedApps)
        #expect(viewModel.lifecycle == .empty)
    }

    @Test("every fixture state maps to its lifecycle state")
    func fixtureLifecycleMapping() {
        let viewModel = UninstallerViewModel(enumerator: InstalledAppsEnumerator(searchDirectories: []),
                                             iconLoader: { _ in nil })
        for state in LifecycleState.allCases {
            viewModel.loadFixture(state)
            #expect(viewModel.lifecycle == state, "fixture \(state.rawValue)")
        }
    }

    @Test("Measure All is refused with no apps")
    func measureAllNeedsApps() {
        let viewModel = Self.makeViewModel(apps: [])
        #expect(!viewModel.startInspectAll())
        #expect(viewModel.phase == .browsing)
    }
}

import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Updater view-model tests (plan PR 10): the Phase → lifecycle mapping, a throwing feed
/// (D3 / OD-10: `checkError`, never "Up to date"), Stop leaving the rows checked so far,
/// the re-entrancy guard, "no check on visit" (OD-10) and the group builder. Hermetic: every
/// feed is an injected closure (no network), every app is a made-up `InstalledApp` under a
/// fictional `/Applications` (no real file system, no real app list).
@Suite("UpdaterViewModel")
@MainActor
struct UpdaterViewModelTests {

    // MARK: - Fixtures

    private struct FeedFailure: LocalizedError {
        var errorDescription: String? { "The network connection was lost." }
    }

    private nonisolated static func app(_ name: String,
                                        version: String = "1.0",
                                        feed: Bool = true,
                                        appStore: Bool = false) -> InstalledApp {
        InstalledApp(name: name,
                     bundleIdentifier: "com.test.\(name.lowercased())",
                     version: version,
                     sparkleFeedURL: feed ? URL(string: "https://updates.example.invalid/\(name.lowercased())/appcast.xml") : nil,
                     bundlePath: "/Applications/\(name).app",
                     isAppStoreDistributed: appStore)
    }

    private static func makeViewModel(
        apps: [InstalledApp],
        feed: @escaping UpdaterViewModel.FeedFunction = { _, installed in installed }
    ) -> UpdaterViewModel {
        let viewModel = UpdaterViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: []),
            feed: feed,
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

    /// Records which feeds were asked, and can hold named feeds open until released.
    private actor FeedProbe {
        private(set) var requested: [String] = []
        private var gates: [String: CheckedContinuation<Void, Never>] = [:]
        private var opened: Set<String> = []

        func record(_ name: String) { requested.append(name) }

        func hold(_ name: String) async {
            guard !opened.contains(name) else { return }
            await withCheckedContinuation { gates[name] = $0 }
        }

        func release(_ name: String) {
            opened.insert(name)
            gates[name]?.resume()
            gates[name] = nil
        }
    }

    private nonisolated static func feedName(_ url: URL) -> String { url.pathComponents[1] }

    // MARK: - Phase → lifecycle mapping

    @Test("every Phase maps to its lifecycle state")
    func phaseToLifecycle() async {
        // idle → start
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")])
        #expect(viewModel.phase == .idle)
        #expect(viewModel.lifecycle == .start)

        // checking → scanning (feed held open so the phase is observable)
        let probe = FeedProbe()
        let held = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            await probe.hold(Self.feedName(url))
            return installed
        })
        #expect(held.startCheck())
        #expect(held.phase == .checking)
        #expect(held.lifecycle == .scanning)
        #expect(held.isCheckingAll)
        await probe.release("alpha")
        #expect(await wait(until: true) { held.phase != .checking })

        // results → results (an update is available)
        let results = Self.makeViewModel(apps: [Self.app("Alpha", version: "1.0")], feed: { _, _ in "2.0" })
        results.startCheck()
        #expect(await wait(until: true) { results.phase != .checking })
        #expect(results.phase == .results)
        #expect(results.lifecycle == .results)

        // empty → empty (every feed answered, nothing newer)
        let empty = Self.makeViewModel(apps: [Self.app("Alpha")])
        empty.startCheck()
        #expect(await wait(until: true) { empty.phase != .checking })
        #expect(empty.phase == .empty)
        #expect(empty.lifecycle == .empty)

        // failed → error (every feed failed)
        let failed = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { _, _ in throw FeedFailure() })
        failed.startCheck()
        #expect(await wait(until: true) { failed.phase != .checking })
        guard case .failed(let message) = failed.phase else {
            Issue.record("expected .failed, got \(failed.phase)")
            return
        }
        #expect(message.contains("The network connection was lost."))
        #expect(failed.lifecycle == .error)
    }

    @Test("one failed feed among answering ones stays in results, never the whole-screen error")
    func partialFailureStaysResults() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo")], feed: { url, installed in
            if Self.feedName(url) == "bravo" { throw FeedFailure() }
            return installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .results)
        #expect(viewModel.hasCheckError)
    }

    // MARK: - D3 / OD-10: a failed check never reads "Up to date"

    @Test("a throwing feed sets checkError and the row never reads Up to date")
    func throwingFeedNeverUpToDate() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo")], feed: { url, installed in
            if Self.feedName(url) == "bravo" { throw FeedFailure() }
            return installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })

        let bravo = viewModel.rows.first { $0.app.name == "Bravo" }
        #expect(bravo?.checkError == "The network connection was lost.")
        #expect(bravo?.latestVersion == nil)
        #expect(bravo.map(UpdaterGroups.status(of:)) == .checkFailed(message: "The network connection was lost."))
        #expect(viewModel.failedRows.map(\.app.name) == ["Bravo"])

        // The row that really answered may read Up to date; the failed one may not.
        let alpha = viewModel.rows.first { $0.app.name == "Alpha" }
        #expect(alpha.map(UpdaterGroups.status(of:)) == .upToDate)
        let kinds = Dictionary(uniqueKeysWithValues: viewModel.groups.map { ($0.kind, $0.rows.map(\.app.name)) })
        #expect(kinds[.upToDate] == ["Alpha"])
        #expect(kinds[.couldntCheck] == ["Bravo"])
        #expect(viewModel.upToDateCount == 1)
    }

    @Test("a feed that answers without a version is a failure, not Up to date")
    func feedWithoutVersionIsAFailure() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo")], feed: { url, installed in
            Self.feedName(url) == "alpha" ? nil : installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        let alpha = viewModel.rows.first { $0.app.name == "Alpha" }
        #expect(alpha?.checkError == "The update feed has no version information.")
        #expect(alpha.map(UpdaterGroups.status(of:)) != .upToDate)
        #expect(viewModel.phase == .results)
    }

    @Test("the engine's real feed error text is kept on the row")
    func errorTextComesFromTheFeed() async {
        struct Specific: LocalizedError { var errorDescription: String? { "HTTP 503 from the feed." } }
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo")], feed: { url, installed in
            if Self.feedName(url) == "alpha" { throw Specific() }
            return installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.checkError == "HTTP 503 from the feed.")
    }

    @Test("retrying re-checks only the failed rows and keeps the other results")
    func retryOnlyFailedRows() async {
        let probe = FeedProbe()
        let failFirst = FailOnce()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo")], feed: { url, installed in
            let name = Self.feedName(url)
            await probe.record(name)
            if name == "bravo", await failFirst.shouldFail() { throw FeedFailure() }
            return name == "alpha" ? "9.0" : installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.hasCheckError)
        #expect(await probe.requested.sorted() == ["alpha", "bravo"])

        #expect(viewModel.retryFailedChecks())
        #expect(await wait(until: true) { viewModel.phase != .checking })
        // Only bravo was asked again; alpha's earlier result is untouched.
        #expect(await probe.requested.sorted() == ["alpha", "bravo", "bravo"])
        #expect(!viewModel.hasCheckError)
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.latestVersion == "9.0")
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:)) == .upToDate)
    }

    private actor FailOnce {
        private var failed = false
        func shouldFail() -> Bool {
            defer { failed = true }
            return !failed
        }
    }

    @Test("retryFailedChecks is refused when no row failed")
    func retryWithoutFailures() {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")])
        #expect(!viewModel.retryFailedChecks())
        #expect(viewModel.phase == .idle)
    }

    // MARK: - Stop

    @Test("Stop leaves the rows checked so far and marks the rest Not checked")
    func stopKeepsCheckedRows() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha", version: "1.0"), Self.app("Bravo"), Self.app("Charlie")],
            feed: { url, installed in
                let name = Self.feedName(url)
                await probe.record(name)
                if name == "bravo" { await probe.hold("bravo") }
                return name == "alpha" ? "2.0" : installed
            })
        viewModel.startCheck()
        // Alpha is done; Bravo's feed is held open.
        #expect(await wait(until: true) { viewModel.rows.first { $0.app.name == "Bravo" }?.isChecking ?? false })
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.latestVersion == "2.0")

        viewModel.stopCheck()
        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .results)
        #expect(!viewModel.isCheckingAll)
        // Alpha keeps its real result; nothing is spinning; the rest is not Up to date.
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.latestVersion == "2.0")
        #expect(viewModel.rows.allSatisfy { !$0.isChecking })
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:)) == .notChecked)
        #expect(viewModel.rows.first { $0.app.name == "Charlie" }.map(UpdaterGroups.status(of:)) == .notChecked)
        #expect(viewModel.upToDateCount == 0)
        #expect(viewModel.checkedCount == 1)

        // Releasing the held feed afterwards must not write into the stopped run.
        await probe.release("bravo")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }?.latestVersion == nil)
        #expect(await !probe.requested.contains("charlie"))
        #expect(viewModel.phase == .results)
    }

    @Test("Stop before any row finished returns to the start")
    func stopWithNothingCheckedReturnsToStart() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            await probe.hold(Self.feedName(url))
            return installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.rows.first?.isChecking ?? false })
        viewModel.stopCheck()
        #expect(viewModel.phase == .idle)
        #expect(viewModel.lifecycle == .start)
        #expect(viewModel.rows.first?.latestVersion == nil)
        await probe.release("alpha")
    }

    @Test("a stopped run cannot change the phase of the run that replaced it")
    func supersededRunIsIgnored() async {
        let probe = FeedProbe()
        let counter = CallCounter()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            let call = await counter.next()
            if call == 1 { await probe.hold(Self.feedName(url)) }
            return call == 1 ? "7.0" : installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.rows.first?.isChecking ?? false })
        viewModel.stopCheck()
        #expect(viewModel.startCheck())
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .empty)
        // The first (stopped) run now finishes late: it must not overwrite the second result.
        await probe.release("alpha")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.rows.first?.latestVersion == "1.0")
        #expect(viewModel.phase == .empty)
    }

    private actor CallCounter {
        private var count = 0
        func next() -> Int { count += 1; return count }
    }

    // MARK: - Re-entrancy and "no check on visit"

    @Test("a second check is refused while one is running")
    func secondCheckIsRefused() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            await probe.record(Self.feedName(url))
            await probe.hold(Self.feedName(url))
            return installed
        })
        #expect(viewModel.startCheck())
        #expect(!viewModel.startCheck())
        #expect(!viewModel.retryFailedChecks())
        await probe.release("alpha")
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(await probe.requested == ["alpha"])
    }

    @Test("visiting never starts a check; loadApps is first-visit-only (OD-10)")
    func visitingDoesNotCheck() async {
        let probe = FeedProbe()
        let viewModel = UpdaterViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: []),
            feed: { url, installed in
                await probe.record(Self.feedName(url))
                return installed
            },
            iconLoader: { _ in nil })
        viewModel.loadApps()
        viewModel.loadApps()
        #expect(viewModel.hasLoadedApps)
        #expect(viewModel.phase == .idle)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await probe.requested.isEmpty)
    }

    @Test("a check with no apps is refused")
    func noAppsNoCheck() {
        let viewModel = Self.makeViewModel(apps: [])
        #expect(!viewModel.startCheck())
        #expect(viewModel.phase == .idle)
    }

    @Test("Check Again clears earlier results first, so a stale row can't read Up to date")
    func checkAgainStartsFromScratch() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            if await probe.requested.count >= 1 { await probe.hold("second") }
            await probe.record(Self.feedName(url))
            return installed
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase == .empty })
        #expect(viewModel.rows[0].latestVersion == "1.0")
        viewModel.startCheck()
        #expect(viewModel.phase == .checking)
        #expect(viewModel.rows[0].latestVersion == nil)
        #expect(viewModel.rows[0].checkError == nil)
        viewModel.stopCheck()
        await probe.release("second")
    }

    // MARK: - What can be checked, and what "empty" requires

    @Test("apps without a feed or an installed version are never checked and never read Up to date")
    func uncheckableRows() async {
        let probe = FeedProbe()
        let noVersion = InstalledApp(name: "Charlie", bundleIdentifier: "com.test.charlie", version: nil,
                                     sparkleFeedURL: URL(string: "https://updates.example.invalid/charlie/appcast.xml"),
                                     bundlePath: "/Applications/Charlie.app", isAppStoreDistributed: false)
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha"), Self.app("Bravo", feed: false), noVersion],
            feed: { url, installed in
                await probe.record(Self.feedName(url))
                return installed
            })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(await probe.requested == ["alpha"])
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:)) == .noFeed)
        #expect(viewModel.rows.first { $0.app.name == "Charlie" }.map(UpdaterGroups.status(of:)) == .noFeed)
        #expect(viewModel.upToDateCount == 1)
        #expect(viewModel.noFeedCount == 2)
        // Cannot-check rows don't count as checked.
        #expect(viewModel.checkedCount == 1)
    }

    @Test("a check with nothing checkable lands in results, never in the all-up-to-date state")
    func nothingCheckableIsNotEmpty() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Bravo", feed: false)])
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.upToDateCount == 0)
    }

    @Test("an App Store app keeps the results screen: all-up-to-date is not claimed")
    func appStoreAppBlocksEmpty() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo", feed: false, appStore: true)])
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.groups.map(\.kind) == [.appStore, .upToDate])
    }

    @Test("a newer version in a feed is an update; an equal or older one is not")
    func updateDetectionIsNumeric() async {
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha", version: "1.9"), Self.app("Bravo", version: "2.0"), Self.app("Charlie", version: "3.1")],
            feed: { url, _ in
                switch Self.feedName(url) {
                case "alpha": "1.10"      // numeric compare: 1.10 > 1.9
                case "bravo": "2.0"
                default: "3.0"            // older than installed
                }
            })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.updatesAvailableCount == 1)
        #expect(viewModel.hasAnyUpdate)
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }.map(UpdaterGroups.status(of:))
                == .updateAvailable(installed: "1.9", latest: "1.10"))
        #expect(viewModel.groups.first?.kind == .updates)
    }

    // MARK: - Groups

    @Test("groups come in spec order and empty groups are dropped")
    func groupOrder() {
        let rows: [UpdaterViewModel.AppUpdateRow] = [
            .init(app: Self.app("Echo", feed: false)),                                        // noFeed
            .init(app: Self.app("Delta"), latestVersion: "1.0"),                              // upToDate
            .init(app: Self.app("Charlie", feed: false, appStore: true)),                     // appStore
            .init(app: Self.app("Bravo"), latestVersion: "2.0"),                              // update
            .init(app: Self.app("Foxtrot"), checkError: "boom"),                              // couldn't check
            .init(app: Self.app("Golf")),                                                     // not checked
        ]
        let groups = UpdaterGroups.groups(for: rows)
        #expect(groups.map(\.kind) == [.updates, .appStore, .upToDate, .noFeed, .couldntCheck, .notChecked])
        #expect(groups.map { $0.rows.map(\.app.name) } == [["Bravo"], ["Charlie"], ["Delta"], ["Echo"], ["Foxtrot"], ["Golf"]])
        #expect(UpdaterGroups.groups(for: []).isEmpty)
        #expect(UpdaterGroups.groups(for: [rows[1]]).map(\.kind) == [.upToDate])
    }

    @Test("updates text is plural-aware")
    func updatesText() {
        #expect(UpdaterGroups.updatesText(1) == "1 update available")
        #expect(UpdaterGroups.updatesText(3) == "3 updates available")
    }

    // MARK: - Fixtures (Debug): every state loads without a feed

    @Test("fixture states load their phase without ever calling the feed")
    func fixtureStates() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(apps: [], feed: { url, installed in
            await probe.record(Self.feedName(url))
            return installed
        })
        let expected: [(String, UpdaterViewModel.Phase, LifecycleState)] = [
            ("start", .idle, .start),
            ("scanning", .checking, .scanning),
            ("results", .results, .results),
            ("checkfailed", .results, .results),
            ("empty", .empty, .empty),
        ]
        for (state, phase, lifecycle) in expected {
            viewModel.loadFixture(state: state)
            #expect(viewModel.phase == phase, "\(state)")
            #expect(viewModel.lifecycle == lifecycle, "\(state)")
        }
        viewModel.loadFixture(state: "error")
        #expect(viewModel.lifecycle == .error)

        viewModel.loadFixture(state: "checkfailed")
        #expect(viewModel.failedRows.count == 1)
        viewModel.loadFixture(state: "results")
        #expect(viewModel.updatesAvailableCount == 3)
        #expect(viewModel.groups.map(\.kind) == [.updates, .appStore, .upToDate, .noFeed])
        viewModel.loadFixture(state: "scanning")
        #expect(viewModel.currentlyCheckingRow != nil)
        #expect(viewModel.progressTracker.progress?.itemsProcessed == 2)

        try? await Task.sleep(for: .milliseconds(50))
        #expect(await probe.requested.isEmpty)
    }

    @Test("fixture apps are fictional: no real host, no real home path")
    func fixtureAppsAreSynthetic() {
        for app in UITestFixtures.updaterApps + UITestFixtures.updaterEmptyApps {
            #expect(app.bundlePath.hasPrefix("/Applications/Example "))
            #expect(app.bundleIdentifier.hasPrefix("com.example."))
            if let host = app.sparkleFeedURL?.host { #expect(host.hasSuffix(".invalid")) }
        }
    }
}

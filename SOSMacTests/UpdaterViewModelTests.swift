import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Updater view-model tests (plan PR 10): the Phase → lifecycle mapping, a throwing feed
/// (D3 / OD-10: `checkError`, never "Up to date"), Stop discarding partial results (F2),
/// the re-entrancy guard, "no check on visit" (OD-10), Check Again re-reading the installed
/// apps, marketing-vs-build version pairs, the user-visible copy and the group builder.
/// Hermetic: every feed is an injected closure (no network); apps are made-up `InstalledApp`s
/// under a fictional `/Applications`, except the re-enumeration tests, which write throwaway
/// bundles into a temporary directory.
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
                                        appStore: Bool = false,
                                        build: String? = nil) -> InstalledApp {
        InstalledApp(name: name,
                     bundleIdentifier: "com.test.\(name.lowercased())",
                     version: version,
                     sparkleFeedURL: feed ? URL(string: "https://updates.example.invalid/\(name.lowercased())/appcast.xml") : nil,
                     bundlePath: "/Applications/\(name).app",
                     isAppStoreDistributed: appStore,
                     buildVersion: build)
    }

    /// A feed that names only a marketing version (`sparkle:shortVersionString`).
    private nonisolated static func release(_ version: String) -> AppcastRelease {
        AppcastRelease(shortVersion: version)
    }

    /// The enumerator seam returns `apps` on every full check, like a machine whose app list
    /// has not changed; tests that need it to change use `UpdaterViewModel(enumerate:)`.
    private static func makeViewModel(
        apps: [InstalledApp],
        feed: @escaping UpdaterViewModel.FeedFunction = { _, installed in Self.release(installed) }
    ) -> UpdaterViewModel {
        let viewModel = UpdaterViewModel(
            enumerate: { apps },
            feed: feed,
            iconLoader: { _ in nil })
        viewModel.loadApps()
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
            return Self.release(installed)
        })
        #expect(held.startCheck())
        #expect(held.phase == .checking)
        #expect(held.lifecycle == .scanning)
        #expect(held.isCheckingAll)
        await probe.release("alpha")
        #expect(await wait(until: true) { held.phase != .checking })

        // results → results (an update is available)
        let results = Self.makeViewModel(apps: [Self.app("Alpha", version: "1.0")], feed: { _, _ in Self.release("2.0") })
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
            return Self.release(installed)
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
            return Self.release(installed)
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
            Self.feedName(url) == "alpha" ? nil : Self.release(installed)
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
            return Self.release(installed)
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
            return Self.release(name == "alpha" ? "9.0" : installed)
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

    @Test("Stop discards partial results and returns to the start (spec F2)")
    func stopDiscardsPartialResults() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha", version: "1.0"), Self.app("Bravo"), Self.app("Charlie")],
            feed: { url, installed in
                let name = Self.feedName(url)
                await probe.record(name)
                if name == "bravo" { await probe.hold("bravo") }
                return Self.release(name == "alpha" ? "2.0" : installed)
            })
        viewModel.startCheck()
        // Alpha is done; Bravo's feed is held open.
        #expect(await wait(until: true) { viewModel.rows.first { $0.app.name == "Bravo" }?.isChecking ?? false })
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.latestVersion == "2.0")

        viewModel.stopCheck()
        #expect(viewModel.phase == .idle)
        #expect(viewModel.lifecycle == .start)
        #expect(!viewModel.isCheckingAll)
        #expect(viewModel.progressTracker.progress == nil)
        // Alpha's partial result is gone too: nothing is kept, nothing spins, the list stays.
        #expect(viewModel.rows.map(\.app.name) == ["Alpha", "Bravo", "Charlie"])
        #expect(viewModel.rows.allSatisfy { $0.latestVersion == nil && $0.installedBasis == nil
                                            && $0.checkError == nil && !$0.isChecking })
        #expect(viewModel.groups.map(\.kind) == [.notChecked])
        #expect(viewModel.checkedCount == 0)
        #expect(viewModel.updatesAvailableCount == 0)
        #expect(viewModel.upToDateCount == 0)
        #expect(!viewModel.hasCheckError)
        // Nothing failed, so there is nothing to retry.
        #expect(!viewModel.retryFailedChecks())

        // Releasing the held feed afterwards must not write into the stopped run.
        await probe.release("bravo")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }?.latestVersion == nil)
        #expect(await !probe.requested.contains("charlie"))
        #expect(viewModel.phase == .idle)
    }

    @Test("Stop before any row finished returns to the start")
    func stopWithNothingCheckedReturnsToStart() async {
        let probe = FeedProbe()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            await probe.hold(Self.feedName(url))
            return Self.release(installed)
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.rows.first?.isChecking ?? false })
        viewModel.stopCheck()
        #expect(viewModel.phase == .idle)
        #expect(viewModel.lifecycle == .start)
        #expect(viewModel.rows.first?.latestVersion == nil)
        await probe.release("alpha")
    }

    @Test("Stop during a Try Again also discards every earlier result")
    func stopDuringRetryDiscardsEverything() async {
        let probe = FeedProbe()
        let failOnce = FailOnce()
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha"), Self.app("Bravo")],
            feed: { url, installed in
                let name = Self.feedName(url)
                if name == "bravo" {
                    if await failOnce.shouldFail() { throw FeedFailure() }
                    await probe.hold("bravo")
                }
                return Self.release(name == "alpha" ? "9.0" : installed)
            })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.failedRows.map(\.app.name) == ["Bravo"])
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.latestVersion == "9.0")

        // The retry's feed is held open; Stop discards the retry *and* Alpha's result.
        #expect(viewModel.retryFailedChecks())
        #expect(await wait(until: true) { viewModel.rows.first { $0.app.name == "Bravo" }?.isChecking ?? false })
        viewModel.stopCheck()
        #expect(viewModel.phase == .idle)
        #expect(viewModel.rows.allSatisfy { $0.latestVersion == nil && $0.checkError == nil && !$0.isChecking })
        #expect(viewModel.failedRows.isEmpty)
        #expect(!viewModel.retryFailedChecks())

        await probe.release("bravo")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.rows.allSatisfy { $0.latestVersion == nil && $0.checkError == nil })
        #expect(viewModel.phase == .idle)
    }

    @Test("a stopped run cannot change the phase of the run that replaced it")
    func supersededRunIsIgnored() async {
        let probe = FeedProbe()
        let counter = CallCounter()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha")], feed: { url, installed in
            let call = await counter.next()
            if call == 1 { await probe.hold(Self.feedName(url)) }
            return Self.release(call == 1 ? "7.0" : installed)
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
            return Self.release(installed)
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
                return Self.release(installed)
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
            return Self.release(installed)
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
                return Self.release(installed)
            })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(await probe.requested == ["alpha"])
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:)) == .noFeed)
        #expect(viewModel.rows.first { $0.app.name == "Charlie" }.map(UpdaterGroups.status(of:)) == .noFeed)
        #expect(viewModel.upToDateCount == 1)
        #expect(viewModel.noFeedCount == 2)
        // Cannot-check rows don't count as checked, and they keep the results screen.
        #expect(viewModel.checkedCount == 1)
        #expect(viewModel.phase == .results)
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
                case "alpha": Self.release("1.10")      // numeric compare: 1.10 > 1.9
                case "bravo": Self.release("2.0")
                default: Self.release("3.0")            // older than installed
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

    // MARK: - D2: Check Again re-reads the installed apps

    /// Writes `<dir>/<name>.app/Contents/Info.plist` the way a real bundle carries it.
    private static func writeApp(_ name: String, version: String, build: String? = nil, in dir: URL) throws {
        let contents = dir.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.\(name.lowercased())",
            "CFBundleShortVersionString": version,
            "SUFeedURL": "https://updates.example.invalid/\(name.lowercased())/appcast.xml",
        ]
        if let build { plist["CFBundleVersion"] = build }
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
    }

    private static func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updater-vm-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Check Again re-reads the installed apps: an app updated elsewhere, a new app, a removed app")
    func checkAgainReEnumerates() async throws {
        let dir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeApp("Alpha", version: "1.0", in: dir)
        let viewModel = UpdaterViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: [dir.path]),
            feed: { _, _ in Self.release("1.1") },
            iconLoader: { _ in nil })
        viewModel.loadApps()
        #expect(viewModel.rows.map(\.app.name) == ["Alpha"])

        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.rows.first.map(UpdaterGroups.status(of:)) == .updateAvailable(installed: "1.0", latest: "1.1"))

        // Alpha is updated outside the app and Bravo is installed.
        try Self.writeApp("Alpha", version: "1.1", in: dir)
        try Self.writeApp("Bravo", version: "1.0", in: dir)
        #expect(viewModel.startCheck())
        // The rows are rebuilt before any feed answers, so a stale "1.0 → 1.1" can't show.
        #expect(viewModel.rows.map(\.app.name) == ["Alpha", "Bravo"])
        #expect(viewModel.rows.allSatisfy { $0.latestVersion == nil })
        #expect(await wait(until: true) { viewModel.phase != .checking })
        let alpha = viewModel.rows.first { $0.app.name == "Alpha" }
        #expect(alpha?.app.version == "1.1")
        #expect(alpha.map(UpdaterGroups.status(of:)) == .upToDate)
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:))
                == .updateAvailable(installed: "1.0", latest: "1.1"))

        // Bravo is uninstalled.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Bravo.app"))
        #expect(viewModel.startCheck())
        #expect(viewModel.rows.map(\.app.name) == ["Alpha"])
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .empty)
    }

    @Test("when every app is gone, Check Again returns to the start instead of an empty results screen")
    func checkAgainWithNoAppsLeft() async throws {
        let dir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeApp("Alpha", version: "1.0", in: dir)
        let viewModel = UpdaterViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: [dir.path]),
            feed: { _, installed in Self.release(installed) },
            iconLoader: { _ in nil })
        viewModel.loadApps()
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Alpha.app"))
        #expect(!viewModel.startCheck())
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.phase == .idle)
    }

    @Test("loadApps reads once and Try Again never re-reads; only a full check does")
    func onlyAFullCheckReEnumerates() async {
        let reads = ReadCounter()
        let failOnce = FailOnce()
        let apps = [Self.app("Alpha"), Self.app("Bravo")]
        let viewModel = UpdaterViewModel(
            enumerate: { reads.count += 1; return apps },
            feed: { url, installed in
                if Self.feedName(url) == "bravo", await failOnce.shouldFail() { throw FeedFailure() }
                return Self.release(installed)
            },
            iconLoader: { _ in nil })
        viewModel.loadApps()
        viewModel.loadApps()
        #expect(reads.count == 1)
        viewModel.startCheck()
        #expect(reads.count == 2)
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.hasCheckError)
        #expect(viewModel.retryFailedChecks())
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(reads.count == 2)
    }

    private final class ReadCounter { var count = 0 }

    // MARK: - D3: marketing vs marketing, build vs build

    @Test("a build-only feed compares against the installed build number")
    func buildOnlyFeedUsesInstalledBuild() async {
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha", version: "2.0", build: "1249"),
                   Self.app("Bravo", version: "2.0", build: "1250")],
            feed: { _, _ in AppcastRelease(buildVersion: "1250") })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        // 1250 > 1249 is an update — shown in build numbers, never mixed with "2.0".
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }.map(UpdaterGroups.status(of:))
                == .updateAvailable(installed: "1249", latest: "1250"))
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:)) == .upToDate)
        #expect(viewModel.phase == .results)
    }

    @Test("a build-only feed for an app without a build number is Couldn't check, never a verdict")
    func buildOnlyFeedWithoutInstalledBuildFailsClosed() async {
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha", version: "2.0", build: "1249"), Self.app("Bravo", version: "2.0")],
            feed: { _, _ in AppcastRelease(buildVersion: "1250") })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        let bravo = viewModel.rows.first { $0.app.name == "Bravo" }
        #expect(bravo?.latestVersion == nil)
        #expect(bravo?.checkError == "The update feed's version can't be compared with this app's.")
        #expect(bravo.map(UpdaterGroups.status(of:))
                == .checkFailed(message: "The update feed's version can't be compared with this app's."))
        #expect(viewModel.failedRows.map(\.app.name) == ["Bravo"])
        #expect(viewModel.phase == .results)
    }

    @Test("a feed with a marketing version ignores build numbers, and 1.0 equals 1.0.0")
    func marketingVersionComparesAgainstMarketing() async {
        let viewModel = Self.makeViewModel(
            apps: [Self.app("Alpha", version: "1.0", build: "1"), Self.app("Bravo", version: "1.9", build: "5000")],
            feed: { url, _ in
                // Builds go the "wrong" way on purpose: they must not decide anything.
                Self.feedName(url) == "alpha"
                    ? AppcastRelease(shortVersion: "1.0.0", buildVersion: "9999")
                    : AppcastRelease(shortVersion: "1.10", buildVersion: "2")
            })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }.map(UpdaterGroups.status(of:)) == .upToDate)
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:))
                == .updateAvailable(installed: "1.9", latest: "1.10"))
    }

    // MARK: - D4: the all-up-to-date gate and the copy

    @Test("an app without a feed keeps the results screen: all-up-to-date needs every app checked")
    func noFeedRowBlocksEmpty() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo", feed: false)])
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .results)
        #expect(viewModel.groups.map(\.kind) == [.upToDate, .noFeed])
    }

    @Test("the results headline claims only what was checked")
    func resultsTitleCopy() async {
        #expect(UpdaterGroups.resultsTitle(updates: 1, checked: 4) == "1 update available")
        #expect(UpdaterGroups.resultsTitle(updates: 3, checked: 4) == "3 updates available")
        #expect(UpdaterGroups.resultsTitle(updates: 0, checked: 1) == "No newer versions found")
        #expect(UpdaterGroups.resultsTitle(updates: 0, checked: 0) == "No apps could be checked")
        for (updates, checked) in [(0, 0), (0, 1), (0, 7)] {
            #expect(UpdaterGroups.resultsTitle(updates: updates, checked: checked) != "No updates available")
        }

        // Through the view model, the way the header and the toolbar subtitle read it.
        let checkedSome = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo", feed: false)])
        checkedSome.startCheck()
        #expect(await wait(until: true) { checkedSome.phase != .checking })
        #expect(UpdaterGroups.resultsTitle(updates: checkedSome.updatesAvailableCount, checked: checkedSome.checkedCount)
                == "No newer versions found")

        let checkedNone = Self.makeViewModel(apps: [Self.app("Bravo", feed: false), Self.app("Charlie", feed: false, appStore: true)])
        checkedNone.startCheck()
        #expect(await wait(until: true) { checkedNone.phase != .checking })
        #expect(checkedNone.phase == .results)
        #expect(UpdaterGroups.resultsTitle(updates: checkedNone.updatesAvailableCount, checked: checkedNone.checkedCount)
                == "No apps could be checked")
    }

    @Test("the sub line, the empty text, the banner and the Not-checked note read as specified")
    func supportingCopy() {
        #expect(UpdaterGroups.checkedText(1) == "1 app checked")
        #expect(UpdaterGroups.checkedText(5) == "5 apps checked")
        #expect(UpdaterGroups.resultsSub(checked: 2) == "2 apps checked. Updates are installed in each app or in the App Store.")
        #expect(UpdaterGroups.emptyText(checked: 1) == "1 app checked. None has a newer version in its update feed.")
        #expect(UpdaterGroups.emptyText(checked: 3) == "3 apps checked. None has a newer version in its update feed.")
        // The empty state is only reachable when every app was checked: no no-feed caveat.
        #expect(!UpdaterGroups.emptyText(checked: 3).contains("no update feed"))

        let one = UpdaterGroups.failedBanner(for: [.init(app: Self.app("Bravo"), checkError: "HTTP 503 from the feed.")])
        #expect(one.title == "Couldn't check Bravo")
        #expect(one.text == "HTTP 503 from the feed. It is not shown as up to date.")
        let two = UpdaterGroups.failedBanner(for: [.init(app: Self.app("Bravo"), checkError: "x"),
                                                   .init(app: Self.app("Charlie"), checkError: "y")])
        #expect(two.title == "Couldn't check 2 apps")
        #expect(two.text == "Their update feeds didn't answer. They are not shown as up to date.")

        #expect(UpdaterGroup.Kind.notChecked.title == "Not checked yet")
        #expect(UpdaterGroup.Kind.notChecked.note == "These apps haven't been checked yet.")
        #expect(UpdaterGroup.Kind.couldntCheck.title == "Couldn't check")
        #expect(UpdaterGroup.Kind.noFeed.title == "No update feed")
    }

    // MARK: - Several feeds failing, and recovery

    @Test("two of three feeds failing is results with failed rows, never the whole-screen error")
    func twoOfThreeFeedsFail() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo"), Self.app("Charlie")], feed: { url, installed in
            if Self.feedName(url) != "alpha" { throw FeedFailure() }
            return Self.release(installed)
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .results)
        #expect(viewModel.failedRows.map(\.app.name) == ["Bravo", "Charlie"])
        #expect(viewModel.groups.map(\.kind) == [.upToDate, .couldntCheck])
        #expect(UpdaterGroups.failedBanner(for: viewModel.failedRows).title == "Couldn't check 2 apps")
    }

    @Test("every feed failing is the whole-check failure with the engine's reason")
    func everyFeedFails() async {
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo"), Self.app("Charlie")],
                                           feed: { _, _ in throw FeedFailure() })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .failed(message: "None of the 3 update feeds answered. The network connection was lost."))
        #expect(viewModel.lifecycle == .error)
    }

    @Test("Try Again: the failed feed answers on retry, its verdict lands, the banner goes, other rows are untouched")
    func tryAgainRecovery() async {
        let probe = FeedProbe()
        let failBravo = FailOnce()
        let viewModel = Self.makeViewModel(apps: [Self.app("Alpha"), Self.app("Bravo"), Self.app("Charlie")], feed: { url, installed in
            let name = Self.feedName(url)
            await probe.record(name)
            if name == "bravo", await failBravo.shouldFail() { throw FeedFailure() }
            return Self.release(name == "alpha" ? "9.0" : (name == "bravo" ? "1.5" : installed))
        })
        viewModel.startCheck()
        #expect(await wait(until: true) { viewModel.phase != .checking })
        #expect(viewModel.phase == .results)
        #expect(viewModel.failedRows.map(\.app.name) == ["Bravo"])
        #expect(UpdaterGroups.failedBanner(for: viewModel.failedRows).title == "Couldn't check Bravo")
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:))
                == .checkFailed(message: "The network connection was lost."))

        #expect(viewModel.retryFailedChecks())
        #expect(await wait(until: true) { viewModel.phase != .checking })
        // Only Bravo was asked again.
        #expect(await probe.requested.sorted() == ["alpha", "bravo", "bravo", "charlie"])
        // Its verdict landed, the banner is gone, the rest is exactly as it was.
        #expect(viewModel.rows.first { $0.app.name == "Bravo" }.map(UpdaterGroups.status(of:))
                == .updateAvailable(installed: "1.0", latest: "1.5"))
        #expect(viewModel.failedRows.isEmpty)
        #expect(!viewModel.hasCheckError)
        #expect(viewModel.rows.first { $0.app.name == "Alpha" }?.latestVersion == "9.0")
        #expect(viewModel.rows.first { $0.app.name == "Charlie" }.map(UpdaterGroups.status(of:)) == .upToDate)
        #expect(viewModel.updatesAvailableCount == 2)
        #expect(viewModel.phase == .results)
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
            return Self.release(installed)
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

        // The "empty" fixture obeys the real gate: every app has a feed, none is App Store.
        viewModel.loadFixture(state: "empty")
        #expect(viewModel.noFeedCount == 0)
        #expect(viewModel.appStoreCount == 0)
        #expect(viewModel.checkedCount == viewModel.checkableCount)
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

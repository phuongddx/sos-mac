import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Smart Care view-model tests (plan PR 7), following the reference screen's pattern
/// (`JunkCleanerViewModelTests`): fixtures for the pure states, hermetic temp trees for
/// the real scan/clean paths, and engine-never-reached doubles for the failure paths.
///
/// `/Users/sample` fixture paths must never reach the cleaner — clean-path tests use
/// unique temp paths that are never created (the failure path) or a hermetic temp tree
/// (the success path).
@Suite("SmartCareViewModel")
@MainActor
struct SmartCareViewModelTests {

    // MARK: - Doubles

    /// Controlled failure with a real, readable reason (LocalizedError, so
    /// `error.localizedDescription` is the message itself).
    private struct StubError: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }

    /// A junk leg that fails — Smart CareOrchestrator folds it into the module result.
    private struct FailingScanner: CleanCore.Scanner {
        func scan() async throws -> [ScanItem] {
            throw StubError(message: "The file “Home” couldn’t be opened because there is no such file.")
        }
    }

    /// A junk leg that succeeds and finds nothing.
    private struct EmptyScanner: CleanCore.Scanner {
        func scan() async throws -> [ScanItem] { [] }
    }

    private static func throwingDuplicates(_ message: String = "The file “Downloads” couldn’t be opened because there is no such file.")
        -> SmartCareViewModel.DuplicateScanSource {
        .custom { _ in throw StubError(message: message) }
    }

    // MARK: - Fixtures

    static func makeViewModel(
        rootPath: String = NSHomeDirectory(),
        orchestrator: SmartCareOrchestrator? = nil,
        cleaner: any Cleaner = DefaultCleaner(),
        duplicateScan: SmartCareViewModel.DuplicateScanSource? = nil
    ) -> SmartCareViewModel {
        SmartCareViewModel(rootPath: rootPath,
                           orchestrator: orchestrator,
                           cleaner: cleaner,
                           duplicateScan: duplicateScan)
    }

    private func waitForPhase(_ viewModel: SmartCareViewModel,
                              _ expected: SmartCareViewModel.Phase,
                              timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if viewModel.phase == expected { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return viewModel.phase == expected
    }

    /// ScanItems pointing at unique temp paths that are **never created**. A clean over
    /// them exercises the real `Cleaner` failure path (per-item `trashItem` errors)
    /// without depending on anything in the user's home directory.
    private static func missingItems(_ count: Int) -> [ScanItem] {
        (0..<count).map { index in
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("smartcare-missing-\(UUID().uuidString)-\(index).db")
                .path
            return ScanItem(
                path: path,
                size: Int64(100 + index),
                kind: .file,
                severity: .safe,
                sourceLabel: "User App Caches")
        }
    }

    // MARK: - Pre-selection (§5.2, unchanged rule)

    @Test("pre-selection: safe junk without the helper, every duplicate except the keep")
    func preSelectionFollowsTheSpecRule() throws {
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadFixture(.results)

        #expect(!viewModel.reviewItems.isEmpty)
        #expect(!viewModel.duplicateGroups.isEmpty)
        let cautionItems = viewModel.reviewItems.filter { $0.sourceModule == SmartCareViewModel.junkModuleName && $0.item.severity != .safe }
        #expect(!cautionItems.isEmpty, "fixtures must include caution junk to prove it stays unselected")

        for item in viewModel.reviewItems {
            let expected: Bool
            if item.isRecommendedKeep {
                expected = false
            } else if item.sourceModule == SmartCareViewModel.duplicatesModuleName {
                expected = true
            } else {
                expected = item.item.severity == .safe && !item.item.requiresPrivilegedHelper
            }
            #expect(viewModel.selectedPaths.contains(item.id) == expected,
                    "selection for \(item.item.path) must be \(expected)")
        }
    }

    // MARK: - S4: the keep lock

    @Test("the keep copy can never be selected — toggle, Select All, pre-selection (S4)")
    func keepCopyIsNeverSelectable() throws {
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadFixture(.results)

        let keeps = viewModel.reviewItems.filter(\.isRecommendedKeep)
        #expect(keeps.count == UITestFixtures.duplicateSets.count, "one keep per duplicate set")
        #expect(keeps.allSatisfy { !viewModel.selectedPaths.contains($0.id) },
                "pre-selection never includes a keep")

        for keep in keeps {
            viewModel.toggleSelection(path: keep.id)
            #expect(!viewModel.selectedPaths.contains(keep.id), "a manual toggle must not select the keep \(keep.item.path)")
        }

        // Select All inside a duplicate group selects every extra copy and no keep.
        let duplicateGroup = viewModel.duplicateGroups[0]
        viewModel.selectGroup(duplicateGroup.id)
        viewModel.deselectAllInCurrentGroup()
        viewModel.selectAllEligibleInCurrentGroup()
        for item in duplicateGroup.items {
            #expect(viewModel.selectedPaths.contains(item.id) == !item.isRecommendedKeep,
                    "Select All must skip the keep \(item.item.path)")
        }
    }

    // MARK: - Partial failure (F3)

    @Test("nothing found in one module and a failure in the other → results, never empty")
    func partialFailureIsNeverEmpty() async throws {
        let viewModel = Self.makeViewModel(
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: EmptyScanner())
            ]),
            duplicateScan: Self.throwingDuplicates())

        #expect(viewModel.startScan())
        #expect(await waitForPhase(viewModel, .results))

        #expect(viewModel.reviewItems.isEmpty)
        #expect(viewModel.duplicateErrorMessage != nil)
        #expect(viewModel.hasModuleFailure)
        #expect(viewModel.lifecycle == .results, "a failed module must not masquerade as “nothing found”")
        #expect(viewModel.lifecycle != .empty)
    }

    @Test("both legs failing → error, with the engine's reason")
    func bothLegsFailingIsError() async throws {
        let viewModel = Self.makeViewModel(
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: FailingScanner())
            ]),
            duplicateScan: Self.throwingDuplicates())

        #expect(viewModel.startScan())
        // The exact message is engine-defined; wait on the lifecycle instead.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, viewModel.lifecycle != .error {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard case .failed(let message) = viewModel.phase else {
            Issue.record("expected .failed, got \(viewModel.phase)")
            return
        }
        #expect(!message.isEmpty)
        #expect(viewModel.lifecycle == .error)
    }

    @Test("the partial-failure fixture produces results with a failed duplicate leg")
    func partialFailureFixtureMatchesTheSpecRow() throws {
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadPartialFailureFixture()

        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .results)
        #expect(viewModel.hasModuleFailure)
        #expect(viewModel.duplicateErrorMessage != nil)
        #expect(viewModel.junkErrorMessage == nil)
        #expect(!viewModel.reviewItems.isEmpty)
        #expect(viewModel.duplicateGroups.isEmpty)
    }

    // MARK: - Stop (F2, N6)

    @Test("Stop returns to start and discards partial results")
    func stopReturnsToStart() throws {
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadFixture(.results)
        #expect(!viewModel.selectedPaths.isEmpty)

        viewModel.loadFixture(.scanning)
        viewModel.cancelScan()

        #expect(viewModel.phase == .idle)
        #expect(viewModel.lifecycle == .start)
        #expect(viewModel.reviewItems.isEmpty)
        #expect(viewModel.selectedPaths.isEmpty)
        #expect(viewModel.junkGroups.isEmpty)
        #expect(viewModel.duplicateGroups.isEmpty)
        #expect(viewModel.performanceSnapshot == nil)
        #expect(viewModel.moduleStatuses.isEmpty)
    }

    // MARK: - Generation guard (stale progress hops)

    /// Drives the duplicate leg's progress from the test side: one scripted queue per
    /// scan generation, so a test can fire hops from any generation — including ones
    /// whose scan was already cancelled, the exact race the generation guard exists
    /// for. `@unchecked Sendable` with a lock: the seam is a `@Sendable` closure.
    private final class ProgressScriptBox: @unchecked Sendable {
        private let lock = NSLock()
        private var queues: [[ScanProgress]] = []
        private var finishedGenerations: Set<Int> = []

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return queues.count
        }

        /// Registers this generation's queue; called once per scan, from the closure.
        func register() -> Int {
            lock.lock()
            defer { lock.unlock() }
            queues.append([])
            return queues.count - 1
        }

        /// Queue a value for generation `index`'s closure to forward to its handler.
        func fire(from index: Int, _ progress: ScanProgress) {
            lock.lock()
            defer { lock.unlock() }
            guard queues.indices.contains(index) else { return }
            queues[index].append(progress)
        }

        /// The scan closure's wait — cancellation-IMMUNE on purpose (`Task.yield`
        /// never throws), so a generation that was already cancelled still forwards
        /// late values to its handler, like an engine leg whose in-flight callback
        /// lands after Stop.
        func next(_ index: Int) async -> ScanProgress? {
            while true {
                if let value = pop(index) { return value }
                if isFinished(index) { return nil }
                await Task.yield()
            }
        }

        // `NSLock` is unavailable from async contexts, so the state access lives in
        // these synchronous helpers.
        private func pop(_ index: Int) -> ScanProgress? {
            lock.lock()
            defer { lock.unlock() }
            guard !queues[index].isEmpty else { return nil }
            return queues[index].removeFirst()
        }

        private func isFinished(_ index: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return finishedGenerations.contains(index)
        }

        /// Ends every generation's loop (test teardown).
        func finishAll() {
            lock.lock()
            defer { lock.unlock() }
            finishedGenerations = Set(queues.indices)
        }
    }

    /// A duplicate leg that forwards scripted values to its progress handler and
    /// deliberately keeps waiting after task cancellation — emulating the engine legs
    /// whose late callbacks the generation guard must drop.
    private static func scriptedDuplicates(_ box: ProgressScriptBox)
        -> SmartCareViewModel.DuplicateScanSource {
        .custom { handler in
            let index = box.register()
            while let progress = await box.next(index) {
                handler(progress)
            }
            throw CancellationError()
        }
    }

    private func waitForScript(_ box: ProgressScriptBox, count: Int, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if box.count == count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return box.count == count
    }

    private func waitForDuplicateProgress(_ viewModel: SmartCareViewModel,
                                          itemsProcessed expected: Int,
                                          timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if viewModel.moduleProgress[SmartCareViewModel.duplicatesModuleName]?.itemsProcessed == expected {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return viewModel.moduleProgress[SmartCareViewModel.duplicatesModuleName]?.itemsProcessed == expected
    }

    @Test("a cancelled scan's late progress hops are dropped, not written into the reset state")
    func staleProgressFromCancelledScanIsDropped() async throws {
        let box = ProgressScriptBox()
        defer { box.finishAll() }
        let viewModel = SmartCareViewModelTests.makeViewModel(
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: EmptyScanner())
            ]),
            duplicateScan: Self.scriptedDuplicates(box))

        #expect(viewModel.startScan())
        #expect(await waitForPhase(viewModel, .scanning))
        #expect(await waitForScript(box, count: 1))

        // A hop from the live generation lands (the guard must not drop current work).
        box.fire(from: 0, ScanProgress(itemsProcessed: 1, totalItems: 10))
        #expect(await waitForDuplicateProgress(viewModel, itemsProcessed: 1))

        // A hop enqueued by the cancelled generation — e.g. already in flight when Stop
        // was tapped — must be dropped by the generation guard, not written into the
        // reset state.
        viewModel.cancelScan()
        #expect(viewModel.phase == .idle)
        #expect(viewModel.moduleProgress.isEmpty)
        box.fire(from: 0, ScanProgress(itemsProcessed: 5, totalItems: 10))
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel.moduleProgress.isEmpty)

        viewModel.cancelScan()
    }

    @Test("an old generation's hop cannot clobber the new scan's progress")
    func staleProgressCannotClobberARestart() async throws {
        let box = ProgressScriptBox()
        defer { box.finishAll() }
        let viewModel = SmartCareViewModelTests.makeViewModel(
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: EmptyScanner())
            ]),
            duplicateScan: Self.scriptedDuplicates(box))

        #expect(viewModel.startScan())
        #expect(await waitForPhase(viewModel, .scanning))
        #expect(await waitForScript(box, count: 1))
        viewModel.cancelScan()

        #expect(viewModel.startScan())
        #expect(await waitForPhase(viewModel, .scanning))
        #expect(await waitForScript(box, count: 2))

        // The old generation's hop is dropped even though a (new) scan is running…
        box.fire(from: 0, ScanProgress(itemsProcessed: 7, totalItems: 10))
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel.moduleProgress[SmartCareViewModel.duplicatesModuleName] == nil)

        // …while the new generation's hop lands.
        box.fire(from: 1, ScanProgress(itemsProcessed: 3, totalItems: 10))
        #expect(await waitForDuplicateProgress(viewModel, itemsProcessed: 3))

        viewModel.cancelScan()
    }

    // MARK: - Clean

    @Test("cleaning refuses a second call while files are moving")
    func cleanRefusesASecondCall() async throws {
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadFixture(.cleaning)
        guard case .cleaning(let selectedCount) = viewModel.phase else {
            Issue.record("fixture should be in .cleaning")
            return
        }

        let accepted = await viewModel.clean()

        #expect(accepted == false)
        guard case .cleaning(let stillSelectedCount) = viewModel.phase else {
            Issue.record("phase must stay .cleaning")
            return
        }
        #expect(stillSelectedCount == selectedCount)
    }

    @Test("clean with an empty selection does nothing")
    func emptySelectionDoesNothing() async throws {
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadFixture(.results)
        for path in viewModel.selectedPaths {
            viewModel.toggleSelection(path: path)
        }
        #expect(viewModel.selectedPaths.isEmpty)

        let accepted = await viewModel.clean()

        #expect(accepted == false)
        #expect(viewModel.lifecycle == .results)
    }

    @Test("failures are counted, surfaced and never turned into a success")
    func failuresAreCountedAndSurfaced() async throws {
        let missing = Self.missingItems(3)
        let viewModel = SmartCareViewModelTests.makeViewModel()
        viewModel.loadFixtureResults(junkItems: missing, duplicateGroups: [])
        #expect(viewModel.selectedItems.count == missing.count)

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedBytes == 0)
        #expect(movedCount == 0)
        #expect(failedCount == missing.count)
        #expect(viewModel.lastFailedItems.count == missing.count)
        #expect(viewModel.lastFailedItems.allSatisfy { !$0.reason.isEmpty })
        #expect(viewModel.reviewItems.count == missing.count, "nothing succeeded, so nothing left the list")
    }

    @Test("a real scan and clean move the selection through the one trash route")
    func realScanAndCleanMovesTheSelection() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("smartcare-e2e-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // One junk file under its own cache folder (so the junk rule doesn't swallow
        // the duplicate pair) and one duplicate pair (same payload → same size → one
        // set). UUID-embedded names keep the Trash landing path deterministic even
        // against leftovers from earlier runs; the Trash cleanup is a `defer`.
        let junkDir = root.appendingPathComponent("Cache", isDirectory: true)
        try fileManager.createDirectory(at: junkDir, withIntermediateDirectories: true)
        let junkName = "smartcare-junk-\(UUID().uuidString).db"
        let dupName = "smartcare-dup-\(UUID().uuidString).dat"
        let olderDupName = "smartcare-dup-old-\(UUID().uuidString).dat"
        try Data("smartcare junk payload".utf8).write(to: junkDir.appendingPathComponent(junkName))
        let payload = Data("smartcare duplicate payload".utf8)
        try payload.write(to: root.appendingPathComponent(dupName))
        try payload.write(to: root.appendingPathComponent(olderDupName))
        // The newest copy by modified date is the keep (engine rule) — set it explicitly.
        let newerDate = Date(timeIntervalSince1970: 1_795_600_000) // 2026-11-24
        let olderDate = Date(timeIntervalSince1970: 1_794_700_000) // 2026-11-23
        try fileManager.setAttributes([.modificationDate: newerDate],
                                      ofItemAtPath: root.appendingPathComponent(dupName).path)
        try fileManager.setAttributes([.modificationDate: olderDate],
                                      ofItemAtPath: root.appendingPathComponent(olderDupName).path)

        let trash = try fileManager.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        defer {
            for name in [junkName, olderDupName] {
                try? fileManager.removeItem(at: trash.appendingPathComponent(name))
            }
        }

        let rule = JunkRule(id: "test-smartcare",
                            label: "Test Caches",
                            kind: .directPath(junkDir.path),
                            defaultSeverity: .safe)
        let viewModel = Self.makeViewModel(
            rootPath: root.path,
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: JunkScanner(rules: [rule]))
            ]))

        viewModel.startScan()
        #expect(await waitForPhase(viewModel, .results))

        #expect(viewModel.junkItemsCount == 1)
        #expect(viewModel.duplicateSetCount == 1)
        guard viewModel.duplicateGroups.count == 1 else {
            Issue.record("expected exactly one duplicate set, got \(viewModel.duplicateGroups.count)")
            return
        }
        let keep = viewModel.reviewItems.first { $0.isRecommendedKeep }
        #expect(keep?.item.path == root.appendingPathComponent(dupName).path,
                "the newest copy by modified date is the keep")
        #expect(viewModel.selectedItems.count == 2, "junk file + the older copy, never the keep")
        let expectedBytes = viewModel.totalSelectedBytes

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedCount == 2)
        #expect(movedBytes == expectedBytes)
        #expect(failedCount == 0)
        #expect(viewModel.reviewItems.count == 1, "only the keep remains listed")
        #expect(!fileManager.fileExists(atPath: junkDir.appendingPathComponent(junkName).path))
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent(olderDupName).path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent(dupName).path),
                "the keep copy must survive the clean")
    }

    @Test("a duplicate keep the junk scan also found stays locked and is never trashed")
    func junkHitKeepStaysLockedAndSurvivesTheClean() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("smartcare-keeplock-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // The P2 setup: the duplicate pair's keep (newest by modified date) sits inside
        // the junk rule's folder, so BOTH legs report the same path. The builder must
        // reserve it for the duplicate set — if junk claimed the row, Smart Care would
        // preselect the "safe" junk copy and Clean would trash every copy of the file.
        let cacheDir = root.appendingPathComponent("Cache", isDirectory: true)
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let keepName = "smartcare-keep-\(UUID().uuidString).dat"
        let olderName = "smartcare-keep-old-\(UUID().uuidString).dat"
        let junkName = "smartcare-keeplock-junk-\(UUID().uuidString).db"
        let payload = Data("smartcare keep-lock duplicate payload".utf8)
        try payload.write(to: cacheDir.appendingPathComponent(keepName))
        try payload.write(to: root.appendingPathComponent(olderName))
        try Data("smartcare keep-lock junk payload".utf8)
            .write(to: cacheDir.appendingPathComponent(junkName))
        // The newest copy by modified date is the keep (engine rule) — set it explicitly.
        let newerDate = Date(timeIntervalSince1970: 1_795_600_000) // 2026-11-24
        let olderDate = Date(timeIntervalSince1970: 1_794_700_000) // 2026-11-23
        try fileManager.setAttributes([.modificationDate: newerDate],
                                      ofItemAtPath: cacheDir.appendingPathComponent(keepName).path)
        try fileManager.setAttributes([.modificationDate: olderDate],
                                      ofItemAtPath: root.appendingPathComponent(olderName).path)

        let trash = try fileManager.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        defer {
            for name in [junkName, olderName, keepName] {
                try? fileManager.removeItem(at: trash.appendingPathComponent(name))
            }
        }

        let rule = JunkRule(id: "test-keeplock",
                            label: "Test Caches",
                            kind: .directPath(cacheDir.path),
                            defaultSeverity: .safe)
        let viewModel = Self.makeViewModel(
            rootPath: root.path,
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: JunkScanner(rules: [rule]))
            ]))

        viewModel.startScan()
        #expect(await waitForPhase(viewModel, .results))

        #expect(viewModel.duplicateSetCount == 1)
        #expect(viewModel.junkItemsCount == 1, "only the unrelated cache file counts as junk — never the keep")
        guard let keep = viewModel.reviewItems.first(where: { $0.isRecommendedKeep }) else {
            Issue.record("the junk-hit duplicate keep is missing from the review")
            return
        }
        #expect(keep.item.path == cacheDir.appendingPathComponent(keepName).path,
                "the newest copy by modified date is the keep, even though junk also found it")
        #expect(keep.sourceModule == SmartCareViewModel.duplicatesModuleName,
                "the keep belongs to its duplicate set, not to the junk section")
        #expect(!viewModel.selectedPaths.contains(keep.id),
                "pre-selection must never include the keep")
        #expect(viewModel.selectedPaths.count == 2, "the unrelated junk file + the older copy, never the keep")
        let expectedBytes = viewModel.totalSelectedBytes

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedCount == 2)
        #expect(movedBytes == expectedBytes)
        #expect(failedCount == 0)
        #expect(viewModel.reviewItems.count == 1, "only the keep remains listed")
        #expect(fileManager.fileExists(atPath: cacheDir.appendingPathComponent(keepName).path),
                "the keep copy must survive the clean")
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent(olderName).path))
        #expect(!fileManager.fileExists(atPath: cacheDir.appendingPathComponent(junkName).path))
    }

    // MARK: - Builder (pure grouping)

    @Test("builder: junk groups by rule in first-appearance order, duplicates by set")
    func builderGroupsByRuleAndSet() throws {
        let junk = [
            Self.missingItems(1)[0],
            ScanItem(path: "/tmp/x/caution.db", size: 10, kind: .file, severity: .caution,
                     sourceLabel: "User Logs (7+ days old)"),
            ScanItem(path: "/tmp/x/other.db", size: 11, kind: .file, severity: .safe,
                     sourceLabel: nil),
        ]
        let setA = DuplicateGroup(id: "a", items: [
            ScanItem(path: "/tmp/x/a-new.bin", size: 5, kind: .file,
                     lastModified: Date(timeIntervalSince1970: 100)),
            ScanItem(path: "/tmp/x/a-old.bin", size: 5, kind: .file,
                     lastModified: Date(timeIntervalSince1970: 50)),
        ])
        let output = SmartCareReviewBuilder.build(junkItems: junk,
                                                  junkModuleID: "Junk & Cache",
                                                  duplicatesModuleID: "Duplicate files",
                                                  duplicateGroups: [setA])

        // Junk section: one group per rule label, first-appearance order, nil → "Other".
        #expect(output.junkGroups.map(\.title) == ["User App Caches", "User Logs (7+ days old)", "Other"])
        #expect(output.junkGroups.allSatisfy { $0.id.hasPrefix("junk:") })
        #expect(output.junkGroups[0].items.count == 1)
        #expect(output.junkGroups[0].sub == "1 file")

        // Duplicates section: one group per set, keep flag on the newest copy only.
        #expect(output.duplicateGroups.count == 1)
        #expect(output.duplicateGroups[0].id == "dup:a")
        #expect(output.duplicateGroups[0].sub == "2 copies")
        let keepFlags = output.duplicateGroups[0].items.map(\.isRecommendedKeep)
        #expect(keepFlags == [true, false], "the newest copy by modified date is the keep")

        // Every unique path lands exactly once, in group order.
        #expect(output.items.map(\.id) ==
                output.junkGroups.flatMap(\.items).map(\.id) +
                output.duplicateGroups.flatMap(\.items).map(\.id))
    }

    @Test("builder: a file both modules found is listed once, under junk")
    func builderDeduplicatesByPath() throws {
        // shared.db is deliberately NOT this set's keep (twin.db is newer), so it stays
        // a single junk row. A set's keep is reserved for the duplicates pass — see
        // builderReservesAJunkHitKeepForItsDuplicateSet below.
        let shared = ScanItem(path: "/tmp/x/shared.db", size: 7, kind: .file, severity: .safe,
                              sourceLabel: "User App Caches")
        let set = DuplicateGroup(id: "s", items: [
            shared,
            ScanItem(path: "/tmp/x/twin.db", size: 7, kind: .file,
                     lastModified: Date(timeIntervalSince1970: 10)),
        ])
        let output = SmartCareReviewBuilder.build(junkItems: [shared],
                                                  junkModuleID: "Junk & Cache",
                                                  duplicatesModuleID: "Duplicate files",
                                                  duplicateGroups: [set])
        #expect(output.items.count == 2, "shared.db appears once")
        #expect(output.items.filter { $0.id == shared.path }.count == 1)
        #expect(output.junkGroups[0].items.map(\.id) == [shared.path])
        #expect(output.duplicateGroups[0].items.map(\.id) == ["/tmp/x/twin.db"],
                "the duplicate section keeps only the paths junk didn't claim")
    }

    @Test("builder: a set's keep that junk also found is the locked keep of its set, never a junk row")
    func builderReservesAJunkHitKeepForItsDuplicateSet() throws {
        // The keep copy also matched a junk rule (e.g. a copy under ~/Library/Caches).
        // The junk pass must leave that path to the duplicates pass, which lists it
        // exactly once, locked — never as a selectable safe-junk row.
        let keep = ScanItem(path: "/tmp/x/keep.db", size: 7, kind: .file,
                            lastModified: Date(timeIntervalSince1970: 100),
                            severity: .safe, sourceLabel: "User App Caches")
        let older = ScanItem(path: "/tmp/x/twin.db", size: 7, kind: .file,
                             lastModified: Date(timeIntervalSince1970: 10))
        let unrelatedJunk = ScanItem(path: "/tmp/x/other.db", size: 11, kind: .file,
                                     severity: .safe, sourceLabel: "User App Caches")
        let set = DuplicateGroup(id: "s", items: [keep, older])

        let output = SmartCareReviewBuilder.build(junkItems: [keep, unrelatedJunk],
                                                  junkModuleID: "Junk & Cache",
                                                  duplicatesModuleID: "Duplicate files",
                                                  duplicateGroups: [set])

        // The keep path still appears exactly once — under its duplicate set, locked.
        #expect(output.items.filter { $0.id == keep.path }.count == 1)
        let keepRow = output.items.first { $0.id == keep.path }
        #expect(keepRow?.sourceModule == "Duplicate files")
        #expect(keepRow?.groupID == "dup:s")
        #expect(keepRow?.isRecommendedKeep == true)
        #expect(!output.junkGroups.flatMap(\.items).contains { $0.id == keep.path },
                "the keep must never be listed as a junk row")

        // Junk keeps only the paths that are not a set's keep.
        #expect(output.junkGroups.flatMap(\.items).map(\.id) == ["/tmp/x/other.db"])

        // The set still lists every copy, keep flag on the newest only.
        #expect(output.duplicateGroups[0].items.map(\.id) == [keep.path, "/tmp/x/twin.db"])
        #expect(output.duplicateGroups[0].items.map(\.isRecommendedKeep) == [true, false])

        // Every unique path still lands exactly once, in group order.
        #expect(output.items.map(\.id) ==
                output.junkGroups.flatMap(\.items).map(\.id) +
                output.duplicateGroups.flatMap(\.items).map(\.id))
    }

    // MARK: - Lifecycle mapping (the frame's contract)

    @Suite("Lifecycle mapping · Smart Care")
    @MainActor
    struct LifecycleMapping {

        @Test("state table: every lifecycle state maps from the phase spec §5.2 defines")
        func stateTable() throws {
            let viewModel = SmartCareViewModelTests.makeViewModel()

            #expect(viewModel.phase == .idle)
            #expect(viewModel.lifecycle == .start)

            viewModel.loadFixture(.scanning)
            #expect(viewModel.phase == .scanning)
            #expect(viewModel.lifecycle == .scanning)

            viewModel.loadFixture(.results)
            #expect(viewModel.phase == .results)
            #expect(!viewModel.reviewItems.isEmpty)
            #expect(viewModel.lifecycle == .results)

            viewModel.loadFixture(.review)
            #expect(viewModel.phase == .review)
            #expect(viewModel.lifecycle == .review)

            viewModel.loadFixture(.cleaning)
            guard case .cleaning = viewModel.phase else {
                Issue.record("expected .cleaning, got \(viewModel.phase)")
                return
            }
            #expect(viewModel.lifecycle == .cleaning)

            viewModel.loadFixture(.done)
            guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
                Issue.record("expected .done, got \(viewModel.phase)")
                return
            }
            #expect(movedBytes > 0)
            #expect(movedCount > 0)
            #expect(failedCount == 0)
            #expect(viewModel.lifecycle == .done)

            viewModel.loadFixture(.empty)
            #expect(viewModel.phase == .results)
            #expect(viewModel.reviewItems.isEmpty)
            #expect(viewModel.lifecycle == .empty)

            viewModel.loadFixture(.error)
            guard case .failed(let message) = viewModel.phase else {
                Issue.record("expected .failed, got \(viewModel.phase)")
                return
            }
            #expect(!message.isEmpty)
            #expect(viewModel.lifecycle == .error)
        }

        @Test("partial failure keeps the results lifecycle and never reads empty")
        func partialFailureMapping() throws {
            let viewModel = SmartCareViewModelTests.makeViewModel()
            viewModel.loadPartialFailureFixture()
            #expect(viewModel.phase == .results)
            #expect(viewModel.lifecycle == .results)
            #expect(viewModel.lifecycle != .empty)
        }

        @Test("scan progress maps without inventing a total the engine didn't report")
        func scanningAggregateIsEngineBacked() throws {
            let viewModel = SmartCareViewModelTests.makeViewModel()
            viewModel.loadFixture(.scanning)
            #expect(viewModel.phase == .scanning)
            // The fixture records real per-module figures; the aggregate mean exists
            // only once every in-flight module reported one.
            #expect(viewModel.aggregateProgress != nil)
            #expect(viewModel.lifecycle == .scanning)
        }
    }
}

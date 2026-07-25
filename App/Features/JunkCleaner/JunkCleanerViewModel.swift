import Foundation
import Observation
import SwiftData
import CleanCore

@MainActor
@Observable
final class JunkCleanerViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaning
        case done(reclaimedBytes: Int64)
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [ScanItem] = []
    var selectedPaths: Set<String> = []
    private(set) var errorMessage: String?

    private let scanner: JunkScanner
    private let cleaner = DefaultCleaner()
    private let privilegedHelperClient: PrivilegedHelperClient
    private let modelContext: ModelContext

    let progressTracker = ScanProgressTracker()
    private var scanTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        scanner: JunkScanner = JunkScanner(),
        privilegedHelperClient: PrivilegedHelperClient = PrivilegedHelperClient()
    ) {
        self.modelContext = modelContext
        self.scanner = scanner
        self.privilegedHelperClient = privilegedHelperClient
    }

    var totalSelectedBytes: Int64 {
        items.filter { selectedPaths.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    /// The categories this scan covers, in the order `JunkScanner` walks
    /// them — used to render one `StepRowView` per rule while scanning.
    var ruleLabels: [String] { JunkRule.allowlist.map(\.label) }

    func startScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .idle }
    }

    private func performScan() async {
        phase = .scanning
        errorMessage = nil
        progressTracker.start()
        do {
            let ignoredPaths = try fetchIgnoredPaths()
            let scanned = try await scanner.scan(onProgress: { [weak self] progress in
                Task { @MainActor in self?.progressTracker.record(progress) }
            })
            guard !Task.isCancelled else { return }
            items = scanned.filter { !ignoredPaths.contains($0.path) }
            // Only pre-select items that are both rule-classified safe and
            // don't need the not-yet-built privileged helper — never
            // auto-select anything requiring a closer look.
            selectedPaths = Set(
                items
                    .filter { $0.severity == .safe && !$0.requiresPrivilegedHelper }
                    .map(\.path)
            )
            phase = .results
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func clean() async {
        let toClean = items.filter { selectedPaths.contains($0.path) }
        guard !toClean.isEmpty else { return }
        phase = .cleaning

        let normalItems = toClean.filter { !$0.requiresPrivilegedHelper }
        let privilegedItems = toClean.filter(\.requiresPrivilegedHelper)

        do {
            let result = try await cleaner.clean(normalItems)
            var succeeded = result.succeeded
            var failed = result.failed

            // Root-owned system-cache paths route through the Phase 8
            // privileged helper instead of the local trashItem-based
            // Cleaner, which can't touch them from a user-context process.
            for item in privilegedItems {
                do {
                    try await privilegedHelperClient.trashSystemPath(item.path)
                    succeeded.append(item)
                } catch {
                    failed.append(CleanResult.FailedItem(item: item, reason: error.localizedDescription))
                }
            }

            let succeededPaths = Set(succeeded.map(\.path))
            items.removeAll { succeededPaths.contains($0.path) }
            selectedPaths.subtract(succeededPaths)
            let reclaimedBytes = succeeded.reduce(Int64(0)) { $0 + $1.size }
            phase = .done(reclaimedBytes: reclaimedBytes)
            if !failed.isEmpty {
                errorMessage = "\(failed.count) item\(failed.count == 1 ? "" : "s") couldn't be removed: \(failed.first?.reason ?? "")"
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .results
        }
    }

    func ignore(_ item: ScanItem) {
        modelContext.insert(IgnoredItem(path: item.path))
        do {
            try modelContext.save()
        } catch {
            // Don't drop the item from the list on a failed save — the user
            // would believe "ignore" took effect when nothing was persisted,
            // and the item would silently reappear on the next scan.
            errorMessage = "Couldn't save ignore list: \(error.localizedDescription)"
            return
        }
        items.removeAll { $0.path == item.path }
        selectedPaths.remove(item.path)
    }

    func backToResults() {
        phase = .results
    }

    private func fetchIgnoredPaths() throws -> Set<String> {
        let descriptor = FetchDescriptor<IgnoredItem>()
        return Set(try modelContext.fetch(descriptor).map(\.path))
    }
}

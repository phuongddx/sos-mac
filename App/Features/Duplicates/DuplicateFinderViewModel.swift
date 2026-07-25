import Foundation
import Observation
import CleanCore

@MainActor
@Observable
final class DuplicateFinderViewModel {
    enum Mode: String, CaseIterable, Hashable {
        case exact = "Exact Duplicates"
        case similarImages = "Similar Images"
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case done(reclaimedBytes: Int64)
    }

    let rootPath: String
    var mode: Mode = .exact
    private(set) var phase: Phase = .idle
    private(set) var groups: [DuplicateGroup] = []
    var selectedPaths: Set<String> = []
    private(set) var errorMessage: String?
    /// Files that couldn't be hashed/decoded (permission denied, deleted
    /// mid-scan, undecodable image) — surfaced so results never look more
    /// exhaustive than they actually are.
    private(set) var skippedCount = 0

    private var scanTask: Task<Void, Never>?

    init(rootPath: String = NSHomeDirectory()) {
        self.rootPath = rootPath
    }

    var totalSelectedBytes: Int64 {
        groups
            .flatMap(\.items)
            .filter { selectedPaths.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }

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
        skippedCount = 0

        let finder = DuplicateFinder(rootPath: rootPath)
        let result: DuplicateScanResult
        do {
            switch mode {
            case .exact:
                result = try await finder.findExactDuplicateGroups()
            case .similarImages:
                result = try await finder.findSimilarImageGroups()
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            phase = .idle
            return
        }

        guard !Task.isCancelled else { return }

        groups = result.groups
        skippedCount = result.skippedCount
        // "Keep newest" default: pre-select every item except the one with
        // the newest modification date — user can override any pre-check
        // before confirming, nothing is deleted without that confirmation.
        selectedPaths = Set(
            result.groups.flatMap { group in
                group.items
                    .filter { $0.path != group.recommendedKeepPath }
                    .map(\.path)
            }
        )
        phase = .results
    }

    func toggleSelection(for path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    func clean() async {
        let allItems = groups.flatMap(\.items)
        let toClean = allItems.filter { selectedPaths.contains($0.path) }
        guard !toClean.isEmpty else { return }

        do {
            let result = try await DefaultCleaner().clean(toClean)
            let succeededPaths = Set(result.succeeded.map(\.path))
            groups = groups.compactMap { group in
                let remaining = group.items.filter { !succeededPaths.contains($0.path) }
                // A group of 1 is no longer a duplicate group at all.
                return remaining.count >= 2 ? DuplicateGroup(id: group.id, items: remaining) : nil
            }
            selectedPaths.subtract(succeededPaths)
            phase = .done(reclaimedBytes: result.reclaimedBytes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func backToResults() {
        phase = .results
    }

    /// The only way back to `.idle` from `.results`/`.done` — without this,
    /// rescanning or switching between Exact/Similar mode required navigating
    /// away from the screen entirely and relying on view teardown to reset
    /// state, which isn't a real user-facing action.
    func startNewScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        groups = []
        selectedPaths = []
        skippedCount = 0
        errorMessage = nil
    }
}

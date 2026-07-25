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
    private let modelContext: ModelContext

    init(modelContext: ModelContext, scanner: JunkScanner = JunkScanner()) {
        self.modelContext = modelContext
        self.scanner = scanner
    }

    var totalSelectedBytes: Int64 {
        items.filter { selectedPaths.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    func startScan() async {
        phase = .scanning
        errorMessage = nil
        do {
            let ignoredPaths = try fetchIgnoredPaths()
            let scanned = try await scanner.scan()
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
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func clean() async {
        let toClean = items.filter { selectedPaths.contains($0.path) }
        guard !toClean.isEmpty else { return }
        phase = .cleaning
        do {
            let result = try await cleaner.clean(toClean)
            let succeededPaths = Set(result.succeeded.map(\.path))
            items.removeAll { succeededPaths.contains($0.path) }
            selectedPaths.subtract(succeededPaths)
            phase = .done(reclaimedBytes: result.reclaimedBytes)
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

import Foundation
import Observation
import SwiftData
import CleanCore

@MainActor
@Observable
final class ProtectionViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case quarantining
        case summary(quarantinedCount: Int, failureCount: Int)
    }

    private(set) var phase: Phase = .idle
    private(set) var findings: [ThreatFinding] = []
    var selectedPaths: Set<String> = []
    private(set) var errorMessage: String?
    private(set) var quarantinedRecords: [QuarantineRecord] = []

    private let modelContext: ModelContext
    private let scanner: ProtectionScanner
    private let quarantineManager = QuarantineManager()
    private let virusTotalClient: VirusTotalClient?
    private var scanTask: Task<Void, Never>?
    let progressTracker = ScanProgressTracker()

    init(
        modelContext: ModelContext,
        signatureDatabase: SignatureDatabase = .bundledBaseline,
        virusTotalConfig: VirusTotalClient.Config = .init()
    ) {
        self.modelContext = modelContext
        self.scanner = ProtectionScanner(signatureDatabase: signatureDatabase)
        self.virusTotalClient = virusTotalConfig.isConfigured ? VirusTotalClient(config: virusTotalConfig) : nil
        self.quarantinedRecords = Self.fetchRecords(from: modelContext)
    }

    func startScan() {
        guard phase != .scanning else { return } // re-entrancy guard: ignore a second tap mid-scan
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
        let generation = progressTracker.start()
        do {
            findings = try await scanner.scan(onProgress: { [weak self] progress in
                Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
            })
            selectedPaths = [] // never auto-select a quarantine target — same invariant as Duplicates/SmartCare/CloudCleanup
            phase = .results
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func toggleSelection(for path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// The explicit confirmation step — nothing above this quarantines
    /// anything on its own. Never claims to replace XProtect/Gatekeeper;
    /// this only acts on what its own static scan found.
    func quarantineSelected() async {
        guard phase != .quarantining else { return } // re-entrancy guard: a fast double-tap shouldn't quarantine twice
        let toQuarantine = findings.filter { selectedPaths.contains($0.path) }
        guard !toQuarantine.isEmpty else { return }

        phase = .quarantining
        var succeededCount = 0
        var failedCount = 0
        var untrackedPaths: [String] = []

        for finding in toQuarantine {
            do {
                let quarantined = try quarantineManager.quarantine(finding)
                do {
                    try persist(quarantined)
                    succeededCount += 1
                } catch {
                    // The file WAS physically moved by this point — don't
                    // report a clean success (nothing tracks it for
                    // restore), but don't pretend it's still at its
                    // original path either. Same "never claim a failed save
                    // succeeded" rule as JunkCleanerViewModel.ignore().
                    failedCount += 1
                    untrackedPaths.append(quarantined.quarantinePath)
                }
            } catch {
                failedCount += 1
            }
        }

        let quarantinedPaths = Set(toQuarantine.map(\.path))
        findings.removeAll { quarantinedPaths.contains($0.path) }
        selectedPaths.subtract(quarantinedPaths)
        quarantinedRecords = Self.fetchRecords(from: modelContext)
        if !untrackedPaths.isEmpty {
            errorMessage = "Moved but not tracked for restore — find manually in the Quarantine folder: \(untrackedPaths.joined(separator: ", "))"
        }
        phase = .summary(quarantinedCount: succeededCount, failureCount: failedCount)
    }

    func restore(_ record: QuarantineRecord) {
        let file = QuarantinedFile(
            originalPath: record.originalPath,
            quarantinePath: record.quarantinePath,
            threatIdentifier: record.threatIdentifier,
            quarantinedAt: record.quarantinedAt
        )
        do {
            try quarantineManager.restore(file)
        } catch {
            errorMessage = "Couldn't restore: \(error.localizedDescription)"
            return
        }
        modelContext.delete(record)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Restored the file, but couldn't update the quarantine record: \(error.localizedDescription)"
        }
        quarantinedRecords = Self.fetchRecords(from: modelContext)
    }

    /// Supplementary only — never called as part of the scan itself, so
    /// Protection stays fully functional offline. Returns `nil` (rather than
    /// surfacing the error) when VirusTotal isn't configured or the lookup
    /// fails; this is a bonus signal, not something the UI should block on.
    func lookupVirusTotal(for finding: ThreatFinding) async -> VirusTotalVerdict? {
        guard let virusTotalClient, finding.detectionMethod == .hash else { return nil }
        return try? await virusTotalClient.lookup(sha256: finding.identifier)
    }

    func startNewScan() {
        phase = .idle
        findings = []
        selectedPaths = []
        errorMessage = nil
    }

    private func persist(_ file: QuarantinedFile) throws {
        let record = QuarantineRecord(
            originalPath: file.originalPath,
            quarantinePath: file.quarantinePath,
            threatIdentifier: file.threatIdentifier,
            quarantinedAt: file.quarantinedAt
        )
        modelContext.insert(record)
        try modelContext.save()
    }

    private static func fetchRecords(from modelContext: ModelContext) -> [QuarantineRecord] {
        let descriptor = FetchDescriptor<QuarantineRecord>(sortBy: [SortDescriptor(\.quarantinedAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

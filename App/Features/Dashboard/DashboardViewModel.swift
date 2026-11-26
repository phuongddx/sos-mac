import Foundation
import CleanCore

/// What the Dashboard's snapshot row and the Performance card show — one reading, taken when
/// the page opened (spec §5.1, §6.4: `PerformanceSnapshot`-style one-off, no polling, no "live"
/// claim). Every field is optional: a value the system did not give is **omitted** by the view,
/// never replaced by a placeholder (D6, spec §11.5).
///
/// "Memory in use" is `MemoryInfo.inUseBytes` (wired + active + compressed, plan PR E1); the
/// legacy `usedBytes` (total − free, ~99 % on an idle Mac) is never read here.
struct DashboardSnapshot: Equatable, Sendable {
    struct Memory: Equatable, Sendable {
        let inUseBytes: UInt64
        let totalBytes: UInt64
    }

    let oneMinuteLoad: Double?
    let memory: Memory?
    let thermalState: ThermalState?

    init(oneMinuteLoad: Double?, memory: Memory?, thermalState: ThermalState?) {
        self.oneMinuteLoad = oneMinuteLoad
        self.memory = memory
        self.thermalState = thermalState
    }

    /// One reading from the engine's public readers — the same sources as Smart Care's health
    /// check and Performance (`SysctlReader`, `MachHostStats`, `IOKitSensors`).
    static func capture() -> DashboardSnapshot {
        let memoryInfo = MachHostStats.memoryInfo()
        return DashboardSnapshot(
            oneMinuteLoad: SysctlReader.loadAverages()?.oneMinute,
            memory: memoryInfo.map { Memory(inUseBytes: $0.inUseBytes, totalBytes: $0.totalBytes) },
            thermalState: IOKitSensors.thermalState())
    }

    /// Nothing readable at all → the view leaves the whole row out.
    var isEmpty: Bool {
        oneMinuteLoad == nil && memory == nil && thermalState == nil
    }

    /// "2.41" — two decimals, the prototype's format. `nil` when the load is unavailable.
    var loadText: String? {
        oneMinuteLoad.map { String(format: "%.2f", $0) }
    }

    var memoryInUseText: String? {
        memory.map { ByteFormatter.string(fromByteCount: Int64(clamping: $0.inUseBytes)) }
    }

    /// "of 16 GB" — the total the in-use figure is measured against.
    var memoryTotalText: String? {
        memory.map { ByteFormatter.string(fromByteCount: Int64(clamping: $0.totalBytes)) }
    }

    /// In-use share of physical memory, whole percent. `nil` when the total is unknown or zero.
    var memoryPercent: Int? {
        guard let memory, memory.totalBytes > 0 else { return nil }
        let share = Double(memory.inUseBytes) / Double(memory.totalBytes) * 100
        return Int(min(max(share, 0), 100).rounded())
    }

    var thermalText: String? {
        thermalState.map { $0.rawValue.capitalized }
    }

    /// The Performance card's second line: the snapshot's load and memory figures, without a
    /// "live" dot (spec §5.1, §6.3). Only the parts that exist; `nil` when neither does.
    var performanceLine: String? {
        var parts: [String] = []
        if let loadText { parts.append("Load \(loadText)") }
        if let memoryPercent { parts.append("Memory \(memoryPercent)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The Dashboard's two actions. The Dashboard has no lifecycle (spec §5.1): it is a launcher,
/// so there is no phase to model — only "open this module" and "Run Smart Care" (N3).
///
/// Dependencies are closures so the launch can be proved without a window or a real scan
/// (`DashboardViewModelTests`): the view passes `{ store.smartCare }` and the shell's
/// selection setter, a test passes a hermetic Smart Care and a recorder.
@MainActor
struct DashboardLauncher {
    private let smartCare: @MainActor () -> SmartCareViewModel
    private let navigate: @MainActor (SidebarDestination) -> Void

    init(smartCare: @escaping @MainActor () -> SmartCareViewModel,
         navigate: @escaping @MainActor (SidebarDestination) -> Void) {
        self.smartCare = smartCare
        self.navigate = navigate
    }

    /// A card or "Open Space Lens": navigation only, nothing starts.
    func open(_ destination: SidebarDestination) {
        navigate(destination)
    }

    /// N3 — "Run Smart Care" opens Smart Care **and starts the scan**. Returns whether a scan
    /// was started.
    ///
    /// - A scan or clean already running: `startScan()` refuses (PR 3 re-entrancy guard), so the
    ///   user simply lands on the screen showing that work — nothing restarts.
    /// - The user is mid-review: results and selection are kept (spec §6.6 / N1) — the screen
    ///   opens where they left it; a new scan would discard the selection.
    /// - Any other phase (idle, results, done, failed): a fresh scan.
    @discardableResult
    func runSmartCare() -> Bool {
        let module = smartCare()
        let started: Bool
        if module.phase == .review {
            started = false
        } else {
            started = module.startScan()
        }
        navigate(.smartCare)
        return started
    }
}

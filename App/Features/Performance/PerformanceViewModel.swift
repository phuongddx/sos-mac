import Foundation
import Observation
import ServiceManagement
import AppKit
import CleanCore

@MainActor
@Observable
final class PerformanceViewModel {
    private static let pollInterval: Duration = .seconds(2) // conservative — see Phase 4 risk notes on battery life

    private(set) var cpuUsagePercent: Double?
    private(set) var memoryInfo: MemoryInfo?
    private(set) var swapUsage: SysctlReader.SwapUsage?
    private(set) var thermalState: ThermalState = .nominal
    private(set) var loadAverages: (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)?
    private(set) var bootTime: Date?
    private(set) var loginItems: [LoginItemEntry] = []
    private(set) var isAppleSilicon = false

    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?
    private(set) var maintenanceMessage: String?

    let privilegedHelperClient = PrivilegedHelperClient()

    private var previousCPUTicks: CPUTicks?

    /// Runs directly inside the caller's own `.task` closure rather than
    /// spawning a second, unstructured `Task` tracked via a stored handle —
    /// SwiftUI's `.task` cancels *its own* task automatically on view
    /// disappearance; a detached `Task` stored in a property is invisible to
    /// that mechanism and depends entirely on `.onDisappear` firing to ever
    /// stop, which isn't guaranteed in every SwiftUI container (e.g. some
    /// lazy/tabbed containers skip `onDisappear` on the outgoing view).
    /// Making cancellation structural removes that whole class of risk.
    func runPollingLoop() async {
        isAppleSilicon = IOKitSensors.isAppleSilicon()
        bootTime = SysctlReader.bootTime()
        loginItems = LoginItemsManager.listInstalledAgents()
        launchAtLoginStatus = LoginItemsManager.mainAppLoginItemStatus()
        previousCPUTicks = nil // fresh baseline each time polling (re)starts

        while !Task.isCancelled {
            sampleOnce()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func sampleOnce() {
        if let current = MachHostStats.cpuTicks() {
            if let previous = previousCPUTicks {
                cpuUsagePercent = MachHostStats.cpuUsagePercent(from: previous, to: current)
            }
            previousCPUTicks = current
        }

        memoryInfo = MachHostStats.memoryInfo()
        swapUsage = SysctlReader.swapUsage()
        thermalState = IOKitSensors.thermalState()
        loadAverages = SysctlReader.loadAverages()
    }

    func toggleLaunchAtLogin() {
        errorMessage = nil
        do {
            if launchAtLoginStatus == .enabled {
                try LoginItemsManager.unregisterMainAppAsLoginItem()
            } else {
                try LoginItemsManager.registerMainAppAsLoginItem()
            }
            launchAtLoginStatus = LoginItemsManager.mainAppLoginItemStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Free up RAM / Flush DNS route through `PrivilegedHelperClient` since
    /// `purge`/`killall -HUP mDNSResponder` need root. `.requiresApproval` is
    /// the expected, common first-run state — `SMAppService.daemon`
    /// mandates a System Settings approval, not a failure to silently
    /// swallow (see Phase 8's own requirement).
    func freeUpRAM() async {
        await runPrivilegedMaintenance(actionName: "Free up RAM") { [privilegedHelperClient] in
            try await privilegedHelperClient.purgeMemory()
        }
    }

    func flushDNSCache() async {
        await runPrivilegedMaintenance(actionName: "Flush DNS Cache") { [privilegedHelperClient] in
            try await privilegedHelperClient.flushDNSCache()
        }
    }

    private func runPrivilegedMaintenance(actionName: String, operation: () async throws -> Void) async {
        errorMessage = nil
        maintenanceMessage = nil
        do {
            try await operation()
            maintenanceMessage = "\(actionName) completed."
        } catch PrivilegedHelperError.notRegistered {
            do {
                try privilegedHelperClient.register()
                maintenanceMessage = "Privileged helper installed — approve it in System Settings > General > Login Items, then try again."
                SMAppService.openSystemSettingsLoginItems()
            } catch {
                errorMessage = "Couldn't install the privileged helper: \(error.localizedDescription)"
            }
        } catch PrivilegedHelperError.requiresApproval {
            maintenanceMessage = "Approve the privileged helper in System Settings > General > Login Items, then try again."
            SMAppService.openSystemSettingsLoginItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Manual affordance until Phase 8/9 wires real `SMAppService.agent`
    /// auto-launch registration for the helper (that needs release-style
    /// signing to test reliably) — the build embeds MenuBarHelper.app at
    /// Contents/Library/LoginItems, so it exists on disk, but nothing
    /// launches it automatically yet.
    func openMenuBarWidget() {
        errorMessage = nil
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/MenuBarHelper.app")
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            errorMessage = "Menu bar widget not found in this build."
            return
        }
        NSWorkspace.shared.open(helperURL)
    }
}

import Foundation
import SwiftData
import CleanCore

/// The app-level session store (spec §6.6, plan PR 3): owns one instance of
/// every feature view model, so results, selections and running scans survive
/// navigation. Views take their view model from here (`.environment(store)`)
/// instead of owning `@State` instances that are recreated with the view.
///
/// View models are created lazily on first access — the sidebar's busy-dot
/// query never creates one — and live for the whole session. Nothing cancels
/// a scan when its screen goes away; every scanning screen keeps an explicit
/// Stop control (OD-3: the scan keeps running in the background).
@MainActor
@Observable
final class ModuleStore {
    private let modelContext: ModelContext

    #if MAS_BUILD
    /// The sandbox build's folder grants (home, Applications). View models are
    /// (re)built from the granted roots; until a grant exists the gating UI
    /// shows the grant call-to-action instead of running a container-rooted
    /// scan that would report a fake empty result.
    let masAccess = MASAccessStore()
    #endif

    private var _smartCare: SmartCareViewModel?
    private var _junkCleaner: JunkCleanerViewModel?
    private var _duplicates: DuplicateFinderViewModel?
    private var _spaceLens: SpaceLensViewModel?
    private var _uninstaller: UninstallerViewModel?
    private var _updater: UpdaterViewModel?
    private var _performance: PerformanceViewModel?
    private var _cloudCleanup: CloudCleanupViewModel?
    private var _protection: ProtectionViewModel?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        #if MAS_BUILD
        masAccess.onAccessChanged = { [weak self] in
            self?.rebuildMASModules()
        }
        #endif
    }

    // One instance per module for the whole session; the first access builds it.

    var smartCare: SmartCareViewModel {
        if let _smartCare { return _smartCare }
        #if MAS_BUILD
        let home = masAccess.homeRoot ?? ""
        let module = SmartCareViewModel(
            rootPath: home,
            junkRules: JunkRule.sandboxAllowlist(homeRoot: home))
        #else
        let module = SmartCareViewModel()
        #endif
        _smartCare = module
        return module
    }

    var junkCleaner: JunkCleanerViewModel {
        if let _junkCleaner { return _junkCleaner }
        #if MAS_BUILD
        let module = JunkCleanerViewModel(
            modelContext: modelContext,
            rules: JunkRule.sandboxAllowlist(homeRoot: masAccess.homeRoot ?? ""))
        #else
        let module = JunkCleanerViewModel(modelContext: modelContext)
        #endif
        _junkCleaner = module
        return module
    }

    var duplicates: DuplicateFinderViewModel {
        if let _duplicates { return _duplicates }
        #if MAS_BUILD
        let module = DuplicateFinderViewModel(rootPath: masAccess.homeRoot ?? "")
        #else
        let module = DuplicateFinderViewModel()
        #endif
        _duplicates = module
        return module
    }

    var spaceLens: SpaceLensViewModel {
        if let _spaceLens { return _spaceLens }
        #if MAS_BUILD
        // Restore the last user-chosen folder (bookmark) so the start screen
        // offers it again; fall back to the container home, which the Home
        // row's grant gate replaces with the real home once granted.
        let module = SpaceLensViewModel(
            rootPath: masAccess.restoreSpaceLensFolder() ?? NSHomeDirectory(),
            persistSelection: { [masAccess] url in masAccess.storeSpaceLensFolder(url) })
        #else
        let module = SpaceLensViewModel()
        #endif
        _spaceLens = module
        return module
    }

    var uninstaller: UninstallerViewModel {
        if let _uninstaller { return _uninstaller }
        #if MAS_BUILD
        let module = UninstallerViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: masAccess.applicationsSearchDirectories))
        #else
        let module = UninstallerViewModel()
        #endif
        _uninstaller = module
        return module
    }

    var updater: UpdaterViewModel {
        if let _updater { return _updater }
        #if MAS_BUILD
        let module = UpdaterViewModel(
            enumerator: InstalledAppsEnumerator(searchDirectories: masAccess.applicationsSearchDirectories))
        #else
        let module = UpdaterViewModel()
        #endif
        _updater = module
        return module
    }

    var performance: PerformanceViewModel {
        if let _performance { return _performance }
        let module = PerformanceViewModel()
        _performance = module
        return module
    }

    var cloudCleanup: CloudCleanupViewModel {
        if let _cloudCleanup { return _cloudCleanup }
        let module = CloudCleanupViewModel()
        _cloudCleanup = module
        return module
    }

    var protection: ProtectionViewModel {
        if let _protection { return _protection }
        #if MAS_BUILD
        let module = ProtectionViewModel(
            modelContext: modelContext,
            locations: ProtectionLocation.sandboxAllowlist(homeRoot: masAccess.homeRoot ?? ""),
            homeDirectory: masAccess.homeRoot ?? "")
        #else
        let module = ProtectionViewModel(modelContext: modelContext)
        #endif
        _protection = module
        return module
    }

    #if MAS_BUILD
    /// Drops every home/applications-rooted view model so the next access
    /// rebuilds them against the fresh grant. Called right after a grant
    /// lands, before any scan has run on the new roots.
    private func rebuildMASModules() {
        _smartCare = nil
        _junkCleaner = nil
        _duplicates = nil
        _uninstaller = nil
        _updater = nil
        _protection = nil
    }
    #endif

    /// Whether the module behind a sidebar destination is mid-scan, for the
    /// sidebar's cyan busy dot (OD-3). Reads the stored optionals directly, so
    /// rendering the sidebar never creates a view model.
    func isScanning(_ destination: SidebarDestination) -> Bool {
        switch destination {
        case .dashboard:
            return false
        case .smartCare:
            return _smartCare?.phase == .scanning || (_smartCare?.isCleaning ?? false)
        case .junkCleaner:
            guard let junk = _junkCleaner else { return false }
            // PR 5: `.cleaning` carries its selection count, so it needs a pattern match.
            return junk.phase == .scanning || junk.isCleaning
        case .duplicateFinder:
            return _duplicates?.phase == .scanning
        case .spaceLens:
            // PR 8: `.cleaning` carries its selection count, so it needs the VM's
            // guard — the same pattern PR 5 set for Junk & Cache.
            return _spaceLens?.phase == .scanning || (_spaceLens?.isCleaning ?? false)
        case .uninstaller:
            return _uninstaller?.isInspectingAll == true
        case .updater:
            return _updater?.isCheckingAll == true
        case .performance:
            return false
        case .cloudCleanup:
            guard let cloud = _cloudCleanup else { return false }
            return cloud.isAnyProviderBusy
        case .protection:
            return _protection?.isBusy == true
        }
    }
}

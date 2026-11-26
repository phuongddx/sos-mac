import SwiftData

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
    }

    // One instance per module for the whole session; the first access builds it.

    var smartCare: SmartCareViewModel {
        if let _smartCare { return _smartCare }
        let module = SmartCareViewModel()
        _smartCare = module
        return module
    }

    var junkCleaner: JunkCleanerViewModel {
        if let _junkCleaner { return _junkCleaner }
        let module = JunkCleanerViewModel(modelContext: modelContext)
        _junkCleaner = module
        return module
    }

    var duplicates: DuplicateFinderViewModel {
        if let _duplicates { return _duplicates }
        let module = DuplicateFinderViewModel()
        _duplicates = module
        return module
    }

    var spaceLens: SpaceLensViewModel {
        if let _spaceLens { return _spaceLens }
        let module = SpaceLensViewModel()
        _spaceLens = module
        return module
    }

    var uninstaller: UninstallerViewModel {
        if let _uninstaller { return _uninstaller }
        let module = UninstallerViewModel()
        _uninstaller = module
        return module
    }

    var updater: UpdaterViewModel {
        if let _updater { return _updater }
        let module = UpdaterViewModel()
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
        let module = ProtectionViewModel(modelContext: modelContext)
        _protection = module
        return module
    }

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
            return _spaceLens?.phase == .scanning || _spaceLens?.phase == .cleaning
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
            return _protection?.phase == .scanning || _protection?.phase == .quarantining
        }
    }
}

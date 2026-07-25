import Foundation
import Observation
import CleanCore

/// Real OAuth client ID/redirect URI per provider — left as placeholders
/// until real apps are registered with Google Cloud Console, Dropbox App
/// Console, and Azure AD (this phase's own blocking prerequisite). Every
/// provider fails closed with `.notConfigured` rather than a doomed request.
struct CloudCleanupConfig {
    var googleDrive = CloudProviderConfig()
    var dropbox = CloudProviderConfig()
    var oneDrive = CloudProviderConfig()

    static let placeholder = CloudCleanupConfig()
}

struct CloudAPIProviderState {
    var isAuthenticated = false
    var isLoading = false
    var scanProgress: ScanProgress?
    var files: [CloudFileMetadata] = []
    var duplicateGroups: [CloudDuplicateGroup] = []
    var errorMessage: String?
}

struct ICloudScanState {
    var isLoading = false
    var items: [ScanItem] = []
    var duplicateGroups: [DuplicateGroup] = []
    var errorMessage: String?
}

@MainActor
@Observable
final class CloudCleanupViewModel {
    enum APIProviderKind: String, CaseIterable, Identifiable {
        case googleDrive = "Google Drive"
        case dropbox = "Dropbox"
        case oneDrive = "OneDrive"
        var id: String { rawValue }
    }

    private(set) var apiStates: [APIProviderKind: CloudAPIProviderState] = [
        .googleDrive: CloudAPIProviderState(),
        .dropbox: CloudAPIProviderState(),
        .oneDrive: CloudAPIProviderState()
    ]
    private(set) var iCloudState = ICloudScanState()

    private let webPresenter: ASWebAuthSessionPresenter
    // Not UI-observed state, and @Observable's macro transformation doesn't
    // support `lazy` on a stored property — initialized directly in init()
    // instead, which is just as fine since webPresenter/config are already
    // available by then.
    @ObservationIgnored private let providers: [APIProviderKind: any CloudProvider]
    private let iCloudScanner = ICloudLocalScanner()

    init(config: CloudCleanupConfig = .placeholder) {
        let webPresenter = ASWebAuthSessionPresenter()
        self.webPresenter = webPresenter
        self.providers = [
            .googleDrive: GoogleDriveProvider(config: config.googleDrive, webSession: webPresenter),
            .dropbox: DropboxProvider(config: config.dropbox, webSession: webPresenter),
            .oneDrive: OneDriveProvider(config: config.oneDrive, webSession: webPresenter)
        ]
    }

    func connect(_ kind: APIProviderKind) async {
        apiStates[kind]?.isLoading = true
        apiStates[kind]?.errorMessage = nil
        do {
            try await providers[kind]!.authenticate()
            apiStates[kind]?.isAuthenticated = true
        } catch {
            apiStates[kind]?.errorMessage = Self.describe(error)
        }
        apiStates[kind]?.isLoading = false
    }

    func disconnect(_ kind: APIProviderKind) async {
        try? await providers[kind]!.signOut()
        apiStates[kind] = CloudAPIProviderState()
    }

    func loadFiles(_ kind: APIProviderKind) async {
        apiStates[kind]?.isLoading = true
        apiStates[kind]?.errorMessage = nil
        apiStates[kind]?.scanProgress = nil

        do {
            var allFiles: [CloudFileMetadata] = []
            var cursor: String?
            var pageCount = 0
            // CloudHTTPClient's backoff only guards against 429/5xx — it does
            // nothing to bound a loop of successful (200) pages. A provider
            // bug (or an untested provider — Dropbox/OneDrive have no
            // dedicated pagination tests this phase) returning a cursor that
            // never advances would otherwise become exactly the naive
            // tight-loop the Phase 6 spec says to avoid, just gated on
            // cursor equality instead of a boolean.
            let maxPages = 500
            repeat {
                let page = try await providers[kind]!.listFiles(cursor: cursor)
                allFiles.append(contentsOf: page.files)
                cursor = page.nextCursor
                pageCount += 1
                apiStates[kind]?.scanProgress = ScanProgress(itemsProcessed: allFiles.count)
            } while cursor != nil && pageCount < maxPages

            if cursor != nil {
                apiStates[kind]?.errorMessage = "Stopped after \(maxPages) pages — this provider may have far more files than expected."
            }
            apiStates[kind]?.files = allFiles
            apiStates[kind]?.duplicateGroups = CloudDuplicateGrouper.findDuplicates(among: allFiles)
        } catch {
            apiStates[kind]?.errorMessage = Self.describe(error)
        }
        apiStates[kind]?.isLoading = false
    }

    func delete(_ fileIDs: [String], from kind: APIProviderKind) async {
        do {
            let result = try await providers[kind]!.delete(fileIDs: fileIDs)
            let succeeded = Set(result.succeededIDs)
            apiStates[kind]?.files.removeAll { succeeded.contains($0.id) }
            apiStates[kind]?.duplicateGroups = CloudDuplicateGrouper.findDuplicates(among: apiStates[kind]?.files ?? [])
        } catch {
            apiStates[kind]?.errorMessage = Self.describe(error)
        }
    }

    /// iCloud Drive has no public API — this reads the locally-synced tree
    /// and reuses Phase 3's real local SHA-256-based `DuplicateFinder`
    /// directly (unlike the API providers, there's no bandwidth cost to
    /// avoid here — the files are already on local disk).
    func loadICloudFiles() async {
        iCloudState.isLoading = true
        iCloudState.errorMessage = nil
        do {
            iCloudState.items = try await iCloudScanner.scan()
            iCloudState.duplicateGroups = try await DuplicateFinder(rootPath: ICloudLocalScanner.mobileDocumentsRoot)
                .findExactDuplicateGroups()
                .groups
        } catch {
            iCloudState.errorMessage = Self.describe(error)
        }
        iCloudState.isLoading = false
    }

    func cleanICloudFiles(_ items: [ScanItem]) async {
        do {
            let result = try await DefaultCleaner().clean(items)
            let succeededPaths = Set(result.succeeded.map(\.path))
            iCloudState.items.removeAll { succeededPaths.contains($0.path) }
        } catch {
            iCloudState.errorMessage = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        if let cloudError = error as? CloudProviderError {
            switch cloudError {
            case .notConfigured:
                return "This provider isn't configured yet — needs a registered OAuth app's client ID and redirect URI."
            case .notAuthenticated:
                return "Not connected."
            case .rateLimited:
                return "Rate limited — try again shortly."
            case .requestFailed(let statusCode):
                return "Request failed (HTTP \(statusCode))."
            }
        }
        return error.localizedDescription
    }
}

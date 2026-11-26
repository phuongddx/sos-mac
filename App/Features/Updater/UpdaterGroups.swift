import Foundation
import CleanCore

/// What one app row says after (or before) a check — the single place that decides
/// whether a row may read "Up to date" (plan PR 10, spec D3 / OD-10).
///
/// **Fail closed:** `upToDate` needs a real feed result (`latestVersion` from the feed).
/// A feed that threw, or answered without a version, is `checkFailed` — never success.
/// A row that has not been checked yet is `notChecked`, never "Up to date".
enum UpdaterRowStatus: Equatable, Sendable {
    case updateAvailable(installed: String, latest: String)
    /// Mac App Store app: no official way to update it from here, so the row offers a
    /// link that opens the App Store.
    case appStore
    case upToDate
    /// No Sparkle feed (or no installed version to compare): the app cannot be checked.
    case noFeed
    /// OD-10: the feed was reached for and failed; `message` is the engine's reason.
    case checkFailed(message: String)
    /// Has a feed but no result yet (before a check, or after Stop).
    case notChecked
}

/// A group of rows on the results screen, in spec §5.8 order.
struct UpdaterGroup: Identifiable, Equatable {
    enum Kind: CaseIterable, Sendable {
        case updates, appStore, upToDate, noFeed
        /// OD-10 (i): feeds that failed. Shown only when there is at least one.
        case couldntCheck
        /// Rows a Stop (or a retry that was stopped) left without a result. Shown only
        /// when there is at least one.
        case notChecked

        var title: String {
            switch self {
            case .updates: "Updates available"
            case .appStore: "Update in the App Store"
            case .upToDate: "Up to date"
            case .noFeed: "No update feed"
            case .couldntCheck: "Couldn't check"
            case .notChecked: "Not checked yet"
            }
        }

        /// The one-line note under the group title.
        var note: String? {
            switch self {
            case .updates: nil
            case .appStore: "Opens the App Store so you can update there."
            case .upToDate: nil
            case .noFeed: "These apps have no update feed SOS Mac can read."
            case .couldntCheck: "Their update feed didn't answer. They are not shown as up to date."
            case .notChecked: "The check was stopped before reaching these apps."
            }
        }
    }

    let kind: Kind
    let rows: [UpdaterViewModel.AppUpdateRow]
    var id: Kind { kind }
}

enum UpdaterGroups {
    /// Whether `latest` is newer than `installed`, compared numerically ("1.10" > "1.9").
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        latest.compare(installed, options: .numeric) == .orderedDescending
    }

    /// The row's status. Order matters: a known newer version wins, then the App Store
    /// link, then "cannot be checked", then the check outcome.
    static func status(of row: UpdaterViewModel.AppUpdateRow) -> UpdaterRowStatus {
        if let latest = row.latestVersion, let installed = row.app.version, isNewer(latest, than: installed) {
            return .updateAvailable(installed: installed, latest: latest)
        }
        if row.app.isAppStoreDistributed { return .appStore }
        if row.app.sparkleFeedURL == nil || row.app.version == nil { return .noFeed }
        if let message = row.checkError { return .checkFailed(message: message) }
        if row.latestVersion != nil { return .upToDate }
        return .notChecked
    }

    /// Rows in spec order; empty groups are dropped. Rows keep the caller's (name) order.
    static func groups(for rows: [UpdaterViewModel.AppUpdateRow]) -> [UpdaterGroup] {
        var buckets: [UpdaterGroup.Kind: [UpdaterViewModel.AppUpdateRow]] = [:]
        for row in rows {
            let kind: UpdaterGroup.Kind
            switch status(of: row) {
            case .updateAvailable: kind = .updates
            case .appStore: kind = .appStore
            case .upToDate: kind = .upToDate
            case .noFeed: kind = .noFeed
            case .checkFailed: kind = .couldntCheck
            case .notChecked: kind = .notChecked
            }
            buckets[kind, default: []].append(row)
        }
        return UpdaterGroup.Kind.allCases.compactMap { kind in
            guard let rows = buckets[kind], !rows.isEmpty else { return nil }
            return UpdaterGroup(kind: kind, rows: rows)
        }
    }

    /// Plural-aware count text: "1 update available" / "3 updates available".
    static func updatesText(_ count: Int) -> String {
        count == 1 ? "1 update available" : "\(count) updates available"
    }
}

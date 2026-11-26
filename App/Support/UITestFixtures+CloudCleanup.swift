#if DEBUG
import Foundation
import CleanCore

/// Fictional Cloud Cleanup sample data (PR 11). Nothing is read from the
/// machine: iCloud Drive sets live under a fictional Mobile Documents path,
/// and the API-provider files are `CloudFileMetadata` values with made-up
/// ids and content hashes. The recommended keep is the newest copy by
/// modified date in every set (the engine's own rule).
extension UITestFixtures {
    /// The extension's own ISO-8601 helper (`UITestFixtures.date(_:)` is
    /// private to the base file).
    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    /// The fictional iCloud Drive container root (synthetic — the real
    /// `ICloudLocalScanner.mobileDocumentsRoot` is never touched).
    static let iCloudHome = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"

    /// The fixture listing's file count ("N files listed") — larger than the
    /// duplicate candidates, as a real listing is.
    static let iCloudListedFileCount = 148

    /// iCloud Drive duplicate sets, ordered newest first (`items[0]` is the
    /// recommended keep — `DuplicateGroup.recommendedKeepPath` picks it).
    static let iCloudDuplicateSets: [DuplicateSetFixture] = [
        DuplicateSetFixture(id: "ic1", title: "team-offsite-photos.zip", isSimilar: false, items: [
            ScanItem(path: "\(iCloudHome)/Photos/team-offsite-photos.zip", size: 2_180_540_000, kind: .file,
                     lastModified: date("2026-11-14T09:12:00Z"), sourceLabel: "iCloud Drive"),
            ScanItem(path: "\(iCloudHome)/Documents/Archive/team-offsite-photos.zip", size: 2_180_540_000, kind: .file,
                     lastModified: date("2026-11-12T18:40:00Z"), sourceLabel: "iCloud Drive"),
            ScanItem(path: "\(iCloudHome)/Desktop/team-offsite-photos.zip", size: 2_180_540_000, kind: .file,
                     lastModified: date("2026-10-28T11:05:00Z"), sourceLabel: "iCloud Drive"),
        ]),
        DuplicateSetFixture(id: "ic2", title: "brand-guidelines-v2.pdf", isSimilar: false, items: [
            ScanItem(path: "\(iCloudHome)/Documents/Brand/brand-guidelines-v2.pdf", size: 61_240_000, kind: .file,
                     lastModified: date("2026-11-18T14:02:00Z"), sourceLabel: "iCloud Drive"),
            ScanItem(path: "\(iCloudHome)/Downloads/brand-guidelines-v2.pdf", size: 61_240_000, kind: .file,
                     lastModified: date("2026-11-09T08:27:00Z"), sourceLabel: "iCloud Drive"),
        ]),
        DuplicateSetFixture(id: "ic3", title: "invoice-ab-231.pdf", isSimilar: false, items: [
            ScanItem(path: "\(iCloudHome)/Documents/Invoices/invoice-ab-231.pdf", size: 486_200_000, kind: .file,
                     lastModified: date("2026-11-03T16:45:00Z"), sourceLabel: "iCloud Drive"),
            ScanItem(path: "\(iCloudHome)/Public/invoice-ab-231.pdf", size: 486_200_000, kind: .file,
                     lastModified: date("2026-10-21T10:19:00Z"), sourceLabel: "iCloud Drive"),
        ]),
    ]

    /// Google Drive's fixture files as the API reports them: content hashes
    /// (Drive's `md5Checksum`) form three duplicate groups; the rest are
    /// singletons the grouper drops. Ids and hashes are synthetic.
    static let driveFiles: [CloudFileMetadata] = [
        CloudFileMetadata(id: "drv-001", name: "Q4-brand-assets.zip", size: 812_300_000,
                          contentHash: "fixture-hash-brand", modifiedDate: date("2026-11-21T10:30:00Z")),
        CloudFileMetadata(id: "drv-002", name: "Q4-brand-assets (1).zip", size: 812_300_000,
                          contentHash: "fixture-hash-brand", modifiedDate: date("2026-11-18T09:15:00Z")),
        CloudFileMetadata(id: "drv-003", name: "Q4-brand-assets-old.zip", size: 812_300_000,
                          contentHash: "fixture-hash-brand", modifiedDate: date("2026-11-02T22:41:00Z")),
        CloudFileMetadata(id: "drv-004", name: "team-offsite-photos.zip", size: 1_062_450_000,
                          contentHash: "fixture-hash-offsite", modifiedDate: date("2026-11-14T17:03:00Z")),
        CloudFileMetadata(id: "drv-005", name: "team-offsite-photos-backup.zip", size: 1_062_450_000,
                          contentHash: "fixture-hash-offsite", modifiedDate: date("2026-11-12T07:52:00Z")),
        CloudFileMetadata(id: "drv-006", name: "contract-ab-2026.pdf", size: 246_800_000,
                          contentHash: "fixture-hash-contract", modifiedDate: date("2026-10-30T13:08:00Z")),
        CloudFileMetadata(id: "drv-007", name: "contract-ab-2026-copy.pdf", size: 246_800_000,
                          contentHash: "fixture-hash-contract", modifiedDate: date("2026-10-21T19:26:00Z")),
        CloudFileMetadata(id: "drv-008", name: "budget-2027.xlsx", size: 84_120_000,
                          contentHash: "fixture-hash-budget", modifiedDate: date("2026-11-19T08:00:00Z")),
        CloudFileMetadata(id: "drv-009", name: "logo-final.svg", size: 1_240_000,
                          contentHash: "fixture-hash-logo", modifiedDate: date("2026-11-06T12:34:00Z")),
        CloudFileMetadata(id: "drv-010", name: "readme.txt", size: 4_100,
                          contentHash: "fixture-hash-readme", modifiedDate: date("2026-09-01T00:00:00Z")),
    ]
}
#endif

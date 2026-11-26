#if DEBUG
import Foundation
import CleanCore

/// Made-up sample data for debug fixtures, modelled on the prototype's `data.js`
/// (`docs/redesign/prototype/data.js`). Every name, path and size is fictional: the
/// paths live under `/Users/sample` and nothing here is read from the machine
/// the app runs on. Screens use it only when `UITestHooks.current.fixtures` is on.
enum UITestFixtures {
    static let home = "/Users/sample"

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: Junk & Cache — 4 rules, files only

    struct JunkRuleFixture: Sendable, Identifiable {
        let id: String
        let label: String
        let root: String
        let requiresHelper: Bool
        let items: [ScanItem]
    }

    private static func junk(
        _ root: String, _ rule: String, helper: Bool, _ files: [(String, String, Int64, Severity)]
    ) -> [ScanItem] {
        files.map { name, dir, size, severity in
            ScanItem(
                path: "\(root)/\(dir)/\(name)", size: size, kind: .file,
                lastAccessed: date("2026-11-20T09:00:00Z"), lastModified: date("2026-11-18T09:00:00Z"),
                severity: severity, sourceLabel: rule, requiresPrivilegedHelper: helper
            )
        }
    }

    static let junkRules: [JunkRuleFixture] = [
        JunkRuleFixture(
            id: "uc", label: "User App Caches", root: "\(home)/Library/Caches", requiresHelper: false,
            items: junk("\(home)/Library/Caches", "User App Caches", helper: false, [
                ("Cache.db", "com.example.musicplayer/Data", 612_480_000, .safe),
                ("data_3", "Example/Browser/Default/Cache/Cache_Data", 341_220_000, .safe),
                ("CachedExtensionVSIXs.zip", "com.example.codeeditor.ShipIt", 218_600_000, .safe),
                ("fsCachedData.db", "com.example.chatapp", 188_940_000, .safe),
                ("Cache.db", "com.example.webview", 96_310_000, .safe),
                ("index-v3.dat", "com.example.designtool", 74_820_000, .safe),
                ("data_1", "com.example.meetings/Cache", 41_270_000, .safe),
                ("Cache.db-wal", "com.example.mediaplayer", 18_450_000, .safe),
                ("icons.cache", "com.example.launcher", 9_620_000, .safe),
            ])),
        JunkRuleFixture(
            id: "ul", label: "User Logs (7+ days old)", root: "\(home)/Library/Logs", requiresHelper: false,
            items: junk("\(home)/Library/Logs", "User Logs (7+ days old)", helper: false, [
                ("IDE-2026-10-29.log", "ExampleIDE", 61_540_000, .safe),
                ("meetings_stdout_stderr.log", "meetings", 12_330_000, .safe),
                ("container-desktop.log", "Example Containers", 8_920_000, .caution),
                ("diagnostic-2026-11-02.ips", "DiagnosticReports", 4_810_000, .safe),
                ("chat-main.log", "ExampleChat", 2_240_000, .caution),
            ])),
        JunkRuleFixture(
            id: "as", label: "App Support Cache Folders", root: "\(home)/Library/Application Support",
            requiresHelper: false,
            items: junk("\(home)/Library/Application Support", "App Support Cache Folders", helper: false, [
                ("data_2", "ExampleChat/Cache/Cache_Data", 402_180_000, .safe),
                ("CachedData.bin", "ExampleEditor/CachedData", 266_410_000, .safe),
                ("index", "ExampleNotes/Cache", 184_520_000, .safe),
                ("f_000a91", "ExampleDesign/DesktopProfile/Cache", 93_610_000, .safe),
                ("js-cache.bin", "ExamplePlayer/PersistentCache", 57_230_000, .safe),
            ])),
        JunkRuleFixture(
            id: "sc", label: "System Caches (requires additional permission)", root: "/Library/Caches",
            requiresHelper: true,
            items: junk("/Library/Caches", "System Caches (requires additional permission)", helper: true, [
                ("store.index", "com.example.system.iconstore", 182_400_000, .caution),
                ("Cache.db", "com.example.system.cloudsync", 96_200_000, .caution),
                ("update-cache.db", "com.example.updater.helper", 41_700_000, .caution),
                ("data.bin", "com.example.system.engagement", 11_300_000, .caution),
            ])),
    ]

    // MARK: Duplicates — first copy is the newest by modified date and is the recommended keep

    struct DuplicateSetFixture: Sendable, Identifiable {
        let id: String
        let title: String
        let isSimilar: Bool
        /// Ordered newest first; `items[0]` is the recommended keep.
        let items: [ScanItem]
    }

    private static func copies(_ name: String, size: Int64, _ places: [(String, String)]) -> [ScanItem] {
        places.map { dir, iso in
            ScanItem(path: "\(home)/\(dir)/\(name)", size: size, kind: .file,
                     lastModified: date(iso), sourceLabel: "Duplicate")
        }
    }

    static let duplicateSets: [DuplicateSetFixture] = [
        DuplicateSetFixture(id: "d1", title: "onboarding-walkthrough.mov", isSimilar: false,
            items: copies("onboarding-walkthrough.mov", size: 1_240_310_000,
                          [("Movies/Exports", "2026-11-21T16:02:00Z"), ("Downloads", "2026-11-14T09:41:00Z")])),
        DuplicateSetFixture(id: "d2", title: "design-assets-v4.zip", isSimilar: false,
            items: copies("design-assets-v4.zip", size: 612_300_000,
                          [("Documents/Projects/Brand", "2026-11-18T14:20:00Z"), ("Downloads", "2026-11-18T14:05:00Z"),
                           ("Desktop/Old", "2026-11-02T10:12:00Z")])),
        DuplicateSetFixture(id: "d3", title: "Sample-Installer.dmg", isSimilar: false,
            items: copies("Sample-Installer.dmg", size: 214_600_000,
                          [("Downloads", "2026-11-10T11:30:00Z"), ("Downloads/Installers", "2026-09-30T17:44:00Z")])),
        DuplicateSetFixture(id: "d4", title: "runtime-v24.11.0.pkg", isSimilar: false,
            items: copies("runtime-v24.11.0.pkg", size: 78_900_000,
                          [("Downloads", "2026-11-04T08:03:00Z"), ("Desktop", "2026-10-29T19:20:00Z")])),
        DuplicateSetFixture(id: "d5", title: "Q3-report.pdf", isSimilar: false,
            items: copies("Q3-report.pdf", size: 48_200_000,
                          [("Documents/Reports", "2026-10-20T15:55:00Z"), ("Downloads", "2026-10-12T12:10:00Z"),
                           ("Desktop", "2026-10-12T12:09:00Z")])),
        DuplicateSetFixture(id: "d6", title: "IMG_0001.HEIC", isSimilar: false,
            items: copies("IMG_0001.HEIC", size: 3_400_000,
                          [("Pictures/2026-10", "2026-10-03T18:31:00Z"), ("Desktop", "2026-10-03T18:30:00Z")])),
    ]

    static let similarSets: [DuplicateSetFixture] = [
        DuplicateSetFixture(id: "s1", title: "IMG_0104.HEIC", isSimilar: true, items: [
            ScanItem(path: "\(home)/Pictures/2026-11/IMG_0104.HEIC", size: 3_810_000, kind: .file,
                     lastModified: date("2026-11-09T17:22:30Z"), sourceLabel: "Similar image"),
            ScanItem(path: "\(home)/Pictures/2026-11/IMG_0103.HEIC", size: 3_790_000, kind: .file,
                     lastModified: date("2026-11-09T17:22:00Z"), sourceLabel: "Similar image"),
            ScanItem(path: "\(home)/Pictures/2026-11/IMG_0102.HEIC", size: 3_820_000, kind: .file,
                     lastModified: date("2026-11-09T17:21:00Z"), sourceLabel: "Similar image"),
        ]),
        DuplicateSetFixture(id: "s2", title: "Screenshot 2026-11-12 at 10.14.08.png", isSimilar: true, items: [
            ScanItem(path: "\(home)/Desktop/Screenshot 2026-11-12 at 10.14.08.png", size: 1_240_000, kind: .file,
                     lastModified: date("2026-11-12T10:14:08Z"), sourceLabel: "Similar image"),
            ScanItem(path: "\(home)/Desktop/Screenshot 2026-11-12 at 10.13.51.png", size: 1_230_000, kind: .file,
                     lastModified: date("2026-11-12T10:13:51Z"), sourceLabel: "Similar image"),
        ]),
    ]

    // MARK: Uninstaller — 10 apps

    struct AppFixture: Sendable, Identifiable {
        let id: String
        let name: String
        let version: String
        let bundleID: String
        let isAppStore: Bool
        let appBytes: Int64
        let supportBytes: Int64
        let cacheBytes: Int64
    }

    static let apps: [AppFixture] = [
        AppFixture(id: "ide", name: "Example IDE", version: "16.4", bundleID: "com.example.ide", isAppStore: true,
                   appBytes: 11_820_000_000, supportBytes: 2_140_000_000, cacheBytes: 864_000_000),
        AppFixture(id: "containers", name: "Example Containers", version: "4.50.0", bundleID: "com.example.containers", isAppStore: false,
                   appBytes: 2_310_000_000, supportBytes: 1_420_000_000, cacheBytes: 96_000_000),
        AppFixture(id: "slides", name: "Example Slides", version: "14.4", bundleID: "com.example.slides", isAppStore: true,
                   appBytes: 735_200_000, supportBytes: 41_000_000, cacheBytes: 12_000_000),
        AppFixture(id: "editor", name: "Example Editor", version: "1.106.2", bundleID: "com.example.editor", isAppStore: false,
                   appBytes: 627_400_000, supportBytes: 266_400_000, cacheBytes: 218_600_000),
        AppFixture(id: "design", name: "Example Design", version: "125.10.4", bundleID: "com.example.design", isAppStore: false,
                   appBytes: 512_400_000, supportBytes: 93_600_000, cacheBytes: 74_800_000),
        AppFixture(id: "chat", name: "Example Chat", version: "4.46.101", bundleID: "com.example.chat", isAppStore: false,
                   appBytes: 498_200_000, supportBytes: 402_200_000, cacheBytes: 188_900_000),
        AppFixture(id: "notes", name: "Example Notes", version: "4.22.1", bundleID: "com.example.notes", isAppStore: false,
                   appBytes: 431_000_000, supportBytes: 184_500_000, cacheBytes: 22_100_000),
        AppFixture(id: "music", name: "Example Music", version: "1.2.74", bundleID: "com.example.music", isAppStore: false,
                   appBytes: 352_900_000, supportBytes: 57_200_000, cacheBytes: 612_500_000),
        AppFixture(id: "meet", name: "Example Meet", version: "6.6.2", bundleID: "com.example.meet", isAppStore: false,
                   appBytes: 287_500_000, supportBytes: 31_000_000, cacheBytes: 41_300_000),
        AppFixture(id: "launcher", name: "Example Launcher", version: "1.104.0", bundleID: "com.example.launcher", isAppStore: false,
                   appBytes: 214_800_000, supportBytes: 88_000_000, cacheBytes: 9_600_000),
    ]

    // MARK: Updater — 8 rows across the four groups

    enum UpdaterRowKind: String, Sendable { case updateAvailable, appStore, upToDate, noFeed }

    struct UpdaterRowFixture: Sendable, Identifiable {
        var id: String { appID }
        let appID: String
        let kind: UpdaterRowKind
        let installedVersion: String
        let latestVersion: String?
    }

    static let updaterRows: [UpdaterRowFixture] = [
        UpdaterRowFixture(appID: "chat", kind: .updateAvailable, installedVersion: "4.45.64", latestVersion: "4.46.101"),
        UpdaterRowFixture(appID: "meet", kind: .updateAvailable, installedVersion: "6.5.11", latestVersion: "6.6.2"),
        UpdaterRowFixture(appID: "launcher", kind: .updateAvailable, installedVersion: "1.103.2", latestVersion: "1.104.0"),
        UpdaterRowFixture(appID: "ide", kind: .appStore, installedVersion: "16.4", latestVersion: nil),
        UpdaterRowFixture(appID: "slides", kind: .appStore, installedVersion: "14.4", latestVersion: nil),
        UpdaterRowFixture(appID: "design", kind: .upToDate, installedVersion: "125.10.4", latestVersion: "125.10.4"),
        UpdaterRowFixture(appID: "notes", kind: .upToDate, installedVersion: "4.22.1", latestVersion: "4.22.1"),
        UpdaterRowFixture(appID: "containers", kind: .noFeed, installedVersion: "4.50.0", latestVersion: nil),
    ]

    // MARK: Space Lens — a small tree

    struct LensNode: Sendable, Identifiable {
        var id: String { path }
        let name: String
        let path: String
        let bytes: Int64
        let isDirectory: Bool
        let children: [LensNode]
    }

    private static func dir(_ name: String, _ parent: String, _ bytes: Int64, _ children: [LensNode] = []) -> LensNode {
        LensNode(name: name, path: "\(parent)/\(name)", bytes: bytes, isDirectory: true, children: children)
    }

    private static func file(_ name: String, _ parent: String, _ bytes: Int64) -> LensNode {
        LensNode(name: name, path: "\(parent)/\(name)", bytes: bytes, isDirectory: false, children: [])
    }

    static let spaceLensRoot: LensNode = {
        let downloads = "\(home)/Downloads"
        return LensNode(name: "sample", path: home, bytes: 0, isDirectory: true, children: [
            dir("Library", home, 182_410_000_000),
            dir("Documents", home, 64_200_000_000),
            dir("Movies", home, 58_940_000_000),
            dir("Pictures", home, 41_730_000_000),
            dir("Developer", home, 37_520_000_000),
            dir("Downloads", home, 22_810_000_000, [
                file("raw-footage-2026-09.zip", downloads, 6_420_000_000),
                dir("Old Installers", downloads, 4_180_000_000),
                file("Large-Image.xip", downloads, 3_210_000_000),
                file("conference-talk.mov", downloads, 2_860_000_000),
                dir("Archive 2025", downloads, 2_260_000_000),
                file("dataset-export.csv.gz", downloads, 1_940_000_000),
                dir("Screenshots", downloads, 1_120_000_000),
            ]),
            dir("Music", home, 12_340_000_000),
            dir("Desktop", home, 8_620_000_000),
            dir("Applications", home, 3_100_000_000),
        ])
    }()

    // MARK: Protection — findings and quarantine

    struct FindingFixture: Sendable, Identifiable {
        let id: String
        let path: String
        let size: Int64
        let method: String
        let identifier: String
    }

    struct QuarantineFixture: Sendable, Identifiable {
        let id: String
        let name: String
        let originalPath: String
        let quarantinedAt: Date
    }

    static let findings: [FindingFixture] = [
        FindingFixture(id: "f1", path: "\(home)/Downloads/eicar_test.com", size: 68,
                       method: "Known signature", identifier: "EICAR-Test-File"),
    ]

    static let quarantine: [QuarantineFixture] = [
        QuarantineFixture(id: "q1", name: "eicar.com.txt", originalPath: "\(home)/Downloads/old/eicar.com.txt",
                          quarantinedAt: date("2026-11-24T16:08:00Z")),
        QuarantineFixture(id: "q2", name: "eicar_com.zip", originalPath: "\(home)/Downloads/eicar_com.zip",
                          quarantinedAt: date("2026-11-24T16:08:00Z")),
    ]

    // MARK: System metrics

    struct SystemMetricsFixture: Sendable {
        let volumeName: String
        let usedBytes: Int64
        let totalBytes: Int64
        let cpuPercent: Int
        let wired: Int64
        let active: Int64
        let compressed: Int64
        let inactive: Int64
        let free: Int64
        let swapUsed: Int64
        let swapTotal: Int64
        let thermal: String
        let loadAverage: [Double]
        let loginAgents: [String]
    }

    static let metrics = SystemMetricsFixture(
        volumeName: "Sample Disk", usedBytes: 460_110_000_000, totalBytes: 494_380_000_000, cpuPercent: 23,
        wired: 2_840_000_000, active: 5_610_000_000, compressed: 2_790_000_000, inactive: 3_920_000_000,
        free: 840_000_000, swapUsed: 1_250_000_000, swapTotal: 2_150_000_000, thermal: "Nominal",
        loadAverage: [2.41, 2.88, 3.02],
        loginAgents: ["com.example.launcher.helper.plist", "com.example.containers.helper.plist", "com.example.meet.updater.plist"]
    )
}
#endif

#if DEBUG
import Foundation
import CleanCore

/// Fictional Protection sample data (PR 13). Modelled on the prototype's `data.js`; nothing
/// is read from the machine, and the locations are plain paths under `/Users/sample` (never
/// the Firefox glob, which would look at the real profile folder). The one finding is the
/// industry-standard EICAR test file: harmless by design, and its SHA-256 is public.
extension UITestFixtures {
    /// "19,388 files checked" — what the prototype's scan reports; used for the scanning
    /// total and for the results / empty copy.
    static let protectionFileCount = 19_388

    /// The six allowlist locations, same ids and labels as `ProtectionLocation.allowlist`,
    /// re-rooted under the fictional home so resolving them touches nothing real.
    static var protectionLocations: [ProtectionLocation] {
        [
            ProtectionLocation(id: "downloads", label: "Downloads", kind: .directPath("\(home)/Downloads")),
            ProtectionLocation(id: "user-login-items", label: "User Login Items", kind: .directPath("\(home)/Library/LaunchAgents")),
            ProtectionLocation(id: "system-login-items", label: "System Login Items", kind: .directPath("/Library/LaunchAgents")),
            ProtectionLocation(id: "system-daemons", label: "System Daemons", kind: .directPath("/Library/LaunchDaemons")),
            ProtectionLocation(id: "chrome-extensions", label: "Chrome Extensions",
                               kind: .directPath("\(home)/Library/Application Support/Google/Chrome/Default/Extensions")),
            ProtectionLocation(id: "firefox-extensions", label: "Firefox Extensions",
                               kind: .directPath("\(home)/Library/Application Support/Firefox/Profiles/sample.default/extensions")),
        ]
    }

    private static func protectionDate(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    /// EICAR's public SHA-256 — what the bundled baseline database matches on.
    static let eicarSHA256 = "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"

    static var protectionFindings: [ThreatFinding] {
        [ThreatFinding(path: "\(home)/Downloads/eicar_test.com",
                       size: 68,
                       detectionMethod: .hash,
                       identifier: eicarSHA256,
                       detectedAt: protectionDate("2026-11-26T10:42:00Z"))]
    }

    /// Transient (never inserted) quarantine records, newest first. `count` of the prototype's
    /// list; `includingJustQuarantined` puts the file the `done` state just moved on top.
    static func protectionQuarantineRecords(count: Int, includingJustQuarantined: Bool = false) -> [QuarantineRecord] {
        let rows: [(String, String, String)] = [
            ("eicar.com.txt", "\(home)/Downloads/old", "2026-11-24T16:08:00Z"),
            ("eicar_com.zip", "\(home)/Downloads", "2026-11-24T16:08:00Z"),
            ("invoice_0923.pdf.app", "\(home)/Downloads", "2026-11-20T09:14:00Z"),
            ("Flash_Update.pkg", "\(home)/Downloads", "2026-11-12T18:30:00Z"),
            ("com.search.helper.plist", "\(home)/Library/LaunchAgents", "2026-11-09T11:02:00Z"),
            ("player_setup.dmg", "\(home)/Downloads/old", "2026-10-31T15:47:00Z"),
            ("ext_8f2c.crx", "\(home)/Library/Application Support/Google/Chrome", "2026-10-18T20:11:00Z"),
            ("codec-pack.zip", "\(home)/Downloads", "2026-10-02T13:05:00Z"),
            ("update_helper", "/Library/LaunchDaemons", "2026-09-21T08:40:00Z"),
        ]
        var records = rows.prefix(count).map { name, folder, iso in
            QuarantineRecord(originalPath: "\(folder)/\(name)",
                             quarantinePath: "\(home)/Library/Application Support/SOS Mac/Quarantine/\(name)",
                             threatIdentifier: eicarSHA256,
                             quarantinedAt: protectionDate(iso))
        }
        if includingJustQuarantined {
            records.insert(QuarantineRecord(originalPath: "\(home)/Downloads/eicar_test.com",
                                            quarantinePath: "\(home)/Library/Application Support/SOS Mac/Quarantine/eicar_test.com",
                                            threatIdentifier: eicarSHA256,
                                            quarantinedAt: protectionDate("2026-11-26T10:43:00Z")),
                           at: 0)
        }
        return records
    }
}
#endif

import Foundation
import Testing

/// MAS signature-update policy, enforced.
///
/// The Mac App Store build ships **without YARA rules** and never downloads
/// rules or signatures over the network: signature/rule updates arrive with
/// an app update, and Protection's built-in hash baseline is the only
/// detection list. `SignatureUpdateChecker` (the networked update path in
/// CleanCore) is therefore not wired anywhere in the MAS app — this test
/// keeps it that way: any app source that references the type fails this
/// suite in the MAS build, so future wiring must be `#if !MAS_BUILD`.
///
/// The Developer ID / DMG build is unaffected by this policy.
@Suite("MAS signature-update policy")
struct SignatureUpdatePolicyTests {

    @Test("no App source references SignatureUpdateChecker (MAS ships without networked signature updates)")
    func appSourcesNeverReferenceSignatureUpdateChecker() throws {
        // Repo root from this test file: …/SOSMacMASTests/ → repo → App.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SOSMacMASTests/
            .deletingLastPathComponent()  // repo root
        let appDir = repoRoot.appendingPathComponent("App")

        let enumerator = FileManager.default.enumerator(
            at: appDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let swiftFiles = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        #expect(!swiftFiles.isEmpty, "App sources not found at \(appDir.path)")

        var offenders: [String] = []
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("SignatureUpdateChecker") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty,
                "MAS app sources must not reference SignatureUpdateChecker (networked signature updates are DMG-only): \(offenders)")
    }
}

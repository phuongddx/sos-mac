# Phase 1: Essential Trio (Junk/Cache Scanner, Uninstaller, Updater)

## Context
The "nền tảng" (foundation) module set per the research doc. Highest value-to-risk ratio — ship this first as the app's actual MVP feature, even though Phase 0 laid the groundwork.

## Requirements
### Junk/Cache Scanner
- Scan known junk locations: `~/Library/Caches`, `~/Library/Logs`, `~/Library/Application Support/*/Cache*`, `/Library/Caches` (needs privileged helper for root-owned entries — stub this call through Phase 8's helper, don't block Phase 1 on it being fully built; system-level caches can be marked "requires additional permission" in the UI until Phase 8 lands).
- Classify by `Severity`: user caches = safe, logs older than N days = safe, anything under an app's own document/support root that looks user-generated = caution (never auto-select).
- Never touch `~/Library/Application Support/<app>/` root wholesale — only well-known cache subfolders. This is the #1 way cleaner apps destroy user data; be conservative and explicit about which subpaths are eligible.

### Uninstaller
- Scan `/Applications` and `~/Applications` for `.app` bundles; for a selected app, find associated files by bundle identifier match across `~/Library/{Caches,Preferences,Application Support,Saved Application State,Containers}` and `~/Library/LaunchAgents` (+ equivalents needing helper for `/Library/LaunchDaemons`).
- Present the full associated-file list to the user before deletion — no silent "remove everything" without a review step.
- Use `trashItem` for the `.app` bundle and every associated file individually (so a partial failure doesn't leave orphaned Preferences invisible to the user).

### Updater
- Enumerate installed apps' version via `Bundle` / `CFBundleShortVersionString` from each `.app`'s Info.plist.
- Do **not** attempt auto-update of third-party apps — no official mechanism exists for arbitrary apps. Scope this down to: (a) surfacing outdated-looking apps by comparing against Sparkle appcast feeds when the app itself uses Sparkle (many do — detectable via `SUFeedURL` in Info.plist), (b) deep-linking to the App Store page for App-Store-distributed apps. This avoids reimplementing every vendor's update mechanism.

## Files to create
- `Packages/CleanCore/Sources/CleanCore/JunkScanner/JunkScanner.swift` (+ `JunkRule.swift` defining the allowlist of scannable subpaths)
- `Packages/CleanCore/Sources/CleanCore/Uninstaller/AppUninstaller.swift`
- `Packages/CleanCore/Sources/CleanCore/Uninstaller/BundleAssociatedFilesFinder.swift`
- `Packages/CleanCore/Sources/CleanCore/Updater/InstalledAppsEnumerator.swift`
- `Packages/CleanCore/Sources/CleanCore/Updater/SparkleAppcastChecker.swift`
- `App/Features/JunkCleaner/JunkCleanerView.swift` + `JunkCleanerViewModel.swift`
- `App/Features/Uninstaller/UninstallerView.swift` + `UninstallerViewModel.swift`
- `App/Features/Updater/UpdaterView.swift` + `UpdaterViewModel.swift`

## Implementation steps
1. Define `JunkRule` as a static allowlist (`[JunkRule]`) — each rule has a path pattern, a default `Severity`, and a human-readable label shown in the UI (so users see *why* something is flaggable, not just a raw path).
2. Implement `JunkScanner: Scanner` iterating rules, using `FTSWrapper` per rule root, tagging each `ScanItem` with its originating rule.
3. Implement `BundleAssociatedFilesFinder` keyed on bundle identifier (read from the `.app`'s `Info.plist`), globbing the standard Library subpaths.
4. Implement `AppUninstaller: Scanner, Cleaner` composing the bundle itself + associated files into one `ScanItem` batch, reusing the shared `Cleaner.clean` default.
5. Implement `InstalledAppsEnumerator` via `FileManager` shallow scan of `/Applications`, `~/Applications`, reading `CFBundleShortVersionString`/`CFBundleIdentifier`/`SUFeedURL` from each Info.plist.
6. Build the three SwiftUI views as thin observers of their ViewModels; ViewModels own `@Observable` state and call into CleanCore, never touching the filesystem directly (see acceptance criteria in plan.md).
7. Add a persistent "always ignore" list (SwiftData) so a user's explicit "don't flag this again" choice survives across scans.

## Tests / validation
- `JunkScannerTests`: temp-directory fixture mimicking `~/Library/Caches` structure; assert correct `Severity` tagging and that non-allowlisted paths are never returned.
- `BundleAssociatedFilesFinderTests`: fixture with a fake `.app` + matching Preferences/Caches files sharing a bundle ID; assert all are found and files with a *different* bundle ID are excluded (proves no false-positive cross-app deletion).
- Manual smoke test: run Junk Scanner and Uninstaller against a real (non-critical) test app installed in a scratch VM/user account, not the primary dev machine.

## Risks / rollback
- **Risk**: over-aggressive cache-path allowlist deletes something load-bearing (e.g. browser session cache holding unsaved state). Mitigation: default every rule to unchecked in the UI except a small, well-vetted "safe" subset; expand the safe set only after real-world testing.
- Rollback: junk rules live in one file (`JunkRule.swift`) — disabling a bad rule is a one-line change, not a redesign.

# SOS Mac — macOS System Cleaner

A commercial-grade, CleanMyMac-style system cleaner for macOS 14+, built with Swift 6 and SwiftUI. Engineered around a protocol-based `CleanCore` engine (zero UI dependencies) that powers seven feature modules and three auxiliary processes.

## Status

Phases 0–8 are complete with tested, production-ready code. Phase 9 is planned but not yet started.

| Phase | Module | Status | Notes |
|-------|--------|--------|-------|
| 0 | Foundation & CleanCore | ✅ Done | XcodeGen, protocols, models, test suite |
| 1 | Essential Trio (Junk/Updater/Uninstaller) | ✅ Done | Full implementations, trash-safe, UI complete |
| 2 | Space Lens (disk treemap) | ✅ Done | SquarifiedTreemap algorithm, interactive visualization |
| 3 | Duplicate Finder | ✅ Done | Exact + perceptual (dHash) deduplication, never auto-deletes |
| 4 | Performance module + menu bar helper | ✅ Done | Live metrics polling; Purge RAM/Flush DNS now wired to Phase 8's helper |
| 5 | Smart Care orchestration | ✅ Done | Concurrent scanner orchestration, partial-failure tolerance |
| 6 | Cloud Cleanup (Drive/Dropbox/OneDrive/iCloud) | ✅ Done | Real OAuth2, iCloud local scan, no auto-delete |
| 7 | Protection (malware scanner) | ✅ Done | Real hash + libyara pattern detection, quarantine/restore; real-time protection deferred (Endpoint Security entitlement) |
| 8 | Privileged Helper Tool | ✅ Done | Real XPC daemon (`SMAppService.daemon`), minimal fixed op-set, server-side validation; live registration/approval needs a real signed build |
| 9 | Distribution & monetization | 🔲 Planned | Developer ID notarization, Sparkle auto-update, licensing |

## What's Built

**UI Modules** (in `App/Features/`):
- **Smart Care** — Orchestrates Junk, Duplicates, and health snapshot in parallel
- **Junk Cleaner** — Cache/temp scanner with SwiftData-backed ignore list
- **Duplicates** — Exact and perceptual image deduplication (never auto-deletes)
- **Space Lens** — Interactive treemap visualizer of disk usage
- **Uninstaller** — Bundle uninstall with associated-files cleanup
- **Updater** — Read-only Sparkle appcast monitoring
- **Performance** — Live CPU/RAM/Disk/thermal metrics; Purge RAM/Flush DNS routed through the Phase 8 privileged helper
- **Cloud Cleanup** — OAuth2 (Google Drive/Dropbox/OneDrive) + iCloud local scan
- **Protection** — Hash + libyara pattern-based malware scan, quarantine/restore, optional VirusTotal hash lookup

**Engine** (`Packages/CleanCore/`):
- Protocol-based `Scanner` and `Cleaner` (empty marker with extension default)
- `FileSystem` module: FTSWrapper (async BSD fts() streaming scanner)
- `Duplicates` module: SizeGrouper → StreamingHasher → DuplicateFinder + PerceptualHasher
- `SpaceLens` module: ArenaTree (arena-allocated node pool) + DiskTreeScanner
- `Performance` module: SysctlReader, MachHostStats, IOKitSensors (no SMC guessing)
- `Cloud` module: Real OAuth2+REST (Drive v3, Dropbox v2, Graph delta), Keychain token store
- `SmartCare` module: TaskGroup-based concurrent scanner orchestration
- `Protection` module: HashScanner + libyara-backed YaraScanner (via the `CYara` C shim), QuarantineManager, Ed25519-verified SignatureUpdateChecker, VirusTotal hash lookup
- `PrivilegedHelper` module: server-side input validation (`HelperOperationValidator`) shared with the `PrivilegedHelper` daemon target; XPC protocol (`HelperXPCProtocol`) with a minimal fixed op-set (trash a system-cache path, purge memory, flush DNS, load/unload a daemon plist) — no generic command passthrough

**Auxiliary**:
- **MenuBarHelper** — Separate embedded `.app`, no IPC, reads system metrics independently
- **PrivilegedHelper** — Separate root-privileged XPC daemon (`SMAppService.daemon`), code-signature-validates every caller, re-validates every input server-side regardless of what the app already checked
- Tests: 22 test files with per-test-token URL stubbing, @Suite(.serialized) for Keychain access, injectable root: override for sandbox-free testing

## What's Not Built

- **Real-time malware protection** (Endpoint Security framework requires Apple entitlement approval) — Protection's static/signature scan is the committed Phase 7 deliverable, per the plan's own scope decision
- **Phase 9**: Developer ID code signing, notarization, Sparkle setup, licensing integration
- **Known gaps**: No `.entitlements` file yet (needed for Phase 9); MenuBarHelper not auto-launching; no production signature-feed server or VirusTotal API key configured (Protection fails closed until real credentials are supplied); the privileged helper's code-signature check is identifier-only (no Team ID anchor yet — needs a real Developer Team, Phase 9); live `SMAppService.daemon` registration/System-Settings-approval has not been exercised end-to-end (needs a real signed build, not achievable with ad-hoc signing)

## How to Build

### Prerequisites
- macOS 14+ with Xcode 15.3+
- Swift 6.0+
- XcodeGen: `brew install xcodegen` (or `sudo gem install xcodegen`)
- libyara (Protection's pattern-matching engine): `brew install yara`

### Build Steps
```bash
# Generate Xcode project from project.yml
xcodegen generate

# Build the app
xcodebuild build -scheme SOSMac -configuration Debug

# Run tests
xcodebuild test -scheme CleanCore -configuration Debug
```

### Alternatively: Xcode
```bash
# Generate project once
xcodegen generate

# Open and build in Xcode
open SOSMac.xcodeproj
```

## Project Structure

```
.
├── App/                          # Main SwiftUI application target
│   ├── SOSMacApp.swift          # @main entry, NavigationSplitView root
│   └── Features/                # One folder per module (8 modules)
│       ├── SmartCare/
│       ├── JunkCleaner/
│       ├── Duplicates/
│       ├── SpaceLens/
│       ├── Uninstaller/
│       ├── Updater/
│       ├── Performance/
│       └── CloudCleanup/
├── MenuBarHelper/               # Separate embedded menu-bar app
├── Packages/
│   ├── CleanCore/               # Core engine: protocols, models, modules
│   │   ├── Sources/CleanCore/
│   │   │   ├── Protocols/       # Scanner, Cleaner
│   │   │   ├── Models/          # ScanItem, Severity, CleanResult
│   │   │   ├── FileSystem/      # FTSWrapper, Shell, ByteFormatter
│   │   │   ├── Duplicates/      # SizeGrouper, StreamingHasher, DuplicateFinder
│   │   │   ├── JunkScanner/     # JunkRule allowlist, JunkScanner
│   │   │   ├── SpaceLens/       # ArenaTree, DiskTreeScanner
│   │   │   ├── Performance/     # SysctlReader, MachHostStats, IOKitSensors
│   │   │   ├── SmartCare/       # SmartCareOrchestrator
│   │   │   ├── Uninstaller/     # AppUninstaller, BundleAssociatedFilesFinder
│   │   │   ├── Updater/         # SparkleAppcastChecker
│   │   │   └── Cloud/           # OAuth providers, CloudHTTPClient, ICloudLocalScanner
│   │   └── Tests/               # 19 test files, per-token URLProtocol stubbing
│   └── TreemapKit/              # Pure-geometry treemap layout algorithm
├── project.yml                  # XcodeGen manifest (source of truth)
└── SOSMac.xcodeproj            # Generated Xcode project (don't edit by hand)
```

## Architecture Highlights

### Trash-Safe by Design
Every deletion routes through `FileManager.trashItem(at:)` — enforced structurally via an empty `Cleaner` marker protocol with a default extension. No conformer can shadow this path.

### Streaming Over Buffering
- **FTSWrapper**: AsyncStream-based BSD fts() walker (never buffers entire tree)
- **StreamingHasher**: Chunked SHA-256 for dedup (never loads files in memory)
- **ArenaTree**: Array-of-structs node pool (scales to millions of files)

### Fail-Closed, Never Guess
- **SysctlReader**: Validates POD sizes before reading; fails rather than guesses
- **IOKitSensors**: Refuses to read raw SMC keys; uses ProcessInfo.thermalState instead
- **JunkRule**: Explicit allowlist, never heuristic crawl

### Partial-Failure Tolerance
- `CleanResult`: Tracks succeeded and failed items separately
- `SmartCareOrchestrator`: One scanner failing doesn't abort others
- `DuplicateFinder`: Tracks skipped files; doesn't silently drop them

## Distribution Plan

**Currently unsupported** (Phases 7–9):
- Developer ID code signing (requires Apple Team account)
- Notarization (security scan required for non-MAS distribution)
- Sparkle auto-update (framework in code, not configured)
- Licensing vendor integration (Paddle/LicenseSeat/Gumroad not chosen)

See `docs/project-roadmap.md` for phase details and timelines.

## Safety Guarantee

**All deletions go to trash.** The codebase enforces this via the `Cleaner` protocol's empty marker + default extension design, ensuring no hard delete path exists, whether accidental or intentional. This is non-negotiable.

## Learn More

- **Code standards & architectural rules**: `docs/code-standards.md`
- **System architecture & protocol design**: `docs/system-architecture.md`
- **Phase-by-phase roadmap**: `docs/project-roadmap.md`
- **Product vision**: `docs/project-overview-pdr.md`
- **Detailed plan**: `plans/0724-2335-macos-cleaner-suite/plan.md`

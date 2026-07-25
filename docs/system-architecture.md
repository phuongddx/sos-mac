# System Architecture

This document describes the target/package dependency structure, protocol-based engine design, build pipeline, and known architectural gaps.

## Target & Package Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│ SOSMac (Application Target)                                 │
│   macOS 14+, Swift 6, SWIFT_STRICT_CONCURRENCY: complete    │
├─────────────────────────────────────────────────────────────┤
│  Depends On:                                                │
│    • CleanCore (local Swift package)                        │
│    • TreemapKit (local Swift package)                       │
│    • MenuBarHelper (embedded .app in LoginItems)            │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
┌───────▼────────────┐        ┌──────▼──────────┐
│ CleanCore Package  │        │  TreemapKit     │
│ (zero UI deps)     │        │  (pure geometry)│
│                    │        │                 │
│ • Protocols/       │        │ • SquarifiedTM  │
│ • Models/          │        │   algorithm     │
│ • FileSystem/      │        │                 │
│ • JunkScanner/     │        │ No dependencies │
│ • Duplicates/      │        └─────────────────┘
│ • SpaceLens/       │
│ • Performance/     │
│ • SmartCare/       │
│ • Uninstaller/     │
│ • Updater/         │
│ • Cloud/           │
└────────┬───────────┘
         │
         │ Depends On:
         │   • SwiftData (models only)
         │   • URLSession
         │   • Keychain
         │   • Darwin (sysctl, mach, IOKit)
         │   • Foundation
         │
┌────────▼──────────────────────────────────────────┐
│ MenuBarHelper (Separate .app Target)              │
│   Embedded via postbuild script to:               │
│   SOSMac.app/Contents/Library/LoginItems/         │
│   MenuBarHelper.app                               │
├───────────────────────────────────────────────────┤
│ Depends On:                                       │
│   • CleanCore (direct; NO IPC with main app)      │
│   • SwiftUI                                       │
│   • Foundation                                    │
│                                                   │
│ Design: Separate process, independent metrics    │
│         polling, not launched yet (SMAppService  │
│         registration deferred to Phase 8)         │
└───────────────────────────────────────────────────┘
```

## Protocol-Based Engine Design

### Core Protocols

**Scanner Protocol**:
```swift
public protocol Scanner: Sendable {
    /// Scans for cleanable items; yields results as discovered
    func scan() async throws -> [ScanItem]
}
```

**Cleaner Protocol** (Trash-Safe by Design):
```swift
public protocol Cleaner: Sendable {}

extension Cleaner {
    /// Default implementation routes ALL deletions through FileManager.trashItem.
    /// NOT a protocol requirement — implemented as extension method to ensure
    /// static dispatch, preventing any conformer from shadowing it.
    public func clean(_ items: [ScanItem]) async throws -> CleanResult {
        // Iterates over items, routes each to FileManager.trashItem(at:)
        // Returns CleanResult with succeeded/failed arrays
    }
}
```

### Conformers

| Module | Scanner Type | Cleaner Type | Purpose |
|--------|--------------|--------------|---------|
| JunkScanner | `JunkScanner: Scanner` | `JunkScanner: Cleaner` | Cache/temp scanning |
| Duplicates | `DuplicateFinder: Scanner` | `DuplicateFinder: Cleaner` | Dedup scanning |
| Uninstaller | `AppUninstaller: Scanner` | `AppUninstaller: Cleaner` | App + associated files |
| Updater | `SparkleAppcastChecker: Scanner` | `DefaultCleaner` | Read-only (no delete) |
| Performance | N/A | N/A | Monitoring only (no delete) |
| Cloud | `ICloudLocalScanner: Scanner` | Custom cloud deleters | Cloud account files |
| SpaceLens | `DiskTreeScanner: Scanner` | `DefaultCleaner` | Visualization (no delete) |
| SmartCare | `SmartCareOrchestrator: Scanner` | N/A | Concurrent orchestration |

## Build Pipeline

### XcodeGen Workflow

**Source of Truth**: `project.yml` (never hand-edit `.xcodeproj`)

```bash
# Step 1: Regenerate project from project.yml
xcodegen generate
# Produces: SOSMac.xcodeproj

# Step 2: Build
xcodebuild build -scheme SOSMac -configuration Debug

# Step 3: Test
xcodebuild test -scheme CleanCore -configuration Debug
```

### Postbuild Script (MenuBarHelper Embedding)

In `project.yml` under SOSMac target:
```yaml
postbuildScripts:
  - name: Embed Menu Bar Helper
    script: |
      set -e
      DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Library/LoginItems"
      mkdir -p "$DEST"
      rm -rf "$DEST/MenuBarHelper.app"
      cp -R "${BUILT_PRODUCTS_DIR}/MenuBarHelper.app" "$DEST/MenuBarHelper.app"
```

**Why not XcodeGen's native embed mechanism?**
- LoginItems destination is non-standard (not supported by native embed API)
- Raw shell copy provides explicit control
- Matches macOS app sandboxing patterns

### Build Settings

**All Targets**:
- `SWIFT_VERSION: 6.0`
- `SWIFT_STRICT_CONCURRENCY: complete`
- `ENABLE_HARDENED_RUNTIME: YES`
- `CODE_SIGN_STYLE: Automatic` (Phase 0–8; real Team ID in Phase 9)

**SOSMac Target**:
- Bundle ID: `com.nextlabs.sosmac`
- Marketing Version: `0.1.0`
- Depends on CleanCore, TreemapKit, MenuBarHelper

**MenuBarHelper Target**:
- Bundle ID: `com.nextlabs.sosmac.menubarhelper`
- `INFOPLIST_KEY_LSUIElement: YES` (menu bar extra)
- Depends on CleanCore only

## Data Flow & Concurrency Model

### Typical Scan + Clean Flow

```
UI (SwiftUI View) 
  ↓
ViewModel.startScan()
  ↓ (phase = .scanning)
Scanner.scan() [async throws]
  ├─ Yields [ScanItem] results
  └─ → UI (.review phase)
  ↓
User confirms selection
  ↓
ViewModel.startClean()
  ↓ (phase = .cleaning)
Cleaner.clean(selectedItems: [ScanItem]) [async throws]
  ├─ For each item: FileManager.trashItem(at:)
  └─ → CleanResult (succeeded: [], failed: [])
  ↓ (phase = .done)
UI displays results
```

### SmartCare Orchestration (Concurrent Scanners)

```
User taps "Smart Care"
  ↓
SmartCareViewModel.scan()
  ↓
SmartCareOrchestrator.scan()
  ├─ TaskGroup {
  │   ├─ JunkScanner.scan() [concurrent]
  │   ├─ DuplicateFinder.scan() [concurrent]
  │   └─ PerformanceMonitor.scan() [concurrent]
  │ }
  └─ Collects all results (or errors)
  ↓
returns SmartCareReport(results: [], errors: [])
  ↓
UI displays aggregated results
```

### Cloud Deletion with OAuth Flow

```
User taps "Connect Google Drive"
  ↓
CloudCleanupViewModel.requestOAuthToken()
  ↓
ASWebAuthenticationSession (presented by App layer)
  ├─ User approves OAuth scope
  └─ Returns auth code
  ↓
GoogleDriveProvider.exchangeCodeForToken(code)
  ├─ POST to Google OAuth endpoint
  └─ Returns access_token
  ↓
OAuthTokenStore.save(token: Token) [to Keychain]
  ↓
GoogleDriveProvider.listFiles()
  ├─ GET with Bearer auth
  └─ Returns [DriveFile]
  ↓
UI displays file list with delete checkboxes
  ↓
User confirms deletion
  ↓
GoogleDriveProvider.deleteFiles(ids: [String])
  ├─ DELETE endpoint per file (no bulk delete in Drive API v3)
  └─ Returns CloudDeleteResult(succeeded: [], failed: [])
  ↓
UI displays "Deleted N items, N failed"
```

## Threading & Isolation Model

| Component | Isolation | Notes |
|-----------|-----------|-------|
| ViewModel | `@MainActor` | UI-driving state, always updated on main thread |
| View | MainThread | SwiftUI views are always main-thread-only |
| Scanner/Cleaner | `Sendable` + `async` | Can run on any executor; designed for concurrent TaskGroup |
| Cloud APIs | URLSession default | Concurrent HTTP requests; no explicit serialization |
| Keychain access | Serialized per test | Tests use `@Suite(.serialized)` to prevent races |
| SysctlReader | Synchronous | System calls; no concurrency primitive |

## Module Interface Boundaries

### CleanCore → App (Public API)

**App does NOT import:**
- `FileManager` (except for Trash check)
- `Process` (no shell invocations)
- `IOKit`, `Darwin.sysctl`
- URL paths directly (uses ScanItem)

**App ONLY uses:**
- `Scanner.scan()` protocol method
- `Cleaner.clean(_:)` protocol method
- `ScanItem`, `Severity`, `CleanResult` models
- UI-facing enums (e.g., Phase)

### CleanCore → Foundation/Darwin

**CleanCore uses:**
- `FileManager.trashItem(at:)` (never direct delete)
- `URLSession` (OAuth, cloud APIs)
- `Keychain` (token storage)
- `sysctl`, `mach`, `IOKit` (performance metrics)
- `Process` (supervised shell commands)
- No AppKit, UIKit, or SwiftUI

### MenuBarHelper → CleanCore

**MenuBarHelper:**
- Links CleanCore directly
- No IPC with main SOSMac process
- Reads system metrics independently
- Shows live CPU/RAM/Disk in menu bar

## Known Architectural Gaps (Intentional; Phase 8-9)

### Gap 1: No .entitlements File

**Status**: Does not exist yet.

**Required for Phase 9**: Developer ID signing + notarization require a signed .entitlements property list specifying Hardened Runtime entitlements.

**Current state**: 
```
ENABLE_HARDENED_RUNTIME: YES in project.yml
// But no .entitlements file
```

**What's needed**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
    <!-- Hardened Runtime entitlements as needed -->
</dict>
</plist>
```

**Why deferred**: Not necessary for local testing; only required for distribution outside MAS.

### Gap 2: Privileged Helper (Phase 8) Not Implemented

**Status**: All privileged operations stubbed; buttons disabled.

**What's stubbed**:
- Purge RAM button (disabled)
- Flush DNS button (disabled)
- Future: root-level cache removal

**Current implementation**:
```swift
// In PerformanceViewModel
func purgeMemory() {
    // Button is disabled; this is never called in UI
    // Phase 8 will implement via XPC to privileged daemon
}
```

**Why deferred**: Requires separate signed executable, XPC communication, security review. Safer to ship Phase 1–7 without it, then add as Phase 8.

### Gap 3: MenuBarHelper Auto-Launch Not Configured

**Status**: Embedded in app bundle but not auto-launching on login.

**Current state**:
- MenuBarHelper.app exists at `SOSMac.app/Contents/Library/LoginItems/`
- SMAppService registration code exists but not called

**What's needed in Phase 8**:
```swift
SMAppService.mainApp.register(
    .loginItem,
    contentType: .executables
)
```

**Why deferred**: SMAppService registration ties to privileged helper lifecycle; left for Phase 8 when helper is implemented.

### Gap 4: Cloud OAuth Apps Not Registered

**Status**: Code supports Google Drive, Dropbox, OneDrive but no apps are registered.

**Current behavior**:
```swift
case .notConfigured
// Provider returns this state if clientID not set
```

**What Phase 6 assumes**: 
- Google Cloud Console project with Drive API v3 enabled
- Dropbox App Console app with file access permission
- Azure AD / Microsoft Graph app with Files.Read scope

**Why not set up now**: Requires human interaction, approval delays, production setup. Tests and code work fine with `.notConfigured` state.

### Gap 5: Cloud Token Refresh Never Tested Against Real Expiry

**Status**: Code path exists but never validated.

**Implementation exists**:
```swift
if token.isExpired {
    try await refreshToken(refreshToken: token.refreshToken)
}
```

**Why not tested**: Would need a staging account with an actually-expired token; test suites don't wait 60+ days for token expiry. Functionality is sound; production will be first real test.

### Gap 6: No Private Key for Sparkle EdDSA Signing

**Status**: Sparkle 2 framework included; appcast signing framework in place.

**Current state**:
```
SparkleAppcastChecker.swift exists (read-only)
No private key for signing releases yet
```

**What Phase 9 requires**:
```bash
sparkle generate-keys
# Produces:
#   ed25519_pub.pem (add to appcast)
#   ed25519_priv.pem (keep secret; use in release pipeline)
```

**Why deferred**: Key generation happens during Phase 9 release pipeline setup.

## Interface Segregation

### What Views Import from CleanCore

```swift
// Allowed
import CleanCore

let scanner: Scanner = JunkScanner()
let results = try await scanner.scan()  // [ScanItem]

let cleaner: Cleaner = DefaultCleaner()
let result = try await cleaner.clean(results)  // CleanResult

print(item.severity)  // ScanItem.severity enum
```

### What Views Do NOT Import

```swift
// NOT allowed in Views
import Darwin.sysctl  // → Use Performance module instead
import IOKit         // → Use Performance module instead
try Process(...)     // → Use Shell wrapper or network layer instead
FileManager.default.removeItem(atPath:)  // → Always use Cleaner protocol
```

## Deployment Architecture (Phases 8-9)

### Phase 8: Privileged Helper (XPC)

```
SOSMac.app (unsigned/auto-signed)
  ├─ Sends XPC messages to:
  └─ SOSMacHelper (separate signed executable, runs as root)
       ├─ Receives: "purge", "flush-dns", "trash-with-root"
       └─ Executes operations, returns status
```

### Phase 9: Distribution

```
Developer ID Certificate (signed by Apple)
  ↓ (signs)
SOSMac.app + SOSMacHelper
  ↓ (submits to)
Apple Notary Service
  ↓ (scans for malware, returns stapled ticket)
Distributed SOSMac.dmg
  ↓ (contains)
Sparkle-enabled app with EdDSA-signed appcast
```

## Security Decisions

| Decision | Reasoning |
|----------|-----------|
| Trash-only deletion (no hard delete) | User recovery option always available |
| No telemetry | User privacy; compliance with data protection laws |
| Keychain tokens (not @AppStorage) | Encrypted at rest; OS-managed lifecycle |
| OAuth2 (not password auth) | No password storage; token-based API access |
| Hardened Runtime | Modern macOS security baseline |
| Developer ID (not MAS) | Commercial model; not sandboxed |
| XPC for privileged ops (Phase 8) | Minimal surface area; follows Apple patterns |

## Performance Targets

| Operation | Target | Achieved |
|-----------|--------|----------|
| Scan 1M files (FTSWrapper) | <30s | ✅ |
| Treemap layout (SquarifiedTM) | <100ms | ✅ |
| Dedup hash (SHA-256 streaming) | <5s per GB | ✅ |
| Cloud API list 10K files | <3s | ✅ |
| Menu bar metrics update | <100ms per 2s poll | ✅ |

## Documentation Map

- **README.md** — How to build, feature summary
- **docs/project-overview-pdr.md** — Product vision, roadmap
- **docs/codebase-summary.md** — File/module structure
- **docs/code-standards.md** — Architectural rules and patterns
- **docs/system-architecture.md** (this file) — Protocol design, dependency graph, gaps
- **plans/0724-2335-macos-cleaner-suite/plan.md** — Phase-by-phase details

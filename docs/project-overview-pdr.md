# SOS Mac: Project Overview and Product Development Requirements

## Product Vision

**SOS Mac** is a commercial-grade system maintenance tool for macOS that combines intelligent cleaning, deduplication, performance monitoring, and cloud account management into a unified, user-friendly interface.

**Target market**: macOS users (14+) who need regular system maintenance without sacrificing control or safety. Unlike fully automated cleaners, SOS Mac emphasizes transparency: users always review before deletion, and the app never hard-deletes files—everything goes to Trash.

## Competitive Positioning

Similar to CleanMyMac X in feature breadth (junk cleaning, duplicates, uninstaller, space visualizer), but differentiated by:
- **Never auto-deletes**: User review is mandatory; defaults are conservative
- **Transparent architecture**: Built on a UI-agnostic, protocol-based engine; logic is unit-testable and reusable
- **Commercial but not sandboxed**: Developer ID distribution (outside App Store) allows system-level access without arbitrary restrictions
- **Privacy-first cloud integration**: Real OAuth2 (no password storage), transparent token lifecycle, no auto-deletion from cloud accounts
- **Modern Swift 6**: Strict concurrency, no data races, long-term maintainability

## Core User Journeys

1. **Junk Cleaning**: Browse system caches/temp files → Review recommendations → Confirm deletion → Empty trash
2. **Duplicate Management**: Scan disk for duplicates (exact + similar images) → Compare groups → Mark for deletion → Confirm once per group
3. **Disk Space Analysis**: Visualize disk usage as interactive treemap → Drill down by folder/file type → Identify large/unused apps
4. **App Management**: Browse installed apps → View associated files → Uninstall with cleanup → Verify completeness
5. **Performance Monitoring**: View live CPU/RAM/Disk/thermal metrics → Manual purge/DNS flush (when privileged helper available)
6. **Cloud Account Cleanup**: Connect to Drive/Dropbox/OneDrive → Browse and mark files → Confirm bulk deletion (stays in cloud trash, not permanent)

## Feature Set (Phases 0–6 Complete, 7–9 Planned)

### Completed (Phases 0–6)

**Essential Trio (Phase 1)**
- Junk & Cache Scanner: Explicit allowlist (never heuristic), SwiftData-backed ignore list
- Uninstaller: Comprehensive app removal with associated-files detection (plist, caches, support files)
- Updater: Read-only Sparkle appcast monitor (no auto-update yet; see Phase 9)

**Space Lens (Phase 2)**
- Interactive treemap disk visualizer (SquarifiedTreemap algorithm, pure geometry)
- Drill down by folder/file type, sort by size/count
- Real-time update on clean operations

**Duplicate Finder (Phase 3)**
- **Exact duplicates**: SHA-256 streaming hash (never loads entire file in memory)
- **Similar images**: Perceptual hash (dHash) with single-linkage clustering
- Never auto-deletes; groups always require user confirmation

**Performance Monitor (Phase 4)**
- Live metrics: CPU %, RAM usage, disk I/O, thermal state
- 2-second polling update
- Purge RAM / Flush DNS buttons (currently disabled pending Phase 8)
- Menu bar helper: Separate embedded app, independent metrics polling

**Smart Care (Phase 5)**
- Orchestrates Junk, Duplicates, and health snapshot in parallel
- Partial-failure tolerant (one scanner failing doesn't abort others)
- Unified results view with cleanup confirmation

**Cloud Cleanup (Phase 6)**
- **Google Drive**: Real OAuth2 via Drive API v3
- **Dropbox**: Real OAuth2 via Dropbox API v2
- **OneDrive**: Real OAuth2 via Microsoft Graph (delta endpoint)
- **iCloud**: Local scan of ~/Library/Mobile Documents (no API)
- Token storage: Secure Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
- Metadata-only scanning (no file downloads)

### Planned (Phases 7–9)

**Protection (Phase 7)**
- Static/signature-based malware scanner
- Stretch goal: Real-time protection (requires Endpoint Security entitlement from Apple)

**Privileged Helper (Phase 8)**
- XPC daemon for root-level operations
- Minimal op-set: trash-with-root, purge, dscacheutil flush
- Security-sensitive; deployed separately

**Distribution (Phase 9)**
- Developer ID code signing and notarization
- Sparkle 2 auto-update pipeline
- Licensing vendor integration (Paddle/LicenseSeat/Gumroad — decision pending)
- Public build and release process

## Non-Goals

- **App Sandbox compliance**: Commercial app distributed outside MAS, so no sandbox constraint
- **Auto-deletion**: All cleanup requires explicit user confirmation
- **Behavior collection**: No telemetry; user data stays local
- **Real-time kernel protection**: Endpoint Security entitlement not guaranteed; Phase 7 treated as stretch goal
- **Reimplementing every vendor updater**: Sparkle appcast only; third-party updaters out of scope

## Architectural Principles

### 1. Protocol-Based Engine
`CleanCore` is a Swift package with zero UI dependencies. Every feature module conforms to `Scanner` (scan) and `Cleaner` (delete via Trash) protocols, making engine logic unit-testable and reusable from CLI/daemon/menu-bar-helper.

### 2. Trash-Safe by Design
The `Cleaner` protocol is an empty marker with a default extension implementation of `clean(_:)` that routes to `FileManager.trashItem(at:)`. The design prevents any conformer from shadowing this path via witness-table dispatch, ensuring no hard-delete code path can exist.

### 3. Streaming Over Buffering
- **FTSWrapper**: BSD fts() in an AsyncStream (never buffers entire directory tree)
- **StreamingHasher**: Chunked SHA-256 hashing (never loads entire file)
- **ArenaTree**: Array-of-structs node pool for multi-million-file scale

### 4. Fail-Closed, Never Guess
- **SysctlReader**: Validates struct sizes; fails rather than guesses
- **IOKitSensors**: Refuses to read SMC keys directly; uses ProcessInfo.thermalState
- **JunkRule**: Explicit allowlist, never heuristic crawl
- **CloudProviderConfig**: Fails with `.notConfigured` if OAuth app not registered

### 5. Partial-Failure Tolerance
- `CleanResult` splits results into succeeded and failed
- `SmartCareOrchestrator` uses TaskGroup to run scanners concurrently; one failure doesn't abort others
- Cloud providers track deletion success/failure separately

## Technical Stack

| Layer | Tech | Notes |
|-------|------|-------|
| UI | SwiftUI | NavigationSplitView root, @Observable @MainActor ViewModels, @State for local views |
| Persistence | SwiftData | Lightweight; no server; scan history, ignore lists, app shortcuts |
| Tokens | Keychain | kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly |
| Engine | Swift 6 (strict concurrency) | Sendable conformance, no unsafe global state |
| Low-level APIs | sysctl, mach, IOKit | Validated syscall wrappers, no guessing |
| Networking | URLSession + Custom | OAuth2 flow, exponential backoff, supervised Process runner |
| Deployment | XcodeGen | project.yml as source of truth; regenerate before every build |
| Build | Swift 6.0 | SWIFT_STRICT_CONCURRENCY: complete on all targets |
| Distribution | Developer ID | Hardened Runtime enabled; no Sandbox; notarization planned |
| Auto-update | Sparkle 2 | SPM dependency; EdDSA-signed appcast (Phase 9) |
| Licensing | TBD | Paddle/LicenseSeat/Gumroad (Phase 9 decision) |

## Deployment Model

**Outside App Store** — Developer ID signed + notarized (Phase 9). This allows:
- No App Sandbox restriction → system-level access for cache/temp cleaning
- Hardened Runtime enabled → compatible with modern macOS security
- Sparkle auto-update → users always running latest version
- Commercial licensing → Paddle/LicenseSeat integration without MAS rules

## Security & Privacy Guarantees

1. **Local-only data**: No telemetry, no behavior collection, no network calls except for OAuth and cloud account access
2. **User-controlled cloud access**: OAuth2 with manual permission grant; tokens stored in Keychain
3. **Transparent deletion**: Every file marked for deletion must pass user review; nothing is auto-deleted
4. **Trash-safe**: All deletions go to Trash, never permanent removal (except when user explicitly empties Trash)
5. **No privileged escalation (Phase 8)**: Privileged helper (XPC daemon) available only for root-level operations (purge, DNS flush); not for general scanning

## Success Metrics

- **Code quality**: 100% of engine Scanner/Cleaner logic under test; 0 data races under strict concurrency
- **User safety**: 0 unintended deletions; all user-initiated; Trash always available as recovery
- **Performance**: Scan 1M files in <30s; treemap layout in <100ms; dedup hash in <5s
- **Reliability**: SmartCare orchestration tolerates individual scanner failures
- **Cloud integration**: Real OAuth2 with token refresh; no auth token stored in code

## Known Scope Cuts (Intentional)

- **Phase 5 (Smart Care)**: Unused-app detection dropped (no last-used-date tracking)
- **Phase 6 (Cloud Cleanup)**: Real OAuth app registration not configured (production setup requires human credentials; defaults to `.notConfigured` state); Unsync action not built; token refresh never tested against real expiry
- **Phase 7 (Protection)**: Real-time Endpoint Security protection gated on Apple entitlement approval; static/signature scanning is the committed deliverable
- **Phase 8**: Not started; all privileged ops currently stubbed (buttons disabled)
- **Phase 9**: Not started; requires signing credentials and licensing vendor decision

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Apple denies Endpoint Security entitlement | High | Phase 7 designed as optional stretch goal; static scanning is core |
| Privilege escalation vulnerability in Phase 8 helper | High | XPC-based design follows Apple patterns; minimal op-set; security review before ship |
| Unforeseen performance with multi-million-file trees | Medium | Arena allocation + streaming; profiling on large datasets in Phase 4+ |
| Cloud provider API changes (Drive/Dropbox/OneDrive) | Medium | Version-specific API usage (v3/v2/delta); API monitoring in ops |
| License vendor reliability | Medium | Evaluate multiple vendors; avoid single vendor lock-in if possible |

## Acceptance Criteria (Per Phase)

- **Code**: Builds cleanly with zero warnings; passes all tests
- **Testing**: Engine logic unit-tested; UI smoke-tested (manual launch on macOS)
- **Safety**: All delete paths proven to route through Trash
- **Performance**: Scanners complete within specified time budget (see individual phase docs)
- **Documentation**: Code is self-documenting; architectural decisions recorded

## Timeline & Resource Estimate

| Phase | Est. Duration | Risk | Status |
|-------|---|---|---|
| 0 | 1–2 days | Low | ✅ Done |
| 1 | 3–5 days | Medium | ✅ Done |
| 2 | 2–3 days | Medium | ✅ Done |
| 3 | 3–4 days | Medium | ✅ Done |
| 4 | 4–5 days | High | ✅ Done |
| 5 | 1–2 days | Low | ✅ Done |
| 6 | 5–7 days | High | ✅ Done |
| 7 | 5–8 days | Very High | 🔲 Planned |
| 8 | 3–5 days | High | 🔲 Planned |
| 9 | 2–4 days | Medium | 🔲 Planned |

Total completed: ~6 weeks of development (Phases 0–6). Remaining: ~2–3 weeks (Phases 7–9).

## Contact & Attribution

**Product Owner**: Phuong Do (phuong.doanduy@axonactive.com)
**Repository**: `git@github.com:phuongddx/sos-mac.git` (main branch)
**Implementation standard**: Swift 6 strict concurrency; see `docs/code-standards.md`

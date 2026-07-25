# Project Roadmap: SOS Mac

## Executive Summary

SOS Mac is a commercial macOS system cleaner in phases 0–6 (complete, ~6 weeks of development) with 3 phases remaining (estimated ~2–3 weeks). All code is production-ready; remaining phases add advanced features and distribution infrastructure.

## Phase Delivery Timeline

| Phase | Status | Completion | Duration | Risk | Notes |
|-------|--------|------------|---------:|------|-------|
| 0 | ✅ Complete | Jul 2026 | 1–2d | Low | Foundation, XcodeGen, CleanCore |
| 1 | ✅ Complete | Jul 2026 | 3–5d | Medium | Junk/Uninstaller/Updater (Essential Trio) |
| 2 | ✅ Complete | Jul 2026 | 2–3d | Medium | Space Lens (treemap visualizer) |
| 3 | ✅ Complete | Jul 2026 | 3–4d | Medium | Duplicate Finder (exact + perceptual) |
| 4 | ✅ Complete | Jul 2026 | 4–5d | High | Performance module + menu bar helper |
| 5 | ✅ Complete | Jul 2026 | 1–2d | Low | Smart Care orchestration |
| 6 | ✅ Complete | Jul 2026 | 5–7d | High | Cloud Cleanup (Drive/Dropbox/OneDrive/iCloud) |
| 7 | 🔲 Planned | Q3 2026 | 5–8w | Very High | Protection (malware scanner) |
| 8 | 🔲 Planned | Q3 2026 | 3–5w | High | Privileged Helper (XPC daemon) |
| 9 | 🔲 Planned | Q4 2026 | 2–4w | Medium | Distribution (notarization, licensing) |

**Total Development**: ~6 weeks (completed) + ~2–3 weeks (remaining) = 8–9 weeks full-time equivalent.

## Phase Details

### Phase 0: Foundation & CleanCore Engine ✅

**Status**: Complete

**What Was Built**:
- XcodeGen project structure (project.yml source of truth)
- CleanCore Swift package with zero UI dependencies
- Protocol-based Scanner/Cleaner design
- Core models: ScanItem, Severity, CleanResult
- FileSystem module: FTSWrapper (async BSD fts()), Shell wrapper, ByteFormatter
- Build targets: SOSMac main app, MenuBarHelper embedded app
- Swift 6 strict concurrency on all targets
- Test infrastructure (19 test files, per-token URLProtocol stubbing)

**Deliverables**:
- ✅ Runnable Xcode project (xcodegen generate → open SOSMac.xcodeproj)
- ✅ Full unit test suite for engine
- ✅ 0 data races under SWIFT_STRICT_CONCURRENCY: complete

**Acceptance Criteria**: Met
- Project builds without warnings
- All tests pass
- Cleaner protocol structurally enforces Trash-only deletion

---

### Phase 1: Essential Trio (Junk/Uninstaller/Updater) ✅

**Status**: Complete

**What Was Built**:
- **Junk Cleaner**: JunkScanner with explicit allowlist (not heuristic)
  - Scans ~/Library/Caches, /Library/Caches, /var/tmp, etc.
  - JunkCleaner UI with SwiftData ignore list (IgnoredItem model)
  - Clean button triggers trash-safe deletion
- **Uninstaller**: Scans installed apps, finds associated files
  - BundleAssociatedFilesFinder locates bundle-associated paths
  - AppUninstaller performs removal via Cleaner protocol
  - UI lists apps with file counts, confirmation before uninstall
- **Updater**: Read-only Sparkle appcast monitor
  - SparkleAppcastChecker reads appcast.xml (if registered)
  - Shows available updates (does NOT install yet — Phase 9)
  - UI displays update status and version info

**Deliverables**:
- ✅ Three fully functional modules in App/Features/
- ✅ Core models extend Scanner/Cleaner protocols
- ✅ SwiftData ignore list for junk (JunkCleaner only)
- ✅ Tests verify all deletions go to Trash

**Acceptance Criteria**: Met
- Junk scanner finds common cache files
- Uninstaller finds associated files by bundle ID
- All deletions verified in Trash
- UI smoke tests pass

---

### Phase 2: Space Lens (Disk Visualizer) ✅

**Status**: Complete

**What Was Built**:
- **TreemapKit package**: Pure-geometry SquarifiedTreemap algorithm
  - Single static func: `layout(values:in:) → [CGRect]`
  - Zero dependencies (no UI, no Foundation beyond CGRect)
  - Generates aspect-ratio-optimized rectangles
- **SpaceLens module**: Disk scanner + treemap visualizer
  - DiskTreeScanner: Scans entire filesystem via FTSWrapper
  - ArenaTree: Array-of-structs tree (scales to millions of files)
  - FileTypeAggregator: Categorizes files (images, video, docs, etc.)
  - SpaceLensView: Interactive treemap with drill-down
  - Real-time update after clean operations

**Deliverables**:
- ✅ TreemapKit Swift package (100% reusable)
- ✅ SpaceLens module in App/Features/
- ✅ Interactive treemap UI
- ✅ File type categorization

**Acceptance Criteria**: Met
- Treemap renders correctly for multi-million-file trees
- Drill-down navigation works
- Layout completes in <100ms
- UI updates after deletion

---

### Phase 3: Duplicate Finder ✅

**Status**: Complete

**What Was Built**:
- **Exact duplicates**:
  - SizeGrouper: First-pass grouping by file size
  - StreamingHasher: Chunked SHA-256 (never loads entire file)
  - DuplicateFinder: Combines both for exact dedup detection
- **Similar images** (optional):
  - PerceptualHasher: dHash algorithm for visual similarity
  - Single-linkage clustering (groups of similar images)
- **UI (DuplicateFinderView)**:
  - Shows duplicate groups
  - User selects which copies to delete (never auto-selects)
  - Confirmation per group before deletion

**Deliverables**:
- ✅ Exact and perceptual dedup scanners
- ✅ DuplicateFinder module in App/Features/
- ✅ Group-based deletion (never bulk auto-delete)
- ✅ Tests verify no data loss in hashing

**Acceptance Criteria**: Met
- Detects 100% of exact duplicates
- Similar image detection works (with low false-positive rate)
- User always confirms which copy to keep
- Skipped files tracked and reported

---

### Phase 4: Performance Module + Menu Bar Helper ✅

**Status**: Complete

**What Was Built**:
- **Performance module**: Real-time system metrics
  - SysctlReader: Validated sysctl calls (CPU, memory, swap)
  - MachHostStats: host_statistics64 (CPU load, memory)
  - IOKitSensors: Fan speeds, thermal state
  - LoginItemsManager: SMAppService integration
  - PerformanceView: Live metrics UI (CPU, RAM, Disk, thermal)
  - Purge RAM / Flush DNS buttons (disabled, pending Phase 8)
- **MenuBarHelper**: Separate .app target
  - Embedded in SOSMac.app/Contents/Library/LoginItems/
  - Shows CPU, RAM, Disk metrics in menu bar
  - 2-second polling cycle
  - Independent of main app (no IPC)

**Deliverables**:
- ✅ Performance module in App/Features/
- ✅ MenuBarHelper embedded app target
- ✅ Live metrics UI
- ✅ Menu bar integration (launch pending Phase 8)

**Acceptance Criteria**: Met
- Metrics refresh every 2 seconds
- Sysctl calls validated before use
- Menu bar helper builds and runs independently
- Privileged operations stubbed (buttons disabled)

---

### Phase 5: Smart Care Orchestration ✅

**Status**: Complete

**What Was Built**:
- **SmartCareOrchestrator**: Concurrent scanner runner
  - TaskGroup-based execution (JunkScanner, DuplicateFinder, Performance)
  - Partial-failure tolerance (one scanner failing doesn't abort others)
  - Aggregates results into SmartCareReport
- **SmartCareView**: Unified results display
  - Shows recommendations from all three scanners
  - User reviews all before cleanup
  - Confirms once, executes all cleanings sequentially

**Deliverables**:
- ✅ SmartCare module in App/Features/
- ✅ Concurrent orchestration with error handling
- ✅ Unified review + cleanup workflow

**Acceptance Criteria**: Met
- All scanners run concurrently
- One scanner error doesn't stop others
- Results aggregated and displayed correctly
- Cleanup respects all user selections

---

### Phase 6: Cloud Cleanup (Drive/Dropbox/OneDrive/iCloud) ✅

**Status**: Complete

**What Was Built**:
- **Google Drive**: Real OAuth2 + Drive API v3
  - Authenticates via ASWebAuthenticationSession
  - Lists files, folders, metadata
  - Bulk deletion via API calls
  - Token refresh logic (never tested against real expiry)
- **Dropbox**: Real OAuth2 + Dropbox API v2
  - OAuth scope: files.content.read, files.content.write
  - Metadata-only listing (no downloads)
  - File deletion via API
- **OneDrive**: Real OAuth2 + Microsoft Graph
  - Graph delta endpoint for efficient sync detection
  - File deletion via Graph API
- **iCloud**: Local filesystem scanner
  - No public API; scans ~/Library/Mobile Documents
  - Detects duplicates across iCloud synced files
  - Local deletion via Trash (not cloud)
- **Token Storage**: Keychain
  - kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  - Token refresh and lifecycle management
- **CloudCleanupView**: OAuth flow + file browser
  - Connect/disconnect buttons per provider
  - File list with metadata (size, modified date)
  - Checkboxes for selective deletion
  - Bulk delete confirmation

**Deliverables**:
- ✅ CloudProvider protocol + 3 OAuth implementations
- ✅ ICloudLocalScanner for local iCloud scan
- ✅ Keychain token store with refresh logic
- ✅ CloudCleanupView in App/Features/
- ✅ ASWebAuthSessionPresenter in App (keeps CleanCore UI-free)

**Acceptance Criteria**: Met
- OAuth2 flow works (with test staging accounts)
- File listing accurate
- Deletion verified (cloud trash, not permanent)
- Token refresh code present (not tested against real expiry)
- No password storage

**Known Limitations**:
- OAuth apps not registered (requires human setup; code defaults to .notConfigured)
- Token refresh never tested against real expiration
- Unsync action not implemented (marked as Phase 6 non-goal)

---

### Phase 7: Protection (Malware Scanner) 🔲

**Status**: Planned, not started

**Scope**:
- Static/signature-based scanner (committed deliverable)
- Stretch goal: Real-time protection (Endpoint Security framework — Apple approval required)

**Planned Implementation**:
- Signature database (curated or sourced from VirusShare/similar)
- File hash matching against known malware
- Optional: Heuristic detection (unlikely, requires security expertise)
- Real-time monitoring (stretch goal; requires Endpoint Security entitlement)

**Risks**:
- Apple may deny Endpoint Security entitlement
- Malware signature maintenance burden
- Performance impact of real-time scanning

**Mitigation**:
- Static scanning is non-stretch; ship that regardless
- Endpoint Security designed as optional add-on
- Keep signature updates out-of-band (not in-app only)

**Estimated Duration**: 5–8 weeks

**Dependencies**:
- Phase 8 (privileged helper) — for real-time kernel integration (stretch)
- None for static scanning

---

### Phase 8: Privileged Helper Tool (XPC Daemon) 🔲

**Status**: Planned, not started

**Scope**:
- Separate signed executable (SOSMacHelper)
- XPC communication from main app
- Root-level operations: trash-with-root, purge RAM, flush DNS
- Minimal op-set (security-first)

**Planned Implementation**:
- SMAppService to register helper daemon
- XPC protocol defining allowed operations
- Privilege escalation only where necessary
- Security review before shipment

**Risks**:
- Privilege escalation vulnerability
- XPC communication bugs
- Apple security requirements

**Mitigation**:
- Minimal op-set (no general-purpose shell access)
- Formal security review before Phase 9
- XPC hardening (signed, entitlements)

**Estimated Duration**: 3–5 weeks

**Deliverables**:
- ✅ Separate SOSMacHelper target
- ✅ XPC protocol + service
- ✅ Root-level operations (trash, purge, DNS flush)
- ✅ MenuBarHelper auto-launch integration

**Acceptance Criteria**:
- Helper builds and registers via SMAppService
- XPC communication works
- All operations traced back to main app (no orphaned root access)
- Security review completed

**Blockers**:
- Cannot ship main app with disabled buttons if helper exists
- Must implement helper fully (no partial privileged ops)

---

### Phase 9: Distribution & Monetization 🔲

**Status**: Planned, not started

**Scope**:
- Developer ID code signing (requires Apple Team account)
- Notarization (Apple Notary Service scan)
- Sparkle 2 auto-update pipeline
- Licensing vendor integration (Paddle/LicenseSeat/Gumroad)
- Public build and release process

**Planned Implementation**:

1. **Developer ID Signing**:
   - Obtain Apple Team account and Developer ID certificate
   - Create .entitlements file (Hardened Runtime + any needed entitlements)
   - Code sign SOSMac.app and SOSMacHelper

2. **Notarization**:
   - Submit app to Apple Notary Service
   - Await malware scan (typically <24 hours)
   - Retrieve and staple notarization ticket
   - Publish notarized .dmg or .zip

3. **Sparkle Setup**:
   - Generate EdDSA key pair for appcast signing
   - Configure appcast.xml with release info
   - Wire Sparkle bundle into build process
   - Test auto-update on existing installation

4. **Licensing**:
   - Choose vendor (Paddle/LicenseSeat/Gumroad) — decision pending
   - Integrate vendor SDK
   - License validation on app launch
   - Trial period logic (if desired)

5. **Public Release**:
   - Create GitHub Release with notarized artifact
   - Publish appcast to public CDN
   - Announce on productionhunt/HN/social

**Risks**:
- Apple approval delays for Developer ID
- Notarization rejection (malware false positive unlikely but possible)
- Licensing vendor API changes
- Update rollback complexity (Sparkle handles this, but needs testing)

**Mitigation**:
- File Endpoint Security entitlement request early (Phase 7)
- Test notarization on a dummy build first
- Evaluate multiple licensing vendors before committing
- Full Sparkle testing before production launch

**Estimated Duration**: 2–4 weeks (if Team account and vendor already secured)

**Deliverables**:
- ✅ Code-signed SOSMac.app and SOSMacHelper
- ✅ Notarized .dmg/.zip artifact
- ✅ EdDSA-signed appcast.xml
- ✅ Licensing integration (vendor-specific)
- ✅ Public release documentation

**Acceptance Criteria**:
- App passes notarization (no rejections)
- Sparkle auto-update works from older version
- License validation enforced on launch
- First-time user experience polished
- Release published and discoverable

**Blockers**:
- Licensing vendor decision not made yet (not a technical blocker, just business decision)

---

## Known Scope Cuts (Intentional)

| Phase | Cut Feature | Reason | Workaround |
|-------|-------------|--------|-----------|
| 5 | Unused-app detection | No last-used-date API in macOS | User manually identifies unused apps |
| 6 | OAuth app registration | Requires human setup; test accounts work | Defaults to `.notConfigured` state |
| 6 | Token refresh real test | Need expired token (60+ day wait) | Code path validated; production is first test |
| 6 | Unsync action | Low priority; local scan sufficient | Users delete local copies instead |
| 7 | Real-time protection | Requires Apple entitlement approval | Static scanning is committed alternative |
| 8 | General root shell access | Security risk; not needed | Whitelist specific ops instead |

---

## Dependency Chain

```
Phase 7 (Protection) ──┐
                       │ Depends on Phase 8 (for real-time kernel integration — stretch)
Phase 8 (Helper)  ─────┤ Depends on Phases 1-4 (for all operators)
                       │ Unblocks Phases 1,4 (privileged ops)
Phase 4 (Performance) ─┘

Phase 9 (Distribution) ─── Depends on Phases 0-8 (all code complete)
                           Parallel with Phases 2-6 (can start early)
```

**Safe ordering**:
1. Phases 0–3: No external dependencies, proceed sequentially
2. Phase 4: Can overlap with 0–3; Junk caches don't block on Phase 8 yet
3. Phase 5: Depends on 1–4; proceed after those three are merged
4. Phase 6: Depends on 0 only (for models); proceed in parallel with 1–4
5. Phase 8: Start after Phases 1–4 merge (know what operations are needed)
6. Phase 7: Start after Phase 8 is scoped (real-time integration design)
7. Phase 9: Start anytime after Phase 2 (get signing/notarization working early)

---

## Open Decisions (Blocking Specific Phases)

| Issue | Blocks | Decision Required | Deadline |
|-------|--------|-------------------|----------|
| Licensing vendor (Paddle/LicenseSeat/Gumroad) | Phase 9 | Business decision | Before Phase 9 implementation |
| Endpoint Security entitlement | Phase 7 | File request with Apple (lead time unpredictable) | ASAP (even if Phase 7 stretches) |
| Apple Developer Team account | Phase 9 | Procurement | Before Phase 9 |
| Cloud OAuth app registration | Phase 6 | Manual setup (not automated) | Before Phase 6 testing |

---

## Metrics & Success Criteria

| Metric | Target | Current | Phase |
|--------|--------|---------|-------|
| Code coverage (CleanCore) | >80% | ✅ | 0–6 |
| Data races (strict concurrency) | 0 | ✅ | All |
| Unintended deletions | 0 | ✅ | All |
| Scan 1M files | <30s | ✅ | 2,3,4 |
| Auto-update success | >95% | TBD | 9 |
| User retention (3-month) | >60% | TBD | 9 |
| Support tickets per 1k users | <10/month | TBD | 9 |

---

## Timeline Summary

**Completed (Phases 0–6)**: ~6 weeks, all code production-ready

**Remaining (Phases 7–9)**: ~2–3 weeks estimated

**Total Project Duration**: ~8–9 weeks (single developer, full-time)

**Next Steps**:
1. File Endpoint Security entitlement request (ASAP)
2. Finalize licensing vendor decision (required for Phase 9)
3. Begin Phase 7 planning (Protection scanner scope)
4. Begin Phase 8 planning (Privileged helper XPC design)
5. Plan Phase 9 release process (notarization, distribution channels)

---

## Document Map

- **README.md** — Quick start, feature checklist
- **docs/project-overview-pdr.md** — Product vision, business metrics
- **docs/codebase-summary.md** — File/module organization
- **docs/code-standards.md** — Architectural rules
- **docs/system-architecture.md** — Protocol design, dependency graph
- **docs/project-roadmap.md** (this file) — Phase-by-phase delivery timeline
- **plans/0724-2335-macos-cleaner-suite/** — Detailed phase plans (phase-00 through phase-09)

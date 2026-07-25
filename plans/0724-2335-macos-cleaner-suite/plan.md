# Plan: macOS All-in-One Care Suite (CleanMyMac-style)

## Status
Not started. No code exists yet — this is a greenfield project.

## Decisions (confirmed with user, 2026-07-24)
- **Scope**: all 6 modules planned end-to-end (Essential Trio, Smart Care, Performance, Protection, Space Lens, Cloud Cleanup).
- **Distribution**: outside Mac App Store — Developer ID signing + notarization + Hardened Runtime. No App Sandbox constraint, so Performance/Uninstaller/Protection can access system paths a sandboxed app cannot.
- **Goal**: commercial product — licensing (Paddle/LicenseSeat) and Sparkle auto-update are in scope, not deferred.

## Architecture

```
SwiftUI App (main target)
  Dashboard · Smart Care · Performance · Protection · Space Lens · Cloud Cleanup
        │ (protocol-based; UI never imports engine internals directly)
CleanCore (local Swift Package, zero UI deps, unit-testable)
  ScanItem/ScanResult/Severity models · Scanner & Cleaner protocols
  FileSystem (fts() wrapper) · Shell (Process wrapper w/ timeout) · ByteFormatter
        │
  ┌─────────┬──────────┬───────────┬──────────────┬───────────┐
  Junk/Cache  Duplicate  Perf        Malware        Cloud API   TreemapKit
  Scanner     Finder     Monitor     Scanner        Adapters    (squarify,
  (fts scan,  (size→     (host_stat, (hash+YARA,    (Drive/     pure geometry,
  trashItem)  hash dedup) IOKit,     optional        Dropbox/    no UI deps)
              + pHash)   sysctl)    Endpoint Sec.)  OneDrive)

Auxiliary processes (separate targets):
  Menu Bar Helper (NSStatusItem, CPU/RAM/Disk readout)
  Privileged Helper (SMAppService daemon, XPC, runs root-only ops)
```

**Why split like this**: CleanCore has zero UI dependency so it is unit-testable with XCTest/Swift Testing and reusable from a future CLI or the menu-bar helper. The privileged helper is a separate signed executable talking over XPC — this is Apple's sanctioned pattern for "some operations need root" instead of running the whole app elevated, and it keeps the attack surface small.

## Tech stack
- Swift 6 (strict concurrency), SwiftUI + AppKit interop (`NSHostingView`/`NSHostingController` for menu bar and custom window chrome).
- Deployment target: macOS 14 Sonoma minimum (covers realistic install base); adopt Liquid Glass / macOS 26 APIs behind `#available` gates, not as a hard requirement.
- Persistence: SwiftData for scan-history/whitelist/settings (lightweight, no server); Keychain for OAuth tokens and license key.
- `FileManager.trashItem(at:)` for every delete — never direct removal. This is non-negotiable per the research doc's safety findings.
- `SMAppService` (not the deprecated `SMJobBless`/`SMLoginItemSetEnabled`) for both the privileged helper daemon and login-item management.
- Sparkle 2 (SPM dependency) for auto-update; EdDSA-signed appcast.
- Licensing: integration point for Paddle or LicenseSeat — **not chosen yet**, see Phase 9 for the decision gate.

## Phases

| # | Phase | File | Risk |
|---|-------|------|------|
| 0 | Project & CleanCore foundation | [phase-00-foundation.md](phase-00-foundation.md) | Low |
| 1 | Essential Trio (Junk/Cache Scanner, Uninstaller, Updater) | [phase-01-essential-trio.md](phase-01-essential-trio.md) | Medium |
| 2 | Space Lens (treemap disk visualizer) | [phase-02-space-lens.md](phase-02-space-lens.md) | Medium |
| 3 | Duplicate Finder | [phase-03-duplicate-finder.md](phase-03-duplicate-finder.md) | Medium |
| 4 | Performance module + menu bar helper | [phase-04-performance.md](phase-04-performance.md) | High (low-level APIs) |
| 5 | Smart Care orchestration | [phase-05-smart-care.md](phase-05-smart-care.md) | Low (UX only) |
| 6 | Cloud Cleanup (Drive/Dropbox/OneDrive/iCloud) | [phase-06-cloud-cleanup.md](phase-06-cloud-cleanup.md) | High (3rd-party APIs) |
| 7 | Protection (malware scanner) | [phase-07-protection.md](phase-07-protection.md) | Very High |
| 8 | Privileged Helper Tool | [phase-08-privileged-helper.md](phase-08-privileged-helper.md) | High (security-sensitive) |
| 9 | Distribution & monetization (notarization, Sparkle, licensing) | [phase-09-distribution.md](phase-09-distribution.md) | Medium |

Phases 0-3 have no hard dependency on 4+ and can proceed in that order safely. Phase 8 (privileged helper) should land before Phase 4 needs root ops (purge/DNS flush) and before Phase 1 needs it for other-app cache removal outside the sandbox-free but still permission-gated paths — see Phase 8 for exact trigger points. Phase 9 runs in parallel starting at Phase 2 (get signing/notarization working early, don't leave it to the end).

## Dependencies between phases
- Phase 4 (Performance) and Phase 1 (Junk Scanner: system caches) both need Phase 8 (Privileged Helper) for root-level operations. Build Phase 8 with a minimal op-set first (trash-with-root, purge, dscacheutil flush), extend as later phases need more ops.
- Phase 5 (Smart Care) depends on Phases 1-4 all exposing a common `Scanner`/`Cleaner` protocol conformance — no new engine work, purely orchestration.
- Phase 7 (Protection) is independent code-wise but is the highest-risk phase for the *business*, not just engineering: real-time protection requires an Apple-granted Endpoint Security entitlement (external approval, not something this plan can guarantee). Build the static/signature-based scanner first; treat Endpoint Security as an optional stretch milestone gated on Apple's approval, not a committed deliverable.

## Acceptance criteria (per phase, detailed in each phase file)
- Each engine module: XCTest/Swift Testing coverage for its `Scanner`/`Cleaner` logic using a temp-directory fixture, no real user files touched in tests.
- Every delete path proven to route through `FileManager.trashItem(at:)` (test asserts file lands in `~/.Trash`, not gone).
- UI layer only calls CleanCore protocols — no `FileManager`/`Process`/`IOKit` calls directly inside SwiftUI views.
- App builds, launches, and passes a manual smoke test in the iOS/macOS destination before a phase is marked done.

## Open questions (unresolved — need a decision before the phase they block)
1. **Licensing vendor** (Paddle vs LicenseSeat vs Gumroad) — blocks Phase 9 implementation, not earlier phases.
2. **Endpoint Security entitlement request** — should be filed with Apple as early as possible (approval lead time is unpredictable) even though the code lands in Phase 7; consider filing during Phase 4-5.
3. **Cloud OAuth app registration** (Google Cloud Console app for Drive API, Dropbox App Console, Azure AD app for Graph/OneDrive) — needs to happen before Phase 6 coding starts since review/verification for these can take days-to-weeks for production quota.
4. ~~**App name / bundle identifier / Apple Developer Team**~~ — **Resolved 2026-07-25**: App name "SOS Mac", bundle id prefix `com.nextlabs` (placeholder — product bundle id `com.nextlabs.sosmac`). Apple Developer Team not yet chosen; Phase 0 scaffolds with automatic/local signing, real Team ID required before Phase 9 (notarization).

# Phase 7: Protection (Malware Scanner)

## Context
**Highest risk phase in the whole plan** — both technically and as an ongoing business commitment. The research doc is explicit: this is the module most likely to "look done but not be done" — a competitor cleaner app was documented failing the basic EICAR test. Do not treat this as a one-time coding task; it requires continuous threat-intel investment after launch.

## Scope decision baked into this plan
- **Committed deliverable**: static, signature-based scanner (hash + YARA rules) + optional VirusTotal/ClamAV-engine integration for broader coverage without building a threat-intel team from scratch.
- **Not committed / stretch**: real-time protection via Apple's Endpoint Security API. This requires an Apple-granted entitlement via a separate, unpredictable approval process. File the request early (see plan.md Open Question 2) but do not schedule real-time protection as a hard deliverable until Apple approves it.
- App must **never** claim to replace or disable XProtect/Gatekeeper — position as complementary, and say so explicitly in-product to avoid misleading users about their actual protection level.

## Requirements
- Static scanner: walk user-writable + common malware-drop locations (Downloads, LaunchAgents, Login Items, browser extension dirs) using the same `FTSWrapper` primitive as every other module.
- Hash-based detection: SHA-256 against a known-bad hash database (reuse Phase 3's `StreamingHasher` — same streaming-read discipline, don't load whole files).
- YARA rule matching: embed a YARA engine (e.g. via a Swift/C binding to `libyara`) for pattern-based detection beyond exact hashes.
- Signature database updates: fetched from your own server, versioned, signed to prevent tampering (a poisoned signature feed is a supply-chain attack vector — treat the update channel with the same rigor as Sparkle's appcast signing).
- Optional cloud lookup: VirusTotal API (hash lookup, respecting their rate limits and ToS) as a supplementary signal, not the sole detection mechanism (don't make the scanner non-functional offline).
- Quarantine flow: move detected files to a dedicated app-managed quarantine folder (still via `trashItem`-equivalent safety — reversible, not a hard delete) with a clear "restore" option, since false positives are a certainty at some point.
- Explicit EICAR test file detection as a baseline regression test — this is the industry-standard "does your AV even work" smoke test and the exact thing a competitor was called out for failing.

## Files to create
- `Packages/CleanCore/Sources/CleanCore/Protection/SignatureDatabase.swift`
- `Packages/CleanCore/Sources/CleanCore/Protection/HashScanner.swift`
- `Packages/CleanCore/Sources/CleanCore/Protection/YaraScanner.swift` (+ C binding target for `libyara`)
- `Packages/CleanCore/Sources/CleanCore/Protection/VirusTotalClient.swift`
- `Packages/CleanCore/Sources/CleanCore/Protection/QuarantineManager.swift`
- `Packages/CleanCore/Sources/CleanCore/Protection/SignatureUpdateChecker.swift`
- `App/Features/Protection/ProtectionView.swift` + `ProtectionViewModel.swift`

## Implementation steps
1. Stand up a minimal signature-feed server/endpoint (even a static signed JSON file on your own CDN to start) hosting known-bad hashes + YARA rules, versioned.
2. `SignatureUpdateChecker`: periodic fetch, signature verification (e.g. Ed25519 sign the feed, verify locally before trusting it) before ingesting any update.
3. `HashScanner`: stream-hash candidate files (reusing Phase 3's hasher), look up against the local signature DB.
4. `YaraScanner`: bind `libyara` (via a C target + Swift wrapper, similar shape to the `fts()` shim in Phase 0), compile the fetched YARA rules, scan file contents.
5. `VirusTotalClient`: hash-lookup-only integration (don't upload user files to a third party without explicit, separate consent — hash lookups are far less privacy-invasive than full uploads).
6. `QuarantineManager`: move flagged files to `~/Library/Application Support/<App>/Quarantine/`, keep a manifest (SwiftData) mapping quarantined path → original path for restore.
7. Add the EICAR test string as a fixture and assert detection — wire this into CI as a permanent regression gate, not a one-time manual check.
8. UI copy review: explicit language distinguishing this from XProtect/Gatekeeper, no "real-time protection" claims until Endpoint Security is actually wired and approved.

## Tests / validation
- **EICAR detection test is mandatory and must never regress** — this is the phase's primary acceptance criterion.
- `HashScannerTests`/`YaraScannerTests`: known-bad fixture hashes/patterns detected, known-good files not flagged (false-positive check matters as much as detection).
- `QuarantineManagerTests`: quarantine → restore round-trip returns the file to its exact original path.
- `SignatureUpdateCheckerTests`: reject an update whose signature doesn't verify (simulate a tampered feed).

## Risks / rollback
- This module can produce false positives that damage user trust (flagging a legitimate file) or false negatives that damage user safety (missing real malware) — both are real risks, not hypothetical, given the competitor precedent cited in the research doc.
- Ongoing cost: signature database needs continuous maintenance post-launch; this is a staffing/process commitment, not just a coding task — flag this clearly to the user/business owner, not just in code.
- Rollback: Protection is a fully separate module behind its own tab; can ship the app without it (defer to a later release) if the threat-intel investment isn't ready, without blocking any other module.

## Implementation note (2026-07-25)
- **libyara is a new build prerequisite.** Installed via `brew install yara` (pulls jansson/libmagic/protobuf-c as sub-dependencies) and linked from `Packages/CleanCore/Package.swift`'s `CYara` target via hardcoded Homebrew paths (`/opt/homebrew/opt/yara`, `/usr/local/opt/yara` for Intel). `YaraScanner` binds it through a real, working C shim (`Sources/CYara`) — all libyara struct complexity (`YR_COMPILER`/`YR_RULES`/`YR_RULE`/`YR_SCAN_CONTEXT`) is kept out of Swift entirely, mirroring how `CFTS` isolates `FTSENT`'s layout: Swift only ever holds opaque `void *` handles and a flat `char**`/`count` match-list struct. Anyone building this repo now needs `yara` installed via Homebrew first.
- **Linker warning, not an error**: the Homebrew `yara` bottle was built against a newer macOS SDK than this project's 14.0 deployment target (`ld: warning: ... linking with dylib ... built for newer version 26.0`). Not a functional problem for local development, but worth resolving before Phase 9 notarization/distribution — likely by vendoring/building libyara from source pinned to the 14.0 target rather than relying on the Homebrew bottle.
- **EICAR test file cannot be materialized on disk in this environment.** Empirically confirmed while building this phase: this machine's own real-time protection intercepts and silently deletes any file containing the literal EICAR string within moments of it hitting disk (a write via the sandboxed shell got `EPERM`; a write via a different code path succeeded but the file vanished immediately after). Since an on-disk EICAR fixture is therefore unreliable for automated tests (here and likely in any CI environment with default macOS/EDR protection active), the mandatory "detection actually works" regression gate is split into two independently-sufficient, non-flaky checks instead of fighting the OS: (1) `HashScannerTests.eicarHashShipsInBundledBaseline` asserts the real, computed SHA-256 of the canonical EICAR string ships in `SignatureDatabase.bundledBaseline`; (2) synthetic-surrogate-fixture tests prove the hash-match mechanism itself works end to end. The real EICAR hash was computed via `hashlib.sha256`/`shasum -a 256` directly, not transcribed from memory.
- **No real signature-feed server exists** (same disclosed-gap pattern as Phase 6's OAuth apps) — `SignatureUpdateChecker`'s Ed25519 verification logic is real and independently tested against a self-signed test keypair (`SignatureUpdateCheckerTests`), but there's no production `feedURL`/`publisherPublicKeyBase64` configured yet; it fails closed with `.notConfigured` until real values are supplied.
- **No real VirusTotal API key configured** — `VirusTotalClient` implements the real, documented API v3 hash-lookup endpoint and fails closed with `.notConfigured` without a key. Supplementary only, per the plan's own requirement: `ProtectionScanner` never depends on it, so Protection stays fully functional offline.
- **Real-time protection (Endpoint Security) was not attempted**, per the plan's own scope decision — it requires an Apple-granted entitlement outside the agent's control.
- **"Unsync"-equivalent scope note**: only "delete/quarantine" exists; there is no bulk "ignore this file forever" allowlist beyond removing it from the current findings list — not required by the plan, not built.

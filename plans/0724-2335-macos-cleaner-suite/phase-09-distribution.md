# Phase 9: Distribution & Monetization

## Context
Go-to-market infrastructure. Per the research doc's roadmap, start this in parallel from Phase 2 onward — don't leave signing/notarization to the end, since a build that's never been notarized tends to surface last-minute entitlement/signing surprises.

## Requirements
- Developer ID signing (application cert) + Hardened Runtime enabled from the very first internal build, not bolted on later.
- Notarization via `notarytool` (or Xcode Cloud/CI equivalent) as part of every release build — confirmed decision is non-App-Store distribution, so this is mandatory, not optional.
- Sparkle 2 integration: EdDSA-signed appcast, delta updates where feasible, respects Hardened Runtime + sandbox-free entitlements.
- Licensing integration point: app-side license-key validation + gating, vendor **not yet chosen** (Paddle vs LicenseSeat vs Gumroad — Open Question 1 in plan.md). Build the app-side interface (`LicenseValidator` protocol) now so swapping the vendor later doesn't touch UI/feature-gating code.
- Feature gating model: freemium scan (free) + paid clean/fix actions, matching the pricing model the research doc documents for this product category.

## Files to create
- `App/Services/LicenseValidator.swift` (protocol + a `TrialLicenseValidator` stub implementation for pre-vendor-decision development)
- `App/Services/FeatureGate.swift` (maps license state → which clean/fix actions are enabled vs free-scan-only)
- `Scripts/notarize-release.sh`
- `Scripts/generate-appcast.sh` (or Sparkle's own `generate_appcast` tool wired into CI)
- `.github/workflows/release.yml` (or equivalent CI config for this repo's actual CI provider — confirm which CI is in use before writing this)

## Implementation steps
1. Enroll in the Apple Developer Program, obtain Developer ID Application + Installer certs, configure Hardened Runtime entitlements (only request the specific entitlements each phase's code actually needs — e.g. no blanket "allow everything").
2. Set up a release build script: archive → export Developer ID signed `.app` → `notarytool submit` → staple ticket → verify with `spctl -a -vvv`.
3. Add Sparkle 2 via SPM, generate an EdDSA keypair (private key never committed to the repo — store in a secrets manager/CI secret), wire `SUUpdater`/`SPUStandardUpdaterController` into the app, host the signed appcast XML on your own site/CDN.
4. Define `LicenseValidator` protocol (`validate(key:) async throws -> LicenseState`) with a stub/mock implementation so Phases 0-8 can build and test without a real licensing vendor wired in yet.
5. Define `FeatureGate` consuming `LicenseState` to enable/disable clean actions in each module's ViewModel — scan/detect always free, clean/fix gated.
6. Once the licensing vendor decision lands (Open Question 1), implement the real `LicenseValidator` conformance, swap the app's dependency injection point — no other code should need to change.

## Tests / validation
- `notarytool` submission succeeds and `spctl -a -vvv` reports "accepted, source=Notarized Developer ID" on a clean test Mac (not the dev machine with dev certs already trusted).
- Sparkle: simulate an update by pointing a test build at a local appcast with a newer version, confirm the update prompt appears and installs correctly, confirm a tampered/unsigned appcast entry is rejected.
- `FeatureGateTests`: given various `LicenseState` values, assert the correct set of actions is enabled/disabled — this is pure logic, fully unit-testable without a real license server.
- Manual: full release dry-run (archive → notarize → staple → Sparkle-served update) on a clean VM before the first real release.

## Risks / rollback
- Notarization failures are often caused by other phases' code (e.g. an unsigned embedded binary, a missing entitlement for a new IOKit/XPC capability) — re-run notarization after every phase that adds a new system capability, don't wait until the end to discover a blocking issue.
- Licensing vendor lock-in risk: keeping `LicenseValidator` behind a protocol from day one (step 4) is the mitigation — don't let vendor-specific SDK types leak into `FeatureGate` or the UI layer.
- Rollback: distribution tooling is CI/build-process, not app runtime code — a broken release pipeline blocks shipping but doesn't affect a build already in users' hands.

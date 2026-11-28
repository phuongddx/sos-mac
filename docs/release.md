# Release pipeline (Developer ID, notarization, Sparkle, GitHub Releases)

SOS Mac ships outside the Mac App Store: Developer ID–signed, notarized and
stapled, distributed as a DMG plus a Sparkle update zip, with the appcast
attached to the GitHub Release. Two workflows drive it:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | every PR / push to `main` | build + tests (no signing, no secrets) via the repo's own merge gate |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | push of a tag `v*` | build, sign, notarize, staple, DMG, appcast, attest, publish the GitHub Release |

Both run on the `xcode-27` GitHub-hosted arm64 runner (Xcode 27, public
preview) — the project is arm64-only (`EXCLUDED_ARCHS` in `project.yml`), so
no self-hosted runner is needed.

## One script, two places

[`Scripts/release.sh`](../Scripts/release.sh) is the release pipeline itself,
shared by CI and the local fallback:

1. `xcodegen generate`, `xcodebuild archive` (ad-hoc signed; deterministic),
   then `-exportArchive` with
   [`Scripts/ExportOptions.plist`](../Scripts/ExportOptions.plist) —
   `method: developer-id`, hardened runtime, secure timestamp. No
   `codesign --deep` anywhere.
2. Re-signs the two embedded components that post-build scripts copy into the
   bundle — the menu-bar helper app and the privileged helper daemon — then
   the outer app (inside-out, each with `--options runtime --timestamp`).
3. Verifies **every** component: `codesign -dvv --verbose=4`,
   `codesign --verify --strict`, `spctl -a -vv` on the app, the menu-bar
   helper and the privileged helper, plus a sweep that `codesign --verify`s
   every Mach-O in the bundle and an `otool -L` check that nothing links
   Homebrew dylibs (libyara is statically linked), and a headless
   `--gate-smoke` launch of every shipped binary.
4. Notarizes (API key, `notarytool submit --wait`), staples the app, and only
   then builds the Sparkle zip (ditto, from the stapled app, so the ticket
   ships inside the update archive).
5. DMG (hdiutil, with an `/Applications` symlink): sign → notarize → staple.
6. Sparkle `generate_appcast` (pinned 2.10.1, downloaded per run) with the
   EdDSA key via stdin (`--ed-key-file -`). Previous releases' appcast and
   zips are downloaded first so the feed keeps old items and can produce
   deltas.

The script **never publishes**. Publishing (creating the GitHub Release and
uploading the DMG, zip and `appcast.xml`) is the workflow's last step, or a
manual `gh release create` for the local fallback.

## Versions

| Setting | Value | Why |
| --- | --- | --- |
| `MARKETING_VERSION` | the tag: `vX.Y.Z` → `X.Y.Z` | one place decides the user-facing version |
| `CURRENT_PROJECT_VERSION` | `git rev-list --count HEAD` | Sparkle compares `CFBundleVersion`, so it must rise monotonically; the commit count at the tagged commit is monotonic and deterministic for a given tag (this is why the release workflow checks out with `fetch-depth: 0`) |

`project.yml` still carries the committed defaults (`0.1.0` / `1`) for local
Debug builds; the release script overrides both on the `xcodebuild` command
line. The defaults are not bumped per release.

## Secrets in the GitHub Environment `release`

Create the environment once, then set the secrets:

```bash
gh api -X PUT repos/phuongddx/sos-mac/environments/release
gh secret set NAME --env release < file   # or: gh secret set NAME --env release --body "value"
```

| Secret | Value | Status (2026-11-27) |
| --- | --- | --- |
| `APPLE_API_KEY` | base64 of the notarization API key `AuthKey_3UU3K6VRFA.p8` | ✅ set |
| `APPLE_API_KEY_ID` | `3UU3K6VRFA` (Team key, profile `next-labs`) | ✅ set |
| `APPLE_API_ISSUER_ID` | issuer id — `asc auth issuer-id` | ✅ set |
| `MACOS_CERTIFICATE` | base64 of a `.p12` export of the "Developer ID Application: Doan Duy Phuong (K2TYLYAWMK)" identity | ⏳ needs Phương (keychain password) |
| `MACOS_CERTIFICATE_PWD` | the password chosen for that `.p12` export | ⏳ needs Phương |
| `SPARKLE_EDDSA_PRIVATE_KEY` | the Sparkle EdDSA private key (base64 seed) | ⏳ needs Phương (keychain prompt) |

The three "needs Phương" steps are exactly the ones that require a secret
only Phương can supply:

```bash
# 1) Export the Developer ID identity (prompts for the login keychain
#    password in the terminal, once) — then set both secrets:
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities -f pkcs12 -P "<choose-a-p12-password>" \
  -o /tmp/DeveloperIDApplication.p12 \
  633D175D73094D48FEBD9D99645EA71319C3C46E
base64 < /tmp/DeveloperIDApplication.p12 | gh secret set MACOS_CERTIFICATE --env release
gh secret set MACOS_CERTIFICATE_PWD --env release --body "<the p12 password>"

# 2) Sparkle EdDSA private key (keychain prompts once; click "Always Allow"):
security find-generic-password -s "https://sparkle-project.org" -w \
  | gh secret set SPARKLE_EDDSA_PRIVATE_KEY --env release
```

Never paste key material into issues, PRs or chat; the commands above pipe it
straight into `gh secret set`.

The app's `SUPublicEDKey` (`App/Info.plist`, generated from `project.yml`) is
the public half of that same Sparkle key; `SUFeedURL` points at
`https://github.com/phuongddx/sos-mac/releases/latest/download/appcast.xml`,
which always resolves to the newest release's cumulative appcast.

## Releasing

### From CI (the normal path)

1. Secrets above are all set (Environment `release`).
2. Merge the change to `main`.
3. Push a tag: `git tag v0.2.0 && git push origin v0.2.0`.
4. The workflow builds, signs, notarizes, staples, attests, creates the
   GitHub Release and uploads `SOSMac-<version>.dmg`,
   `SOSMac-<version>.zip` and `appcast.xml`. Nothing is pushed or published
   before the tag itself.

### Locally (fallback)

```bash
Scripts/release.sh --version 0.2.0            # appcast uses the keychain key (one prompt)
Scripts/release.sh --version 0.2.0 --skip-appcast   # everything except the appcast
```

Local run uses the login keychain's Developer ID identity, notarization key
from `~/Projects/next-labs/certs/asc.env` (`ASC_PRIVATE_KEY_PATH`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`), and the Sparkle key from the login keychain.
Artifacts land in `artifacts/release/` (git-ignored). Publishing is manual:

```bash
gh release create v0.2.0 --title 'SOS Mac 0.2.0' --generate-notes \
  artifacts/release/SOSMac-0.2.0.dmg \
  artifacts/release/SOSMac-0.2.0.zip \
  artifacts/release/appcast/appcast.xml
```

## Privileged helper re-registration

`SMAppService.h` requires a LaunchDaemon to be re-registered when its plist
or executable changes, so on every launch `PrivilegedHelperRegistration`
compares the bundled helper's fingerprint (SHA-256 over the helper executable
and its launchd plist) with the one stored at the last successful
registration. When it differs, it does `unregister` → (1 s pause) →
`register` with bounded retries — see the notes in
`App/Services/PrivilegedHelperRegistration.swift`. This logic is deliberately
independent of Sparkle: the app bundle can also be replaced by hand. The
Performance screen's manual register path records the fingerprint too, so a
manual register never triggers a spurious repair cycle on the next launch.

## Calendar

- The **Developer ID Application** certificate
  ("Developer ID Application: Doan Duy Phuong (K2TYLYAWMK)") expires
  **2027-02-01**. Before then: renew it, export a fresh `.p12`, and update
  the `MACOS_CERTIFICATE` / `MACOS_CERTIFICATE_PWD` secrets. Already-shipped
  builds keep working (timestamped signatures remain valid); only new
  signings need the new cert.
- The notarization API key (`AuthKey_3UU3K6VRFA.p8`) and the Sparkle EdDSA
  key have no fixed expiry; if either is ever rotated, the Sparkle EdDSA key
  can be rotated alongside one update (Sparkle supports changing one of
  signing key / Developer ID cert per update) — update
  `SPARKLE_EDDSA_PRIVATE_KEY`, the secret and `SUPublicEDKey` together.

#!/usr/bin/env bash
# Build, sign, notarize, staple and package a release of SOS Mac.
#
# One script for both places it runs:
#   * CI (.github/workflows/release.yml, GitHub Environment `release`):
#     certificate imported into a temporary keychain, notarization API key and
#     Sparkle EdDSA key from Environment secrets, tag v* provides the version.
#   * Local fallback: Developer ID identity from the login keychain,
#     notarization key from ../certs/asc.env, Sparkle key from the login
#     keychain ("Private key for signing Sparkle updates").
#
# It never publishes anything: creating the GitHub Release is a separate,
# explicit step (the workflow's last step, or a manual `gh release create`).
#
# Usage:
#   Scripts/release.sh [--version X.Y.Z] [--build N] [--skip-appcast]
#
# Versions:
#   MARKETING_VERSION  = the tag (vX.Y.Z -> X.Y.Z; CI passes it via
#                        GITHUB_REF_NAME, or --version, or falls back to
#                        project.yml's value for local test runs).
#   CURRENT_PROJECT_VERSION = git rev-list --count HEAD (or --build N).
#                        Sparkle compares CFBundleVersion, so it must rise
#                        monotonically; the commit count at the tagged commit
#                        does, and is deterministic for a given tag.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SOSMac"
VOLUME_NAME="SOS Mac"
IDENTITY="${SOSMAC_SIGNING_IDENTITY:-Developer ID Application: Doan Duy Phuong (K2TYLYAWMK)}"
REPO_SLUG="phuongddx/sos-mac"
SPARKLE_VERSION="2.10.1"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
HELPER_BINARY="com.nextlabs.sosmac.privilegedhelper"
WORK="artifacts/release"
LOG_DIR="$WORK/logs"

die() { echo "RELEASE FAILED: $*" >&2; exit 1; }
log() { echo; echo "==> $*"; }

step_seconds() { echo $(( $(date +%s) - ${1:?no start time} )); }

# ---------------------------------------------------------------------------
# Arguments and version resolution
# ---------------------------------------------------------------------------

VERSION=""
BUILD_NUMBER=""
SKIP_APPCAST="${SKIP_APPCAST:-0}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?}"; shift 2 ;;
        --build) BUILD_NUMBER="${2:?}"; shift 2 ;;
        --skip-appcast) SKIP_APPCAST=1; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

# CI tag push: GITHUB_REF_NAME is vX.Y.Z.
if [[ -z "$VERSION" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    VERSION="${GITHUB_REF_NAME#v}"
fi
# Local fallback: the committed default in project.yml (SOSMac target).
if [[ -z "$VERSION" ]]; then
    VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^""]+)"?.*/\1/')"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION must look like X.Y.Z (got '$VERSION')"
TAG="v$VERSION"

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
fi
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "CURRENT_PROJECT_VERSION must be an integer (got '$BUILD_NUMBER')"

APP="$WORK/export/$APP_NAME.app"
ZIP="$WORK/$APP_NAME-$VERSION.zip"
DMG="$WORK/$APP_NAME-$VERSION.dmg"

mkdir -p "$WORK" "$LOG_DIR"
rm -rf "$WORK/export" "$WORK/dmg-staging" "$WORK/appcast" "$WORK/DerivedData"

log "Release $TAG — MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD_NUMBER"

# ---------------------------------------------------------------------------
# 1. Archive + export (Developer ID, hardened runtime, secure timestamp)
# ---------------------------------------------------------------------------

log "1/7 xcodegen + xcodebuild archive"
ARCHIVE_T0=$(date +%s)
xcodegen generate >"$LOG_DIR/xcodegen.log"
# The archive is ad-hoc signed (deterministic, no identity ambiguity); the
# developer-id export below is what signs for distribution. EXCLUDED_ARCHS
# (arm64-only) comes from project.yml.
xcodebuild archive \
    -scheme SOSMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$WORK/$APP_NAME.xcarchive" \
    -derivedDataPath "$WORK/DerivedData" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY=- \
    | tee "$LOG_DIR/archive.log" | grep -E '^(/|\*\*|error:|warning: .*sign)' || true
log "   archive took $(step_seconds "$ARCHIVE_T0")s"

log "2/7 xcodebuild -exportArchive (method developer-id)"
EXPORT_T0=$(date +%s)
xcodebuild -exportArchive \
    -archivePath "$WORK/$APP_NAME.xcarchive" \
    -exportPath "$WORK/export" \
    -exportOptionsPlist Scripts/ExportOptions.plist \
    | tee "$LOG_DIR/export.log" | grep -E '^(/|\*\*|error:|warning: .*sign)' || true
[[ -d "$APP" ]] || die "export did not produce $APP"
log "   export took $(step_seconds "$EXPORT_T0")s"

# ---------------------------------------------------------------------------
# 3. Re-sign the custom embedded components, then the outer app.
#
# -exportArchive signs the app bundle, but two components land in the bundle
# through post-build scripts and need explicit Developer ID re-signing:
# the menu-bar helper (a nested .app under Library/LoginItems) and the
# privileged helper daemon (a bare Mach-O under Resources). The outer app is
# signed last so its resource seal covers the re-signed nested code.
# No `codesign --deep`: inside-out, one component at a time.
# ---------------------------------------------------------------------------

log "3/7 re-sign embedded helpers + app (Developer ID, hardened runtime, secure timestamp)"
HELPER_APP="$APP/Contents/Library/LoginItems/MenuBarHelper.app"
HELPER_BINARY_PATH="$APP/Contents/Resources/$HELPER_BINARY"
[[ -f "$HELPER_BINARY_PATH" ]] || die "missing $HELPER_BINARY_PATH"

# Every nested .app gets the Developer ID identity (the menu-bar helper is
# embedded twice — XcodeGen's dependency copy puts it in Resources as well as
# the post-build script's Library/LoginItems copy). Deepest first, then the
# bare helper binary, then the outer app so its seal covers everything.
NESTED_APP_COUNT=0
while IFS= read -r -d '' nested; do
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$nested" \
        2>&1 | tee "$LOG_DIR/codesign-$(basename "$nested" .app).log"
    NESTED_APP_COUNT=$((NESTED_APP_COUNT + 1))
done < <(find "$APP" -mindepth 1 -type d -name "*.app" -print0 | sort -rz)
echo "   re-signed $NESTED_APP_COUNT nested .app bundle(s)"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --identifier "$HELPER_BINARY" "$HELPER_BINARY_PATH" 2>&1 | tee "$LOG_DIR/codesign-privilegedhelper.log"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP" 2>&1 | tee "$LOG_DIR/codesign-app.log"

# ---------------------------------------------------------------------------
# 4. Verify every signed component (codesign -dvv / --verify --strict) and
#    sweep the whole bundle: every Mach-O must verify and none may be ad-hoc;
#    nothing may link Homebrew dylibs (libyara is statically linked).
#    spctl is checked in the final gate after notarization + stapling: before
#    the ticket exists it always answers "rejected / Unnotarized Developer ID".
# ---------------------------------------------------------------------------

log "4/7 verify signatures (app, menu-bar helper, privileged helper) + Mach-O sweep"
codesign_checks() {
    local path="$1" label="$2"
    echo "--- $label: codesign -dvv --verbose=4"
    codesign -dvv --verbose=4 "$path" 2>&1 | tee "$LOG_DIR/verify-dvv-$label.log"
    echo "--- $label: codesign --verify --strict"
    codesign --verify --strict --verbose=2 "$path" 2>&1 | tee "$LOG_DIR/verify-strict-$label.log"
}

codesign_checks "$APP" app
codesign_checks "$HELPER_APP" menubarhelper
codesign_checks "$APP/Contents/Resources/MenuBarHelper.app" menubarhelper-resources-copy
codesign_checks "$HELPER_BINARY_PATH" privilegedhelper

# libyara is statically linked (PR #25): the shipped binaries must not
# reference Homebrew paths, and every Mach-O in the bundle must verify.
SHIPPED_BINARIES=("$APP/Contents/MacOS/$APP_NAME" "$HELPER_APP/Contents/MacOS/MenuBarHelper" "$HELPER_BINARY_PATH")
for BIN in "${SHIPPED_BINARIES[@]}"; do
    if DYLIB_REFS="$(otool -L "$BIN" | grep -E '/opt/homebrew|/usr/local/(opt|Cellar)')"; then
        die "$(basename "$BIN") still links Homebrew libraries: $DYLIB_REFS"
    fi
done
MACHO_COUNT=0
while IFS= read -r -d '' file; do
    if file "$file" | grep -q "Mach-O"; then
        codesign --verify --strict "$file" || die "$(basename "$file") failed codesign --verify"
        if codesign -dvv "$file" 2>&1 | grep -q "Signature=adhoc"; then
            die "$(basename "$file") is still ad-hoc signed — notarization would reject it"
        fi
        MACHO_COUNT=$((MACHO_COUNT + 1))
    fi
done < <(find "$APP" -type f -perm -111 -print0)
echo "   $MACHO_COUNT Mach-O file(s) in the bundle pass codesign --verify --strict and none is ad-hoc signed"

# Smoke-launch every shipped executable headless (GateSmokeMode exits before
# any window or permission prompt; dyld must load every linked library).
for BIN in "${SHIPPED_BINARIES[@]}"; do
    "$BIN" --gate-smoke
    echo "   smoke: $(basename "$BIN") exited 0"
done

# ---------------------------------------------------------------------------
# 5. Notarize the app, staple it, then build the Sparkle zip from the
#    stapled app (the update archive must carry the ticket inside).
# ---------------------------------------------------------------------------

log "5/7 notarize + staple the app"
NOTARY_T0=$(date +%s)
if [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
    NOTARY_KEY_PATH="$WORK/notary-api-key.p8"
    printf '%s' "$APPLE_API_KEY" | base64 --decode -o "$NOTARY_KEY_PATH"
    NOTARY_KEY_ID="$APPLE_API_KEY_ID"
    NOTARY_ISSUER="$APPLE_API_ISSUER_ID"
else
    ASC_ENV="${SOSMAC_ASC_ENV:-$HOME/Projects/next-labs/certs/asc.env}"
    [[ -f "$ASC_ENV" ]] || die "no notarization credentials: set APPLE_API_KEY / APPLE_API_KEY_ID / APPLE_API_ISSUER_ID (CI) or provide $ASC_ENV (local)"
    set -a; # shellcheck disable=SC1090
    source "$ASC_ENV"; set +a
    NOTARY_KEY_PATH="${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH missing in $ASC_ENV}"
    NOTARY_KEY_ID="${ASC_KEY_ID:?ASC_KEY_ID missing in $ASC_ENV}"
    NOTARY_ISSUER="${ASC_ISSUER_ID:?ASC_ISSUER_ID missing in $ASC_ENV}"
fi
[[ -f "$NOTARY_KEY_PATH" ]] || die "notarization key not found at $NOTARY_KEY_PATH"

notarytool_submit() {
    local file="$1" logname="$2"
    echo "--- submitting $(basename "$file")"
    if ! xcrun notarytool submit "$file" \
            --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
            --wait 2>&1 | tee "$LOG_DIR/$logname"; then
        submission_id="$(grep -Eo 'id: [0-9a-fA-F-]+' "$LOG_DIR/$logname" | head -1 | cut -d' ' -f2 || true)"
        if [[ -n "$submission_id" ]]; then
            echo "--- fetching notarization log for $submission_id"
            xcrun notarytool log "$submission_id" \
                --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
                2>&1 | tee "$LOG_DIR/$logname.detail" || true
        fi
        die "notarization failed for $(basename "$file") — see $LOG_DIR/$logname"
    fi
}

# The submission zip (Apple's supported upload format); it is thrown away
# after stapling — the Sparkle zip below is rebuilt from the stapled app.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/submit.zip"
notarytool_submit "$WORK/submit.zip" "notary-app.log"
xcrun stapler staple "$APP" 2>&1 | tee "$LOG_DIR/stapler-app.log"
xcrun stapler validate "$APP" 2>&1 | tee "$LOG_DIR/stapler-validate-app.log"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
log "   notarization + staple took $(step_seconds "$NOTARY_T0")s"

# ---------------------------------------------------------------------------
# 6. DMG: build from the stapled app, sign, notarize, staple.
# ---------------------------------------------------------------------------

log "6/7 DMG: create, sign, notarize, staple"
DMG_T0=$(date +%s)
STAGING="$WORK/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -sfn /Applications "$STAGING/Applications"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" \
    | tee "$LOG_DIR/hdiutil.log"
hdiutil verify "$DMG" | tee "$LOG_DIR/hdiutil-verify.log"
codesign --sign "$IDENTITY" --timestamp "$DMG" 2>&1 | tee "$LOG_DIR/codesign-dmg.log"
notarytool_submit "$DMG" "notary-dmg.log"
xcrun stapler staple "$DMG" 2>&1 | tee "$LOG_DIR/stapler-dmg.log"
xcrun stapler validate "$DMG" 2>&1 | tee "$LOG_DIR/stapler-validate-dmg.log"
log "   DMG pipeline took $(step_seconds "$DMG_T0")s"

# ---------------------------------------------------------------------------
# Final gate: with notarization tickets stapled, spctl must now accept the
# app and every embedded component. (Before notarization spctl always answers
# "rejected / Unnotarized Developer ID" — that's why it runs here, not in
# step 4.)
# ---------------------------------------------------------------------------

log "6b/7 final gate: spctl must accept app, menu-bar helper, privileged helper"
spctl_gate() {
    local path="$1" label="$2"
    echo "--- $label: spctl -a -vv -t execute"
    local output
    output="$(spctl -a -vv -t execute "$path" 2>&1)" || true
    echo "$output" | tee "$LOG_DIR/final-spctl-$label.log"
    if grep -q "accepted" <<<"$output"; then
        return 0
    fi
    # The privileged helper is a bare Mach-O, not an app bundle, so Gatekeeper
    # assessment answers exactly this — "the code is valid but does not seem
    # to be an app" — while still confirming the Developer ID origin. That
    # outcome, plus `codesign --verify --strict` (step 4) and the notarization
    # ticket stapled into the app that embeds it, is the helper's pass
    # condition; anything else is a real rejection.
    if grep -q "the code is valid but does not seem to be an app" <<<"$output" \
        && grep -q "origin=Developer ID Application" <<<"$output"; then
        return 0
    fi
    die "spctl rejected $label — see $LOG_DIR/final-spctl-$label.log"
}
spctl_gate "$APP" app
spctl_gate "$HELPER_APP" menubarhelper
spctl_gate "$HELPER_BINARY_PATH" privilegedhelper

# ---------------------------------------------------------------------------
# 7. Sparkle appcast (generate_appcast, EdDSA key via stdin).
#    Previous releases' appcast + archives are downloaded so the feed keeps
#    the old items and can generate deltas. SKIP_APPCAST=1 skips the step
#    (e.g. before the Sparkle secret exists, or for a dry local run).
# ---------------------------------------------------------------------------

if [[ "$SKIP_APPCAST" == "1" ]]; then
    log "7/7 appcast skipped (SKIP_APPCAST=1)"
else
    log "7/7 Sparkle appcast (generate_appcast $SPARKLE_VERSION)"
    SPARKLE_BIN_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sos-mac/sparkle/$SPARKLE_VERSION"
    if [[ ! -x "$SPARKLE_BIN_DIR/generate_appcast" ]]; then
        mkdir -p "$WORK/sparkle-download" "$SPARKLE_BIN_DIR"
        curl -fsSL "$SPARKLE_URL" -o "$WORK/sparkle-download/sparkle.tar.xz"
        tar -xf "$WORK/sparkle-download/sparkle.tar.xz" -C "$WORK/sparkle-download"
        cp "$WORK/sparkle-download/bin/"* "$SPARKLE_BIN_DIR/"
    fi

    APPCAST_DIR="$WORK/appcast"
    mkdir -p "$APPCAST_DIR"
    PREV_TAG="$(gh release view --repo "$REPO_SLUG" --json tagName --jq .tagName 2>/dev/null || true)"
    if [[ -n "$PREV_TAG" && "$PREV_TAG" != "$TAG" ]]; then
        echo "--- downloading previous release assets ($PREV_TAG) to keep old items + deltas"
        gh release download "$PREV_TAG" --repo "$REPO_SLUG" --dir "$APPCAST_DIR" \
            --pattern 'appcast.xml' --pattern "$APP_NAME-*.zip" --clobber || true
    fi
    cp "$ZIP" "$APPCAST_DIR/"

    if [[ -n "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
        printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" \
            | "$SPARKLE_BIN_DIR/generate_appcast" "$APPCAST_DIR" --ed-key-file - \
              --download-url-prefix "https://github.com/$REPO_SLUG/releases/download/$TAG/" \
            | tee "$LOG_DIR/generate_appcast.log"
    else
        # Local fallback: the login-keychain key Sparkle's generate_keys
        # created ("Private key for signing Sparkle updates"). macOS shows
        # one keychain prompt the first time; "Always Allow" fixes it.
        security find-generic-password -s "https://sparkle-project.org" -w \
            | "$SPARKLE_BIN_DIR/generate_appcast" "$APPCAST_DIR" --ed-key-file - \
              --download-url-prefix "https://github.com/$REPO_SLUG/releases/download/$TAG/" \
            | tee "$LOG_DIR/generate_appcast.log"
    fi
    [[ -f "$APPCAST_DIR/appcast.xml" ]] || die "generate_appcast produced no appcast.xml"
fi

# ---------------------------------------------------------------------------
# Summary — everything a release needs, before the separate publish step.
# ---------------------------------------------------------------------------

log "Release artifacts ready in $WORK/"
ls -lh "$DMG" "$ZIP" 2>/dev/null || true
[[ "$SKIP_APPCAST" == "1" ]] || ls -lh "$WORK/appcast/" 2>/dev/null || true
echo
echo "Publish (not done by this script):"
echo "  gh release create $TAG --repo $REPO_SLUG --title 'SOS Mac $VERSION' --generate-notes \\"
echo "      '$DMG' '$ZIP' '$WORK/appcast/appcast.xml'"

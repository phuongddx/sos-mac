#!/usr/bin/env bash
# The merge gate for SOS Mac PRs. Every step must pass; Release is a hard step since
# 2026-11-27 (a #if DEBUG-only type used by the live code path slipped past a Debug-only
# gate — docs/superpowers/specs/2026-11-27-release-followups-a-f-design.md, point A).
#
# Usage: Scripts/verify-gate.sh [xcodebuild args…] (e.g. -destination …)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/6 xcodegen generate (project.yml is the source of truth) =="
xcodegen generate

echo "== 2/6 Debug build =="
xcodebuild build -scheme SOSMac -configuration Debug "$@"

echo "== 3/6 Release build (arm64-only per project.yml; catches #if DEBUG scope bugs) =="
xcodebuild build -scheme SOSMac -configuration Release "$@"

echo "== 4/6 Release smoke launch (dyld must load every linked library) =="
# Runs every shipped executable headless: `GateSmokeMode` makes each one exit at
# startup, after dyld has mapped every linked library — so a load-time failure
# (e.g. hardened-runtime library validation rejecting a Homebrew dylib, the
# 2026-11-27 crash that killed Release installs before any window appeared)
# aborts the process with a non-zero status and fails the gate. No window, Dock
# activation, or permission dialog is ever shown; unit tests cannot catch this
# class of bug because xcodebuild runs the test host under a debugger, which
# suspends library validation.
REL_PRODUCTS="$(xcodebuild -scheme SOSMac -configuration Release -showBuildSettings "$@" 2>/dev/null \
  | awk -F' = ' '$1 ~ /BUILT_PRODUCTS_DIR/ { gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 == "BUILT_PRODUCTS_DIR") { print $2; exit } }')"
APP="$REL_PRODUCTS/SOSMac.app"
if [[ ! -d "$APP" ]]; then
  echo "GATE FAILED: Release SOSMac.app not found (BUILT_PRODUCTS_DIR=$REL_PRODUCTS)" >&2
  exit 1
fi
SMOKE_BINARIES=(
  "$APP/Contents/MacOS/SOSMac"
  "$APP/Contents/Library/LoginItems/MenuBarHelper.app/Contents/MacOS/MenuBarHelper"
  "$APP/Contents/Resources/com.nextlabs.sosmac.privilegedhelper"
)
for BIN in "${SMOKE_BINARIES[@]}"; do
  if [[ ! -x "$BIN" ]]; then
    echo "GATE FAILED: expected shipped executable is missing: $BIN" >&2
    exit 1
  fi
  # No macOS `timeout(1)`: watchdog-kill after 20 s in case a binary ever hangs
  # instead of exiting.
  "$BIN" --gate-smoke &
  SMOKE_PID=$!
  ( sleep 20; kill -9 "$SMOKE_PID" 2>/dev/null ) &
  WATCHDOG=$!
  set +e
  wait "$SMOKE_PID"
  SMOKE_RC=$?
  set -e
  kill "$WATCHDOG" 2>/dev/null || true
  wait "$WATCHDOG" 2>/dev/null || true
  if [[ "$SMOKE_RC" -ne 0 ]]; then
    echo "GATE FAILED: $(basename "$BIN") --gate-smoke exited $SMOKE_RC — dyld could not load a linked library" >&2
    exit 1
  fi
  echo "  smoke: $(basename "$BIN") exited 0"
done
# Static audit with a precise message: no shipped binary may reference Homebrew
# dylibs (the smoke launch above already exercises the real dyld path).
for BIN in "${SMOKE_BINARIES[@]}"; do
  if DYLIB_REFS="$(otool -L "$BIN" | grep -E '/opt/homebrew|/usr/local/(opt|Cellar)')"; then
    echo "GATE FAILED: $(basename "$BIN") still links Homebrew libraries:" >&2
    echo "$DYLIB_REFS" >&2
    exit 1
  fi
done

echo "== 5/6 CleanCore Swift Testing suite =="
(cd Packages/CleanCore && swift test)

echo "== 6/6 App unit tests =="
xcodebuild test -scheme SOSMac -only-testing:SOSMacTests "$@"

echo "GATE PASSED: Debug + Release + smoke launch + CleanCore tests + SOSMacTests"

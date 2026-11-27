#!/usr/bin/env bash
# The merge gate for SOS Mac PRs. Every step must pass; Release is a hard step since
# 2026-11-27 (a #if DEBUG-only type used by the live code path slipped past a Debug-only
# gate — docs/superpowers/specs/2026-11-27-release-followups-a-f-design.md, point A).
#
# Usage: Scripts/verify-gate.sh [xcodebuild args…] (e.g. -destination …)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/5 xcodegen generate (project.yml is the source of truth) =="
xcodegen generate

echo "== 2/5 Debug build =="
xcodebuild build -scheme SOSMac -configuration Debug "$@"

echo "== 3/5 Release build (arm64-only per project.yml; catches #if DEBUG scope bugs) =="
xcodebuild build -scheme SOSMac -configuration Release "$@"

echo "== 4/5 CleanCore Swift Testing suite =="
(cd Packages/CleanCore && swift test)

echo "== 5/5 App unit tests =="
xcodebuild test -scheme SOSMac -only-testing:SOSMacTests "$@"

echo "GATE PASSED: Debug + Release + CleanCore tests + SOSMacTests"

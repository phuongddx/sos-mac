#!/usr/bin/env bash
# Captures the SOS Mac window for chosen screen states, in light and dark, without
# taking over the user's screen: the app is launched in the background (`open -g`),
# only its own window is captured (`screencapture -l`), and the instance is killed.
#
# Usage:
#   Scripts/ui-snapshots.sh -p <pr-name> -s <screen>=<state>[,<screen>=<state>…] [options]
#
# Options:
#   -p NAME   Output folder name under artifacts/ui-snapshots/ (required)
#   -s LIST   Comma-separated screen=state pairs, e.g. dashboard=default,junk=results
#             (default: the eight Junk & Cache reference states — the first migrated screen)
#   -a LIST   Appearances, default "dark,light"
#   -w WxH    Window size in points, default 1200x760
#   -1        Downscale PNGs to 1x (points) instead of the display's native pixels
#   -d DIR    Reuse this derived-data folder instead of a throwaway one (skips nothing: still builds)
#   -n        Skip the contact sheet
#   -e K=V    Extra SOSMAC_UITEST_ launch variable passed through on every open
#             (repeatable; e.g. -e SOSMAC_UITEST_VIEW=type — PR 8's By Type captures)
#   -h        Help
#
# Screen keys: dashboard smartcare junk duplicates spacelens cloud uninstaller updater performance protection
#
# Requires Screen Recording permission for the process that runs this script
# (Terminal, your editor, or the agent host). Without it the script stops with a
# clear message; it never tries to work around the prompt.
set -euo pipefail

BUNDLE_ID="com.nextlabs.sosmac"   # PRODUCT_BUNDLE_IDENTIFIER of target SOSMac in project.yml
EXECUTABLE="SOSMac"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="" SPECS="" APPEARANCES="dark,light" SIZE="1200x760" ONE_X=0 DERIVED="" CONTACT=1
EXTRA_ENV=()

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { echo "ui-snapshots: $*" >&2; exit 1; }

while getopts "p:s:a:w:1d:ne:h" opt; do
  case "$opt" in
    p) NAME="$OPTARG" ;;
    s) SPECS="$OPTARG" ;;
    a) APPEARANCES="$OPTARG" ;;
    w) SIZE="$OPTARG" ;;
    1) ONE_X=1 ;;
    d) DERIVED="$OPTARG" ;;
    n) CONTACT=0 ;;
    e) EXTRA_ENV+=("$OPTARG") ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
for pair in "${EXTRA_ENV[@]}"; do
  [[ "$pair" =~ ^SOSMAC_UITEST_[A-Z_]+=[A-Za-z0-9._-]+$ ]] || die "bad -e pair (want SOSMAC_UITEST_KEY=value): $pair"
done
[[ -n "$NAME" ]] || { usage >&2; exit 2; }
if [[ -z "$SPECS" ]]; then
  # PR 5's default matrix: the eight Junk & Cache lifecycle states (start/scanning/
  # results/review/cleaning/done/empty/error), the reference screen every later PR copies.
  SPECS="junk=start,junk=scanning,junk=results,junk=review,junk=cleaning,junk=done,junk=empty,junk=error"
fi
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "-p must be letters, digits, . _ -"
[[ "$SIZE" =~ ^[0-9]+x[0-9]+$ ]] || die "-w must look like 1200x760"
for spec in ${SPECS//,/ }; do
  [[ "$spec" =~ ^[a-z]+=[a-z]+$ ]] || die "bad screen=state pair: $spec"
done
for a in ${APPEARANCES//,/ }; do
  [[ "$a" == dark || "$a" == light ]] || die "appearance must be dark or light: $a"
done

OUT="$ROOT/artifacts/ui-snapshots/$NAME"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sosmac-snap.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"   # resolve /var -> /private/var so pgrep -f matches the real exec path
[[ -n "$DERIVED" ]] || DERIVED="$WORK/derived"
mkdir -p "$DERIVED"; DERIVED="$(cd "$DERIVED" && pwd -P)"
APP="$DERIVED/Build/Products/Debug/SOSMac.app"
EXEC_PATH="$APP/Contents/MacOS/$EXECUTABLE"
PID=""

stop_app() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    for _ in $(seq 1 50); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
    kill -9 "$PID" 2>/dev/null || true
  fi
  PID=""
}
cleanup() { stop_app; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

frontmost_bundle() {
  local asn; asn="$(lsappinfo front 2>/dev/null || true)"
  [[ -n "$asn" ]] || { echo ""; return; }
  lsappinfo info -only bundleid "$asn" 2>/dev/null | sed -n 's/.*bundleID="\(.*\)".*/\1/p'
}

# 1. Build Debug into the throwaway derived-data folder (never touches the user's DerivedData).
echo "==> Building Debug into $DERIVED"
( cd "$ROOT" && xcodebuild build -scheme SOSMac -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" -quiet ) > "$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log" >&2; die "build failed"; }
[[ -x "$EXEC_PATH" ]] || die "built app not found at $APP"
BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$BUILT_ID" == "$BUNDLE_ID" ]] || die "built bundle id is $BUILT_ID, expected $BUNDLE_ID"

# 2. Compile the window-id helper once (interpreting it on every call is slow).
swiftc -O "$ROOT/Scripts/window-id.swift" -o "$WORK/window-id" 2> "$WORK/swiftc.log" \
  || { cat "$WORK/swiftc.log" >&2; die "could not compile window-id.swift"; }

mkdir -p "$OUT"
FRONT_BEFORE="$(frontmost_bundle)"
echo "==> Frontmost app before capture: ${FRONT_BEFORE:-unknown}"

CAPTURED=()
for appearance in ${APPEARANCES//,/ }; do
  for spec in ${SPECS//,/ }; do
    screen="${spec%%=*}"; state="${spec#*=}"
    file="$OUT/$appearance-$screen-$state.png"
    echo "==> $appearance $screen=$state"

    # A leftover instance of THIS derived-data build would confuse pid lookup.
    if pgrep -f "$EXEC_PATH" > /dev/null; then die "another instance of $EXEC_PATH is already running"; fi

    open_args=(
      --env "SOSMAC_UITEST_SCREEN=$screen"
      --env "SOSMAC_UITEST_STATE=$state"
      --env "SOSMAC_UITEST_APPEARANCE=$appearance"
      --env "SOSMAC_UITEST_FIXTURES=1"
      --env "SOSMAC_UITEST_WINDOW_SIZE=$SIZE"
      --env "SOSMAC_UITEST_OUTPUT_DIR=$OUT"
    )
    for pair in "${EXTRA_ENV[@]}"; do
      open_args+=(--env "$pair")
    done
    open -n -g -a "$APP" "${open_args[@]}"

    # Our pid: the process whose executable is the throwaway build.
    for _ in $(seq 1 100); do PID="$(pgrep -f "$EXEC_PATH" | head -n1 || true)"; [[ -n "$PID" ]] && break; sleep 0.1; done
    [[ -n "$PID" ]] || die "app did not start"

    # Wait for its window, then let the layout settle.
    WINDOW=""
    for _ in $(seq 1 150); do
      WINDOW="$("$WORK/window-id" "$PID" "$BUNDLE_ID" 2>/dev/null || true)"; [[ -n "$WINDOW" ]] && break; sleep 0.1
    done
    [[ -n "$WINDOW" ]] || die "no window appeared for pid $PID"
    sleep 1.5
    WINDOW="$("$WORK/window-id" "$PID" "$BUNDLE_ID")"
    WID="${WINDOW%% *}"

    # If the app grabbed the foreground, stop: this route must not steal focus.
    FRONT_NOW="$(frontmost_bundle)"
    if [[ "$FRONT_NOW" == "$BUNDLE_ID" && "$FRONT_BEFORE" != "$BUNDLE_ID" ]]; then
      die "the app became the frontmost app; stopping so it does not interrupt the user"
    fi

    # -l: that window only, -o: no shadow, -x: no sound.
    if ! screencapture -l"$WID" -o -x "$file" 2> "$WORK/capture.log"; then
      cat "$WORK/capture.log" >&2
      die "screencapture failed. Grant Screen Recording to the app running this script (System Settings > Privacy & Security > Screen & System Audio Recording) and retry."
    fi
    stop_app
    [[ -s "$file" ]] || die "screencapture wrote no file: $file"

    [[ "$ONE_X" == 1 ]] && sips -z "${SIZE#*x}" "${SIZE%x*}" "$file" > /dev/null
    CAPTURED+=("$file")
  done
done

# 3. Report size and blank-image check for every capture.
STATUS=0
for file in "${CAPTURED[@]}"; do
  dims="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel(Width|Height)/{printf "%s%s", sep, $2; sep="x"}')"
  # A black or empty image has (almost) no variation between pixels.
  deviation="$(magick "$file" -colorspace Gray -format '%[fx:standard_deviation*1000]' info: 2>/dev/null || echo 0)"
  if awk "BEGIN{exit !($deviation < 5)}"; then
    echo "BLANK  $file ($dims, deviation $deviation)" >&2; STATUS=1
  else
    echo "OK     $file ($dims)"
  fi
done

# 4. Contact sheet.
if [[ "$CONTACT" == 1 && ${#CAPTURED[@]} -gt 0 ]]; then
  magick montage "${CAPTURED[@]}" -tile 2x -geometry 800x+8+8 -background '#222' \
    "$OUT/contact-sheet.png" 2>/dev/null && echo "Contact sheet: $OUT/contact-sheet.png"
fi

FRONT_AFTER="$(frontmost_bundle)"
echo "==> Frontmost app after capture: ${FRONT_AFTER:-unknown}"
[[ "$STATUS" == 0 ]] || die "one or more captures look blank (missing Screen Recording permission?)"

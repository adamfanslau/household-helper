#!/usr/bin/env bash
# Android build/run/drive helpers for the Claude loop (dev flavor on the Pixel_10_Pro AVD).
#   android.sh avd up|status          start the AVD if needed / print its state
#   android.sh build                  ./gradlew :app:installDevDebug (daemon kept warm); prints BUILD OK <s>
#   android.sh launch alice|bob|carol|none [deeplink]   force-stop + start (auto sign-in via HH_UITEST_USER)
#   android.sh shot <label>           screenshot to .dev/shots/<label>/screen.png
#   android.sh tree                   uiautomator dump: resource-id | text | content-desc | bounds
#   android.sh tap <tag | x y>        tap by testTag (resource-id) or point
#   android.sh key <KEYCODE> [n] | clear      send a keycode n times | empty the focused field (≤ 40 chars)
#   android.sh open <deeplink>                 VIEW intent to the running app (householdhelper://…)
#   android.sh wait <tag> [secs] | waittext "<text>" [secs]   poll the tree (default 8 s) — use before taps after animations
#   android.sh taptext "<text>"       tap the first node with that exact text (snackbar actions, dialog buttons)
#   android.sh longpress <tag>  | type "text" | swipe up|down|left|right [tag] | back
#   android.sh night on|off | fontscale 1.0|2.0
#   android.sh log [n]                last n lines of logcat tagged HH
#   android.sh unit | uitest          testDevDebugUnitTest | connectedDevDebugAndroidTest
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
A="$REPO_ROOT/apps/android"
ACT="$PKG_DEV/com.householdhelper.app.MainActivity"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 1; }
cmd="${1:-}"; shift || true

adbs() { adb -s "$ADB_SERIAL" "$@"; }
# Device loopback → host: the dev flavor talks to 127.0.0.1:9099 (Auth emulator) and :8091 (API).
reverse_ports() { adbs reverse tcp:9099 tcp:9099 >/dev/null 2>&1; adbs reverse tcp:8091 tcp:8091 >/dev/null 2>&1; }
dump() { adbs exec-out uiautomator dump /dev/tty 2>/dev/null | sed 's/UI hierchary dumped to: \/dev\/tty//'; }
center() { dump | python3 "$REPO_ROOT/scripts/dev/uia.py" center "$1"; }

case "$cmd" in
  avd)
    case "${1:-}" in
      up)
        if adb devices | grep -q "^$ADB_SERIAL"; then echo "avd $AVD already running ($ADB_SERIAL)"; exit 0; fi
        (nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -no-boot-anim > "$LOG_DIR/emulator.log" 2>&1 &)
        adb wait-for-device; for _ in $(seq 1 120); do [ "$(adbs shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 1; done
        reverse_ports; echo "avd $AVD booted ($ADB_SERIAL), ports reversed" ;;
      status) adb devices | grep -q "^$ADB_SERIAL" && { reverse_ports; echo "up $ADB_SERIAL (api $(adbs shell getprop ro.build.version.sdk | tr -d '\r'), ports reversed)"; } || echo "down" ;;
      *) usage ;;
    esac ;;
  build)
    start=$SECONDS; rc=0
    (cd "$A" && ./gradlew :app:installDevDebug -q > "$LOG_DIR/gradle.log" 2>&1) || rc=$?
    { grep -E "^e: |error:|FAILED|What went wrong" -A3 "$LOG_DIR/gradle.log" | head -30; } || true
    if [ $rc -eq 0 ]; then echo "BUILD OK $((SECONDS-start))s"; else echo "BUILD FAILED (rc=$rc, $((SECONDS-start))s) — see $LOG_DIR/gradle.log"; fi
    exit $rc ;;
  launch)
    [ $# -ge 1 ] || usage; who="$1"; link="${2:-}"
    reverse_ports
    adbs shell am force-stop "$PKG_DEV" >/dev/null 2>&1 || true
    adbs logcat -c >/dev/null 2>&1 || true
    if [ "$who" = none ]; then adbs shell am start -n "$ACT" >/dev/null
    else adbs shell am start -n "$ACT" --es HH_UITEST_USER "$who" >/dev/null; fi
    sleep 2
    [ -n "$link" ] && adbs shell am start -a android.intent.action.VIEW -d "$link" "$PKG_DEV" >/dev/null
    echo "launched $PKG_DEV as=$who${link:+ link=$link}" ;;
  shot) [ $# -eq 1 ] || usage; mkdir -p "$SHOT_DIR/$1"; adbs exec-out screencap -p > "$SHOT_DIR/$1/screen.png" && echo "$SHOT_DIR/$1/screen.png" ;;
  tree) dump | python3 "$REPO_ROOT/scripts/dev/uia.py" tree ;;
  tap)
    [ $# -ge 1 ] || usage
    if [ $# -eq 2 ]; then adbs shell input tap "$1" "$2" && echo "tapped $1,$2"
    else pt=$(center "$1"); [ -n "$pt" ] || die "no node with resource-id $1"; adbs shell input tap $pt && echo "tapped $1 ($pt)"; fi ;;
  key) [ $# -ge 1 ] || usage; n="${2:-1}"; for _ in $(seq 1 "$n"); do adbs shell input keyevent "$1"; done; echo "key $1 x$n" ;;
  clear) sleep 0.4; adbs shell input keyevent KEYCODE_MOVE_END && adbs shell input keyevent $(printf 'KEYCODE_DEL %.0s' $(seq 1 40)) && echo "cleared field" ;;
  open) [ $# -eq 1 ] || usage; adbs shell am start -a android.intent.action.VIEW -d "$1" "$PKG_DEV" >/dev/null && echo "opened $1" ;;
  wait|waittext)
    [ $# -ge 1 ] || usage; key=$([ "$cmd" = wait ] && echo center || echo center-text); secs="${2:-8}"; t0=$SECONDS
    while :; do pt=$(dump | python3 "$REPO_ROOT/scripts/dev/uia.py" "$key" "$1"); [ -n "$pt" ] && { echo "found $1 after $((SECONDS-t0))s"; break; }
      [ $((SECONDS-t0)) -lt "$secs" ] || die "timeout waiting for $1"; sleep 0.5; done ;;
  taptext) [ $# -eq 1 ] || usage; pt=$(dump | python3 "$REPO_ROOT/scripts/dev/uia.py" center-text "$1"); [ -n "$pt" ] || die "no node with text $1"; adbs shell input tap $pt && echo "tapped text $1 ($pt)" ;;
  longpress) [ $# -eq 1 ] || usage; pt=$(center "$1"); [ -n "$pt" ] || die "no node with resource-id $1"; set -- $pt; adbs shell input swipe "$1" "$2" "$1" "$2" 900 && echo "long-pressed ($1,$2)" ;;
  type) [ $# -eq 1 ] || usage; adbs shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" && echo "typed" ;;
  swipe)
    [ $# -ge 1 ] || usage; dir="$1"; tag="${2:-}"
    if [ -n "$tag" ]; then pt=$(center "$tag"); [ -n "$pt" ] || die "no node $tag"; set -- $pt; cx=$1; cy=$2; else cx=540; cy=1200; fi
    case "$dir" in
      up) adbs shell input swipe "$cx" $((cy+400)) "$cx" $((cy-400)) 300 ;;
      down) adbs shell input swipe "$cx" $((cy-400)) "$cx" $((cy+400)) 300 ;;
      left) adbs shell input swipe $((cx+300)) "$cy" $((cx-500)) "$cy" 600 ;;
      right) adbs shell input swipe $((cx-300)) "$cy" $((cx+500)) "$cy" 600 ;;
      *) usage ;;
    esac && echo "swiped $dir${tag:+ on $tag}" ;;
  back) adbs shell input keyevent KEYCODE_BACK && echo back ;;
  night) [ $# -eq 1 ] || usage; adbs shell cmd uimode night "$1" >/dev/null && echo "night $1" ;;
  fontscale) [ $# -eq 1 ] || usage; adbs shell settings put system font_scale "$1" && echo "font_scale $1" ;;
  log) adbs logcat -d -s HH:* 2>/dev/null | tail -n "${1:-40}" | cut -c1-220 ;;
  unit)
    start=$SECONDS; rc=0; (cd "$A" && ./gradlew :app:testDevDebugUnitTest -q > "$LOG_DIR/gradle-test.log" 2>&1) || rc=$?
    { grep -E "tests completed|FAILED|failed|^e: " "$LOG_DIR/gradle-test.log" | head -10; } || true
    [ $rc -eq 0 ] && echo "UNIT OK $((SECONDS-start))s" || echo "UNIT FAILED (rc=$rc) — see $LOG_DIR/gradle-test.log"; exit $rc ;;
  uitest)
    start=$SECONDS; rc=0; (cd "$A" && ./gradlew :app:connectedDevDebugAndroidTest -q > "$LOG_DIR/gradle-uitest.log" 2>&1) || rc=$?
    { grep -E "Tests on|FAILED|failed|passed" "$LOG_DIR/gradle-uitest.log" | head -10; } || true
    [ $rc -eq 0 ] && echo "UITEST OK $((SECONDS-start))s" || echo "UITEST FAILED (rc=$rc) — see $LOG_DIR/gradle-uitest.log"; exit $rc ;;
  *) usage ;;
esac

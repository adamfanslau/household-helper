#!/usr/bin/env bash
# iOS build/run/drive helpers for the Claude loop. Every command prints one compact result.
#   ios.sh gen                           regenerate HouseholdHelper.xcodeproj from project.yml (xcodegen)
#   ios.sh build [Debug|DebugFirebase]   incremental build into .dev/DerivedData (prints BUILD OK <s>)
#   ios.sh install <udid>                install the last Debug build
#   ios.sh launch <udid> alice|bob|none [deeplink]   terminate + launch (auto sign-in via HH_UITEST_USER)
#   ios.sh shot <udid> <label>           screenshot to .dev/shots/<label>/screen.png
#   ios.sh tree <udid>                   accessibility tree: id | label | type | x,y,w,h
#   ios.sh tap <udid> <id | x y>         tap by accessibilityIdentifier or point
#   ios.sh label <udid> "<label>"        tap by accessibility label
#   ios.sh longpress <udid> <id>
#   ios.sh type <udid> "text"
#   ios.sh swipe <udid> up|down|left|right [id]
#   ios.sh home <udid> | appearance <udid> light|dark | textsize <udid> default|ax5
#   ios.sh log <udid> [n]                last n lines of the app's os_log (captured since launch)
#   ios.sh unit | uitest <Class[/test]>  xcodebuild test
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PROJ="$REPO_ROOT/apps/ios/HouseholdHelper.xcodeproj"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/HouseholdHelper.app"
usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 1; }
cmd="${1:-}"; shift || true

xcb() { # xcb <extra xcodebuild args...>
  local start=$SECONDS
  local rc=0
  xcodebuild -project "$PROJ" -derivedDataPath "$DERIVED_DATA" -quiet "$@" > "$LOG_DIR/xcodebuild.log" 2>&1 || rc=$?
  { grep -E "error:|warning: .*(unreachable|never used|deprecated)" "$LOG_DIR/xcodebuild.log" | grep -v "^ld: warning" | sort -u | head -20; } || true
  if [ $rc -eq 0 ]; then echo "BUILD OK $((SECONDS-start))s"; else echo "BUILD FAILED (rc=$rc, $((SECONDS-start))s) — see $LOG_DIR/xcodebuild.log"; fi
  return $rc
}

case "$cmd" in
  gen) need xcodegen "brew install xcodegen"; (cd "$REPO_ROOT/apps/ios" && xcodegen generate --quiet) && echo "generated $PROJ" ;;
  build)
    cfg="${1:-Debug}"; udid="${2:-$UDID_IPHONE17}"
    xcb -scheme HouseholdHelper -configuration "$cfg" -destination "id=$udid" build ;;
  install)
    [ $# -eq 1 ] || usage; [ -d "$APP" ] || die "no build at $APP (ios.sh build)"
    xcrun simctl install "$1" "$APP" && echo "installed $(basename "$APP") on $1" ;;
  launch)
    [ $# -ge 2 ] || usage; udid="$1"; who="$2"; link="${3:-}"
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    pkill -f "simctl spawn $udid log stream" 2>/dev/null || true
    pkill -f "log stream --style compact.*$BUNDLE" 2>/dev/null || true
    (xcrun simctl spawn "$udid" log stream --style compact --level debug --predicate "subsystem == \"$BUNDLE\"" > "$LOG_DIR/ios-app.log" 2>&1 &)
    if [ "$who" = "none" ]; then pid=$(xcrun simctl launch "$udid" "$BUNDLE" | awk '{print $NF}')
    else pid=$(SIMCTL_CHILD_HH_UITEST_USER="$who" xcrun simctl launch "$udid" "$BUNDLE" | awk '{print $NF}'); fi
    sleep 2
    [ -n "$link" ] && xcrun simctl openurl "$udid" "$link"
    echo "launched $BUNDLE pid=$pid as=$who${link:+ link=$link}" ;;
  shot)
    [ $# -eq 2 ] || usage; mkdir -p "$SHOT_DIR/$2"; xcrun simctl io "$1" screenshot "$SHOT_DIR/$2/screen.png" >/dev/null 2>&1 && echo "$SHOT_DIR/$2/screen.png" ;;
  tree)
    [ $# -eq 1 ] || usage; need axe "brew install cameroncooke/axe/axe"
    axe describe-ui --udid "$1" | jq -r '
      def walk(n): (n | select(.AXUniqueId != null or .AXLabel != null) | "\(.AXUniqueId // "-") | \(.AXLabel // "-") | \(.type // "-") | \(.frame.x|floor),\(.frame.y|floor),\(.frame.width|floor),\(.frame.height|floor)"), (n.children[]? | walk(.));
      .[] | walk(.)' ;;
  tap)
    [ $# -ge 2 ] || usage; udid="$1"; shift
    if [ $# -eq 2 ]; then axe tap -x "$1" -y "$2" --udid "$udid" >/dev/null && echo "tapped $1,$2"
    else axe tap --id "$1" --udid "$udid" >/dev/null && echo "tapped $1"; fi ;;
  label) [ $# -eq 2 ] || usage; axe tap --label "$2" --udid "$1" >/dev/null && echo "tapped label $2" ;;
  longpress) [ $# -eq 2 ] || usage; axe touch --id "$2" --down --udid "$1" >/dev/null 2>&1; sleep 0.8; axe touch --id "$2" --up --udid "$1" >/dev/null 2>&1 && echo "long-pressed $2" ;;
  type) [ $# -eq 2 ] || usage; axe type "$2" --udid "$1" >/dev/null && echo "typed" ;;
  swipe)
    [ $# -ge 2 ] || usage; udid="$1"; dir="$2"; id="${3:-}"
    if [ -n "$id" ]; then
      read -r x y w h < <(axe describe-ui --udid "$udid" | jq -r --arg id "$id" 'def walk(n): n, (n.children[]? | walk(.)); [.[] | walk(.)] | map(select(.AXUniqueId == $id)) | .[0].frame | "\(.x) \(.y) \(.width) \(.height)"')
      cx=$(printf '%.0f' "$(echo "$x + $w/2" | bc -l)"); cy=$(printf '%.0f' "$(echo "$y + $h/2" | bc -l)")
    else cx=200; cy=400; fi
    case "$dir" in
      up) axe swipe --start-x "$cx" --start-y $((cy+150)) --end-x "$cx" --end-y $((cy-150)) --udid "$udid" ;;
      down) axe swipe --start-x "$cx" --start-y $((cy-150)) --end-x "$cx" --end-y $((cy+150)) --udid "$udid" ;;
      left) axe swipe --start-x $((cx+120)) --start-y "$cy" --end-x $((cx-160)) --end-y "$cy" --udid "$udid" ;;
      right) axe swipe --start-x $((cx-120)) --start-y "$cy" --end-x $((cx+160)) --end-y "$cy" --udid "$udid" ;;
      *) usage ;;
    esac >/dev/null && echo "swiped $dir${id:+ on $id}" ;;
  home) [ $# -eq 1 ] || usage; axe button home --udid "$1" >/dev/null && echo "home" ;;
  appearance) [ $# -eq 2 ] || usage; xcrun simctl ui "$1" appearance "$2" && echo "appearance $2" ;;
  textsize)
    [ $# -eq 2 ] || usage
    case "$2" in default) xcrun simctl ui "$1" content_size medium ;; ax5) xcrun simctl ui "$1" content_size accessibility-extra-extra-extra-large ;; *) usage ;; esac && echo "textsize $2" ;;
  log) [ $# -ge 1 ] || usage; tail -n "${2:-40}" "$LOG_DIR/ios-app.log" 2>/dev/null | cut -c1-220 ;;
  unit) xcb -scheme HouseholdHelper -destination "id=$UDID_IPHONE17" -only-testing:HouseholdHelperTests test ;;
  uitest) [ $# -eq 1 ] || usage; xcb -scheme HouseholdHelper -destination "id=$UDID_IPHONE17" -only-testing:"HouseholdHelperUITests/$1" test ;;
  *) usage ;;
esac

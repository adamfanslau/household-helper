#!/usr/bin/env bash
# Snapshot a device into .dev/shots/<label>/{screen.png,tree.txt,log.txt}; prunes to the 20 newest labels.
#   snap.sh ios <udid> <label> | snap.sh android <label>
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="$REPO_ROOT/scripts/dev"
case "${1:-}" in
  ios) [ $# -eq 3 ] || die "usage: snap.sh ios <udid> <label>"; udid="$2"; label="$3"; dir="$SHOT_DIR/$label"; mkdir -p "$dir"
       "$S/ios.sh" shot "$udid" "$label" >/dev/null; "$S/ios.sh" tree "$udid" > "$dir/tree.txt"; "$S/ios.sh" log "$udid" 50 > "$dir/log.txt" ;;
  android) [ $# -eq 2 ] || die "usage: snap.sh android <label>"; label="$2"; dir="$SHOT_DIR/$label"; mkdir -p "$dir"
       "$S/android.sh" shot "$label" >/dev/null; "$S/android.sh" tree > "$dir/tree.txt"; "$S/android.sh" log 50 > "$dir/log.txt" ;;
  *) die "usage: snap.sh ios <udid> <label> | snap.sh android <label>" ;;
esac
ls -1t "$SHOT_DIR" | tail -n +21 | while read -r old; do rm -rf "${SHOT_DIR:?}/${old:?}"; done
echo "$dir: screen.png tree.txt log.txt ids=$(grep -c . "$dir/tree.txt")"

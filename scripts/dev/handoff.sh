#!/usr/bin/env bash
# Prepare a human checkpoint: fresh seed, device status, and the hand-off message skeleton.
#   handoff.sh <n> "<title>"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ $# -ge 2 ] || { echo "usage: handoff.sh <n> \"<title>\"" >&2; exit 1; }
n="$1"; title="$2"; S="$REPO_ROOT/scripts/dev"
"$S/stack.sh" reset | tail -1
ios_state="$("$S/sim.sh" state "$UDID_IPHONE17" 2>/dev/null || echo unknown)"
android_state="$("$S/android.sh" avd status 2>/dev/null | head -1 || echo down)"
shots="$(ls -t "$SHOT_DIR" 2>/dev/null | head -8 | sed "s|^|  .dev/shots/|" || true)"
cat <<MSG
## Checkpoint $n: $title
Stack: running (api :8091, auth :9099, emulator UI :4000); seed reset at $(date '+%H:%M'); alice@dev.local / bob@dev.local, password "password".
iOS: open apps/ios/HouseholdHelper.xcodeproj → scheme "HouseholdHelper" → iPhone 17 (iOS 26.3) → Play → "Sign in as Alice".   [simulator: $ios_state]
Android: Android Studio → run config app (dev) → Pixel_10_Pro → Play → "Sign in as Bob".   [$android_state]
Check:
1. <what to look at / do>   — evidence: <shot path>
Claude verified: <one line per automated assertion that passed>
Known gaps: <list or "none">
Recent snapshots:
$shots
MSG

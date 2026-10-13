#!/usr/bin/env bash
# iOS simulator helpers. Prints UDIDs, never relies on `booted`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
usage() { die 'usage: sim.sh list | resolve "<name>" [<runtime>] | boot <udid> | shutdown <udid> | state <udid>'; }
cmd="${1:-}"; shift || true
case "$cmd" in
  list)
    xcrun simctl list -j devices available \
      | jq -r --arg rt "iOS-${IOS_RUNTIME//./-}" \
          '.devices | to_entries[] | select(.key | endswith($rt)) | .value[] | "\(.state)\t\(.udid)\t\(.name)"' \
      | sort -k3 ;;
  resolve)
    [ $# -ge 1 ] || usage
    udid="$(sim_resolve "$1" "${2:-}")"
    [ -n "$udid" ] || die "no available simulator named '$1' on iOS ${2:-$IOS_RUNTIME}"
    printf '%s\n' "$udid" ;;
  boot)
    [ $# -eq 1 ] || usage
    xcrun simctl boot "$1" 2>/dev/null || true          # already booted is fine
    xcrun simctl bootstatus "$1" -b >/dev/null
    open -a Simulator --args -CurrentDeviceUDID "$1" >/dev/null 2>&1 || true
    echo "booted $1" ;;
  shutdown)
    [ $# -eq 1 ] || usage
    xcrun simctl shutdown "$1" >/dev/null
    echo "shutdown $1" ;;
  state)
    [ $# -eq 1 ] || usage
    xcrun simctl list -j devices | jq -r --arg u "$1" '.devices[][] | select(.udid == $u) | .state' ;;
  *) usage ;;
esac

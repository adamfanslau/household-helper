#!/usr/bin/env bash
# Shared helpers for scripts/dev/*. Source it; don't execute it.
# Every script here does one whole step and prints one compact result so the
# Claude inner loop stays cheap (see household-helper-plan.md, "Claude development
# & verification flow").
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_DIR="$REPO_ROOT/.dev"              # gitignored scratch: logs, pids, shots, DerivedData
LOG_DIR="$DEV_DIR/logs"
PID_DIR="$DEV_DIR/pids"
SHOT_DIR="$DEV_DIR/shots"
DERIVED_DATA="$DEV_DIR/DerivedData"
mkdir -p "$LOG_DIR" "$PID_DIR" "$SHOT_DIR" "$DERIVED_DATA"

# Fixed devices (verified 2026-10-13). Never pass `booted` to simctl: two sims may be
# up at once and "iPhone 16e" exists on two runtimes. Re-resolve with sim.sh if these change.
UDID_IPHONE17="89850DF1-19BE-4DAF-92D5-B6411AF061A4"
UDID_IPHONE16E_26="D1A7B231-8689-40A0-8536-126AC063188E"
IOS_RUNTIME="26.3"
AVD="Pixel_10_Pro"
ADB_SERIAL="${ADB_SERIAL:-emulator-5554}"

BUNDLE="com.householdhelper.app"
PKG_DEV="com.householdhelper.app.dev"
API_URL="http://127.0.0.1:8091"
AUTH_EMULATOR="127.0.0.1:9099"
FIREBASE_PROJECT="demo-household-helper"

log()  { printf '%s\n' "$*" >&2; }
die()  { log "error: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || die "missing tool: $1${2:+ ($2)}"; }

# sim_resolve "<name>" [<runtime>] → UDID of the available simulator with that exact
# name on that iOS runtime (default $IOS_RUNTIME). Empty output = not found.
sim_resolve() {
  local name="$1" rt="${2:-$IOS_RUNTIME}"
  xcrun simctl list -j devices available \
    | jq -r --arg n "$name" --arg rt "iOS-${rt//./-}" \
        '.devices | to_entries[] | select(.key | endswith($rt)) | .value[] | select(.name == $n) | .udid' \
    | head -1
}

# stack_up_api / stack_up_auth → 0 when the local API / Auth emulator answers.
stack_up_api()  { curl -fsS -m 2 "$API_URL/healthz" >/dev/null 2>&1; }
stack_up_auth() { curl -fsS -m 2 "http://$AUTH_EMULATOR/" >/dev/null 2>&1; }

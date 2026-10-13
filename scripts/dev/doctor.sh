#!/usr/bin/env bash
# One-screen, read-only health check of the toolchain, devices and local stack.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

ver() { # ver <label> <binary> [args...]  → first line of output, or MISSING
  local label="$1" bin="$2"; shift 2
  if have "$bin"; then printf '  %-12s %s\n' "$label" "$("$bin" "$@" 2>&1 | head -1)"
  else printf '  %-12s MISSING\n' "$label"; fi
}

echo "household-helper doctor — $(date '+%Y-%m-%d %H:%M')  ($REPO_ROOT)"
echo "Tools"
ver xcodebuild xcodebuild -version
ver axe axe --version
ver adb adb version
ver emulator emulator -version
ver java java -version
ver go go version
ver node node --version
if [ -x "$REPO_ROOT/node_modules/.bin/firebase" ]; then
  printf '  %-12s %s\n' firebase "$("$REPO_ROOT/node_modules/.bin/firebase" --version 2>/dev/null)"
else printf '  %-12s MISSING (run: npm install at the repo root)\n' firebase; fi
ver jq jq --version
ver gh gh --version
printf '  %-12s %s\n' ANDROID_HOME "${ANDROID_HOME:-unset}"
ls -d "${ANDROID_HOME:-/nonexistent}"/cmdline-tools/*/bin >/dev/null 2>&1 \
  && printf '  %-12s %s\n' cmdline-tools "$(ls -d "$ANDROID_HOME"/cmdline-tools/*/bin | head -1) (not on PATH)"

echo "iOS simulators (iOS $IOS_RUNTIME)"
"$REPO_ROOT/scripts/dev/sim.sh" list 2>/dev/null | awk -F'\t' '{ printf "  %-9s %s  %s\n", $1, $2, $3 }'

echo "Android"
if have emulator; then emulator -list-avds 2>/dev/null | sed 's/^/  avd: /'; fi
if have adb; then adb devices 2>/dev/null | tail -n +2 | awk 'NF { printf "  adb: %s %s\n", $1, $2 }'; fi

echo "Disk"
df -h / | awk 'NR==2 { printf "  %s free of %s\n", $4, $2 }'

echo "Local stack"
if stack_up_api; then printf '  api          up   %s\n' "$(curl -fsS -m 2 "$API_URL/healthz" 2>/dev/null | head -c 120)"
else printf '  api          down (%s)\n' "$API_URL"; fi
if stack_up_auth; then printf '  auth-emu     up   http://%s\n' "$AUTH_EMULATOR"
else printf '  auth-emu     down (http://%s)\n' "$AUTH_EMULATOR"; fi

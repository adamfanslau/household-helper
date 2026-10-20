#!/usr/bin/env bash
# Cross-device realtime check: alice on the iPhone 17 simulator, bob on the Pixel_10_Pro emulator.
#   realtime.sh <label>
# Requires: stack up (fresh seed is best), both apps built and installed (ios.sh build/install, android.sh build).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="$REPO_ROOT/scripts/dev"; label="${1:-realtime}"; H="11111111-1111-4111-8111-111111111111"
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; FAILED=1; }; FAILED=0
"$S/stack.sh" status | grep -q "api=ok" || die "stack is down"
"$S/android.sh" avd status | grep -q "^up" || die "AVD is down (android.sh avd up)"
"$S/sim.sh" boot "$UDID_IPHONE17" >/dev/null

log "alice on iOS, bob on Android (bob joins MOCK1234 through the API)"
"$S/api.sh" bob POST /v1/households/join '{"code":"MOCK1234"}' >/dev/null
"$S/ios.sh" launch "$UDID_IPHONE17" alice >/dev/null; "$S/android.sh" launch bob >/dev/null; sleep 8
# Fresh installs ask for notification permission first.
"$S/ios.sh" allow "$UDID_IPHONE17" >/dev/null 2>&1 || true; "$S/android.sh" taptext Allow >/dev/null 2>&1 || true; sleep 1
"$S/android.sh" tap tab.settings >/dev/null; sleep 1; "$S/android.sh" tap "settings.household.Mock Household" >/dev/null 2>&1 || true; "$S/android.sh" tap tab.list >/dev/null; sleep 2

log "alice adds 'Oat milk' on iOS → must appear on Android within 5 s"
"$S/ios.sh" tap "$UDID_IPHONE17" list.add >/dev/null; sleep 1.5; "$S/ios.sh" type "$UDID_IPHONE17" "Oat milk" >/dev/null; "$S/ios.sh" tap "$UDID_IPHONE17" list.submit >/dev/null; sleep 5
"$S/android.sh" tree | grep -q "list.item.Oat milk" && pass "android shows Oat milk" || fail "android missing Oat milk"

log "bob marks it bought on Android → iOS shows it under Recently bought within 5 s"
"$S/android.sh" tap "list.item.Oat milk" >/dev/null; sleep 5
"$S/ios.sh" tap "$UDID_IPHONE17" list.bought.toggle >/dev/null 2>&1 || true; sleep 1
"$S/ios.sh" tree "$UDID_IPHONE17" | grep "list.item.Oat milk" | grep -q bought && pass "ios shows Oat milk bought" || fail "ios did not get the update (AXe tree may be empty: read screen.png)"
"$S/snap.sh" ios "$UDID_IPHONE17" "$label-ios" >/dev/null; "$S/snap.sh" android "$label-android" >/dev/null
"$S/api.sh" alice GET "/v1/households/$H/items" | tail -1 | jq -c '.[] | select(.name=="Oat milk") | {status, added_by}'
exit $FAILED

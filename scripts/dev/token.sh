#!/usr/bin/env bash
# Print a Firebase ID token for a seeded dev user:  token.sh alice|bob
# Signs in against the Auth emulator with the seeded password. If the user is
# missing (emulator restarted), re-creates alice and bob through the admin endpoint once.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq; need curl
who="${1:-}"
case "$who" in alice|bob) ;; *) die "usage: token.sh alice|bob" ;; esac
email="$who@dev.local"

sign_in() {
  curl -fsS -m 5 -X POST "http://$AUTH_EMULATOR/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"password\",\"returnSecureToken\":true}" 2>/dev/null | jq -r '.idToken // empty'
}
ensure_users() { # same call the Go dev seed makes (internal/devseed)
  for u in "dev-alice alice@dev.local Alice" "dev-bob bob@dev.local Bob"; do
    set -- $u
    curl -fsS -m 5 -o /dev/null -X POST "http://$AUTH_EMULATOR/identitytoolkit.googleapis.com/v1/projects/$FIREBASE_PROJECT/accounts" \
      -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
      -d "{\"localId\":\"$1\",\"email\":\"$2\",\"password\":\"password\",\"displayName\":\"$3\",\"emailVerified\":true}" >/dev/null 2>&1 || true
  done
}

stack_up_auth || die "auth emulator is down (scripts/dev/stack.sh up)"
tok="$(sign_in)"
if [ -z "$tok" ]; then ensure_users; tok="$(sign_in)"; fi
[ -n "$tok" ] || die "could not sign in $email"
printf '%s\n' "$tok"

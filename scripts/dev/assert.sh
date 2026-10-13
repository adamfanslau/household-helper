#!/usr/bin/env bash
# Assertions over a snapshot, the API or a log. Prints PASS/FAIL and exits accordingly.
#   assert.sh tree <label> '<id-regex>' [absent]
#   assert.sh api alice|bob /v1/path '<jq filter that must be truthy>'
#   assert.sh log <label> '<regex>'
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="$REPO_ROOT/scripts/dev"
pass() { echo "PASS $*"; exit 0; }
fail() { echo "FAIL $*"; exit 1; }
case "${1:-}" in
  tree)
    [ $# -ge 3 ] || die "usage: assert.sh tree <label> '<regex>' [absent]"
    f="$SHOT_DIR/$2/tree.txt"; [ -f "$f" ] || fail "no tree at $f"
    if grep -qE -- "$3" "$f"; then [ "${4:-}" = absent ] && fail "tree $2 contains /$3/" || pass "tree $2 contains /$3/"
    else [ "${4:-}" = absent ] && pass "tree $2 lacks /$3/" || fail "tree $2 lacks /$3/"; fi ;;
  api)
    [ $# -eq 4 ] || die "usage: assert.sh api alice|bob /v1/path '<jq>'"
    body="$("$S/api.sh" "$2" GET "$3" | tail -n +2)"
    if printf '%s' "$body" | jq -e "$4" >/dev/null 2>&1; then pass "api $3 | $4"; else fail "api $3 | $4 (body: $(printf '%s' "$body" | cut -c1-200))"; fi ;;
  log)
    [ $# -eq 3 ] || die "usage: assert.sh log <label> '<regex>'"
    f="$SHOT_DIR/$2/log.txt"; [ -f "$f" ] || fail "no log at $f"
    grep -qE -- "$3" "$f" && pass "log $2 matches /$3/" || fail "log $2 lacks /$3/" ;;
  *) die "usage: assert.sh tree|api|log …" ;;
esac

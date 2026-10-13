#!/usr/bin/env bash
# Watch a household's event stream for N seconds:  sse.sh alice|bob <hid> [seconds=10]
# Raw frames go to .dev/logs/sse.log; prints a count per frame type when done.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need curl
who="${1:-}"; hid="${2:-}"; secs="${3:-10}"
[ -n "$who" ] && [ -n "$hid" ] || die "usage: sse.sh alice|bob <household-id> [seconds]"
stack_up_api || die "api is down (scripts/dev/stack.sh up)"
tok="$("$REPO_ROOT/scripts/dev/token.sh" "$who")"
curl -sN -m "$secs" -H "Authorization: Bearer $tok" "$API_URL/v1/households/$hid/events" > "$LOG_DIR/sse.log" 2>/dev/null || true
echo "frames in ${secs}s ($LOG_DIR/sse.log):"
grep -oE '^(event: [a-z]+|: ping)' "$LOG_DIR/sse.log" | sort | uniq -c | sed 's/^/  /'
grep -A1 '^event: change' "$LOG_DIR/sse.log" | grep '^data:' | cut -c1-160 | sed 's/^/  /'

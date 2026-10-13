#!/usr/bin/env bash
# Call the local API as a seeded user:  api.sh alice|bob GET|POST|PATCH|DELETE /v1/path ['{"json":1}']
# Prints "HTTP <code>" then the jq-compacted body. Tokens never hit the logs.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq; need curl
who="${1:-}"; method="${2:-}"; path="${3:-}"; body="${4:-}"
[ -n "$who" ] && [ -n "$method" ] && [ -n "$path" ] || die 'usage: api.sh alice|bob GET|POST|PATCH|DELETE /v1/path [json]'
stack_up_api || die "api is down (scripts/dev/stack.sh up)"
tok="$("$REPO_ROOT/scripts/dev/token.sh" "$who")"
out="$(mktemp)"
code="$(curl -sS -m 30 -o "$out" -w '%{http_code}' -X "$method" "$API_URL$path" \
  -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' ${body:+--data "$body"})"
echo "HTTP $code"
if [ -s "$out" ]; then jq -c . "$out" 2>/dev/null || cat "$out"; fi
rm -f "${out:?}"

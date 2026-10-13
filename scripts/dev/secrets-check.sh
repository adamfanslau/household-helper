#!/usr/bin/env bash
# Refuse to commit secrets. Scans STAGED files (default) or the whole tree (--all) for
# forbidden paths and secret-shaped content. Exit 0 = clean, 1 = findings.
# --hook: Claude Code PreToolUse mode — reads the tool call JSON on stdin, runs only for
#         `git commit`, exits 2 on findings so the harness blocks the commit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

mode="${1:-staged}"
if [ "$mode" = "--hook" ]; then
  cmd="$(jq -r '.tool_input.command // ""' 2>/dev/null)"
  case "$cmd" in *"git commit"*|*"git -C"*"commit"*) ;; *) exit 0 ;; esac
  mode=staged
fi

# Paths that must never be committed (regex on the repo-relative path).
forbidden_paths='(^|/)\.env(\.[^/]*)?$|GoogleService-Info\.plist$|google-services\.json$|\.(p8|p12|jks|keystore|pem|key)$|fcm-sa[^/]*\.json$|(^|/)id_(rsa|ed25519|ecdsa)[^/]*$|\.db(-wal|-shm)?$|(^|/)\.netrc$'
# Exceptions: templates and the fabricated dev-flavor Firebase config.
allowed_paths='\.example$|^apps/android/app/src/dev/google-services\.json$'

# Secret-shaped content. Keep patterns specific; dev fakes use "demo-" / "password" on purpose.
content_patterns=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '"private_key"[[:space:]]*:'              # GCP service-account JSON
  'sb_secret_[A-Za-z0-9_-]{10,}'            # Supabase secret key
  'eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'   # JWT
  'AIza[0-9A-Za-z_-]{35}'                   # Google API key
  'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'            # Slack
  'AKIA[0-9A-Z]{16}'                        # AWS
  'sk_live_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{32,}'
  '(SECRET|TOKEN|PASSWORD|API_KEY)[A-Z_]*=[^[:space:]"'"'"']{12,}'   # KEY=realvalue in env-ish files
)

if [ "$mode" = "--all" ]; then
  files="$(git ls-files)"; show() { cat -- "$1"; }
else
  files="$(git diff --cached --name-only --diff-filter=ACMR)"; show() { git show ":$1"; }
fi
[ -n "$files" ] || exit 0

findings=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [[ "$f" =~ $forbidden_paths ]] && ! [[ "$f" =~ $allowed_paths ]]; then
    echo "SECRET PATH  $f"; findings=$((findings+1)); continue
  fi
  # skip binaries
  if [ "$(show "$f" | head -c 4000 | tr -dc '\000' | wc -c)" -gt 0 ]; then continue; fi
  for pat in "${content_patterns[@]}"; do
    hits="$(show "$f" | grep -nE -e "$pat" | grep -v 'secrets-check: allow' | head -3 || true)"
    if [ -n "$hits" ]; then
      while IFS= read -r h; do echo "SECRET MATCH $f:${h%%:*}  ($pat)"; done <<< "$hits"
      findings=$((findings+1))
    fi
  done
done <<< "$files"

if [ "$findings" -gt 0 ]; then
  echo "secrets-check: $findings finding(s). Remove the secret, rotate it if it was ever committed, or append 'secrets-check: allow' on a line that is a known non-secret." >&2
  [ "${1:-}" = "--hook" ] && exit 2 || exit 1
fi
echo "secrets-check: clean"

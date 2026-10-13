#!/usr/bin/env bash
# Free disk plus the caches that grow during iOS/Android work. Run before clean builds.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
df -h / | awk 'NR==2 { printf "free: %s of %s (%s used)\n", $4, $2, $5 }'
for d in "$DERIVED_DATA" "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/.gradle/caches" "$SHOT_DIR" "$REPO_ROOT/node_modules"; do
  [ -d "$d" ] && printf '%-8s %s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)" "$d"
done
true

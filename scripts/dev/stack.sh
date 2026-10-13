#!/usr/bin/env bash
# Local stack: Firebase Auth emulator (127.0.0.1:9099, UI :4000) + hh-api (127.0.0.1:8091).
#   stack.sh up | down | status | reset | logs [api|firebase] [n]
# Processes run in the background with pid files in .dev/pids and logs in .dev/logs.
# `up` is idempotent. `reset` deletes apps/api/hh-dev.db* for a fresh seed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

API_DIR="$REPO_ROOT/apps/api"
API_BIN="$DEV_DIR/bin/hh-api"
FIREBASE="$REPO_ROOT/node_modules/.bin/firebase"

alive() { [ -f "$PID_DIR/$1.pid" ] && kill -0 "$(cat "$PID_DIR/$1.pid")" 2>/dev/null; }
stop_one() {
  local name="${1:?}"
  if alive "$name"; then
    kill "$(cat "$PID_DIR/$name.pid")" 2>/dev/null || true
    for _ in $(seq 1 50); do alive "$name" || break; sleep 0.2; done
    alive "$name" && kill -9 "$(cat "$PID_DIR/$name.pid")" 2>/dev/null || true
  fi
  rm -f "${PID_DIR:?}/${name:?}.pid"
}
wait_for() { # wait_for <label> <seconds> <command...>
  local label="$1" secs="$2"; shift 2
  for _ in $(seq 1 $((secs * 2))); do "$@" >/dev/null 2>&1 && return 0; sleep 0.5; done
  log "timeout waiting for $label ($secs s); see $LOG_DIR"; return 1
}

up() {
  need jq; need curl
  [ -x "$FIREBASE" ] || die "firebase CLI missing: run 'npm install' at the repo root"
  [ -f "$API_DIR/.env" ] || { cp "$API_DIR/.env.example" "$API_DIR/.env"; log "created apps/api/.env from .env.example"; }
  if ! stack_up_auth; then
    stop_one firebase
    # exec inside the backgrounded subshell: $! is then the service's own pid and the
    # redirect happens before exec, so nothing keeps the caller's stdout pipe open.
    (cd "$REPO_ROOT" && exec "$FIREBASE" emulators:start --only auth --project "$FIREBASE_PROJECT" \
        > "$LOG_DIR/firebase.log" 2>&1 < /dev/null) &
    echo $! > "$PID_DIR/firebase.pid"
    wait_for "auth emulator" 60 curl -fsS -m 1 "http://$AUTH_EMULATOR/" || exit 1
  fi
  mkdir -p "$(dirname "$API_BIN")"
  (cd "$API_DIR" && go build -o "$API_BIN" ./cmd/hh-api) || die "go build failed"
  stop_one api
  (cd "$API_DIR" && set -a && . ./.env && set +a && exec "$API_BIN" > "$LOG_DIR/api.log" 2>&1 < /dev/null) &
  echo $! > "$PID_DIR/api.pid"
  wait_for "api" 30 curl -fsS -m 1 "$API_URL/healthz" || { tail -5 "$LOG_DIR/api.log" >&2; exit 1; }
  status
}

down() { stop_one api; stop_one firebase; echo "api=down auth=down"; }

status() {
  local api auth seed
  if stack_up_api; then api="ok ($(curl -fsS -m 2 "$API_URL/healthz" | jq -r '.auth + " " + .version'))"; else api=down; fi
  if stack_up_auth; then auth=ok; else auth=down; fi
  seed="n/a"
  [ -f "$LOG_DIR/api.log" ] && grep -q '"msg":"dev seed' "$LOG_DIR/api.log" 2>/dev/null && seed=ok
  echo "api=$api auth=$auth seed=$seed"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  reset)
    down
    for f in hh-dev.db hh-dev.db-wal hh-dev.db-shm; do rm -f "${API_DIR:?}/$f"; done
    log "deleted apps/api/hh-dev.db*"
    up ;;
  logs) tail -n "${3:-50}" "$LOG_DIR/${2:-api}.log" ;;
  *) die "usage: stack.sh up | down | status | reset | logs [api|firebase] [n]" ;;
esac

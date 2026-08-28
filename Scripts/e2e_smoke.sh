#!/usr/bin/env bash
# Live smoke for DeskPet (native AppKit).
# Playwright cannot drive LSUIElement menu-bar / borderless NSWindows; this uses
# the debug harness and the process's own NSLog stream instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG="$ROOT/.build/e2e-smoke.log"
mkdir -p "$ROOT/.build"
rm -f "$LOG"

echo "== kill leftover DeskPet =="
killall DeskPet 2>/dev/null || true
sleep 0.5

echo "== build app =="
make app >/dev/null

BIN="./DeskPet.app/Contents/MacOS/DeskPet"
echo "== launch binary with debug harness =="
DESKPET_DEBUG_DUMP_SETTINGS=1 \
DESKPET_DEBUG_DUMP_MENU=1 \
DESKPET_DEBUG_LOG_STATE=1 \
DESKPET_DEBUG_INTERVALS=1,1 \
DESKPET_DEBUG_SETTINGS=1 \
DESKPET_DEBUG_FOCUS=2 \
DESKPET_DEBUG_HYDRATION=4 \
DESKPET_DEBUG_QUIT=8 \
"$BIN" >"$LOG" 2>&1 &
PID=$!
echo "pid=$PID log=$LOG"

cleanup() {
  kill "$PID" 2>/dev/null || true
  killall DeskPet 2>/dev/null || true
}
trap cleanup EXIT

echo "== wait for quit (≤15s) =="
for _ in $(seq 1 30); do
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Give buffers a moment to flush.
sleep 0.3
wait "$PID" 2>/dev/null || true
trap - EXIT

echo "== results =="
fail=0
check() {
  local label="$1" pattern="$2"
  if grep -Eq "$pattern" "$LOG"; then
    echo "PASS  $label"
  else
    echo "FAIL  $label  (/$pattern/)"
    fail=1
  fi
}

check "launch" "DeskPet .* launched"
check "menu dump" "DeskPet\\[debug\\]: tray menu has"
check "settings open" "DeskPet\\[debug\\]: opening settings"
check "hydration demo" "DeskPet\\[debug\\]: triggering hydration prompt"
check "focus start" "DeskPet\\[debug\\]: starting focus session"
check "quit probe" "DeskPet\\[debug\\]: quitting"
check "hydration state" "state=hydrationPrompt"
check "focus state" "state=focusGuard"
check "focus active" "focusActive=true"

if pgrep -x DeskPet >/dev/null 2>&1; then
  echo "FAIL  DeskPet still running"
  killall DeskPet 2>/dev/null || true
  fail=1
else
  echo "PASS  process exited"
fi

if (( fail == 0 )); then
  echo "e2e smoke: OK"
  exit 0
fi
echo "---- last 80 log lines ----"
tail -80 "$LOG" || true
echo "e2e smoke: FAILED"
exit 1

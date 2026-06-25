#!/usr/bin/env bash
#
# killswitch.sh — emergency force-quit for Frost.
#
# Frost suppresses local keyboard/mouse/trackpad input while locked, so the
# realistic way to run this is OVER SSH from another device, or from a terminal
# session you started BEFORE locking. (Locally, input is blocked while the lock
# is active — that is what the in-app DEBUG auto-unlock timer is for.)
#
# Safe to run anytime; it only targets Frost.

set -uo pipefail

BUNDLE_ID="dev.abdeen.frost"
EXECUTABLE="frost"
APP_EXEC_PATH="${EXECUTABLE}.app/Contents/MacOS/${EXECUTABLE}"

echo "[frost killswitch] Force-quitting Frost (${BUNDLE_ID})…"

found=0

# 1) Exact executable-name match (covers both Xcode-run and installed builds).
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
  found=1
  pkill -9 -x "$EXECUTABLE" || true
fi

# 2) Full app-bundle path match (more specific; avoids unrelated "frost" tools).
if pgrep -f "$APP_EXEC_PATH" >/dev/null 2>&1; then
  found=1
  pkill -9 -f "$APP_EXEC_PATH" || true
fi

# Give the OS a moment to tear down the event tap and restore input.
sleep 1 || true

# Verify nothing survived.
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1 || pgrep -f "$APP_EXEC_PATH" >/dev/null 2>&1; then
  echo "[frost killswitch] WARNING: Frost is still running. Surviving process(es):" >&2
  pgrep -fl "$EXECUTABLE" >&2 || true
  echo "[frost killswitch] Try again, or: kill -9 <pid>" >&2
  exit 1
fi

if [ "$found" -eq 0 ]; then
  echo "[frost killswitch] No running Frost process found."
else
  echo "[frost killswitch] Done — Frost terminated; input restored."
fi

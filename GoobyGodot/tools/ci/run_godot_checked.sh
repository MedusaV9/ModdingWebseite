#!/usr/bin/env bash
# Run one Godot command, preserve its exit code, and reject hidden engine
# errors/leaks/skips from the complete combined stdout/stderr log.
set -uo pipefail

if [ "$#" -lt 3 ] || [ "$2" != "--" ]; then
  echo "Aufruf: $0 <log-pfad> -- <befehl> [argumente ...]" >&2
  exit 2
fi

LOG_PATH="$1"
shift 2

mkdir -p "$(dirname "$LOG_PATH")"
"$@" 2>&1 | tee "$LOG_PATH"
COMMAND_STATUS="${PIPESTATUS[0]}"

LOG_STATUS=0
CHECK_ARGS=("$LOG_PATH")
if [ -n "${GODOT_LOG_ALLOWLIST:-}" ]; then
  CHECK_ARGS+=("$GODOT_LOG_ALLOWLIST")
fi
python3 "$(dirname "$0")/check_godot_log.py" "${CHECK_ARGS[@]}" || LOG_STATUS="$?"

if [ "$COMMAND_STATUS" -ne 0 ]; then
  echo "GODOT-PROZESS ROT: Exit $COMMAND_STATUS" >&2
  exit "$COMMAND_STATUS"
fi
exit "$LOG_STATUS"

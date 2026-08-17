#!/usr/bin/env bash
# Runs one Godot command with a fresh user:// and editor configuration.
#
# Godot maps user:// through XDG_DATA_HOME on Linux. A developer profile can
# otherwise hide first-run UI (for example hints.hud_actions_seen), while a
# fresh GitHub runner renders it. HOME and all XDG roots are isolated together
# so local preflight and CI execute against the same empty persisted state.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Aufruf: $0 <godot-befehl> [argumente ...]" >&2
  exit 2
fi

ROOT="${CIWATCH_USER_DATA_ROOT:-}"
REMOVE_ROOT=0
if [ -z "$ROOT" ]; then
  ROOT="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gooby-godot-user.XXXXXX")"
  REMOVE_ROOT=1
fi

cleanup() {
  if [ "$REMOVE_ROOT" = "1" ]; then
    rm -rf "$ROOT"
  fi
}
trap cleanup EXIT

mkdir -p "$ROOT/home" "$ROOT/xdg-data" "$ROOT/xdg-config" "$ROOT/xdg-cache"
export HOME="$ROOT/home"
export XDG_DATA_HOME="$ROOT/xdg-data"
export XDG_CONFIG_HOME="$ROOT/xdg-config"
export XDG_CACHE_HOME="$ROOT/xdg-cache"
export CIWATCH_ISOLATED_USER_DATA=1
export CIWATCH_USER_DATA_ROOT="$ROOT"

"$@"

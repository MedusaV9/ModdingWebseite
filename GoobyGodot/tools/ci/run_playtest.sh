#!/usr/bin/env bash
# Playtest-Wrapper (G7-P58): startet EINEN Playtest-Lauf der Harness
# GOOBY-GODOT/tests/tools/playtest_harness.gd (Doku im Datei-Kopf dort) —
# echtes Spiel (main.tscn) unter xvfb/llvmpipe, eigenes user:// pro Lauf
# (über run_godot_isolated.sh), Log-Tee und Log-Befund-Anhang an report.md.
#
# Nutzung: tools/ci/run_playtest.sh <flow> [BxH] [lauf-id]
#   <flow>    z. B. flow_home_basis (Datei in tests/tools/playtest_flows/)
#   [BxH]     Fenster, Default 2868x1320 (Leitformat quer; hoch: 1320x2868)
#   [lauf-id] Ordnername unter /tmp/gooby-godot/artifacts/PLAYTEST/
#             (Default <flow>_<Zeit>_<PID> — parallele Läufe: einfach weglassen)
#
# Der xvfb-Screen wird IMMER auf exakt BxH gestellt (hoch wie quer). Grund
# (Befund B6, W18): xvfb-runs Default-Screen 1280x1024 ist KLEINER als das
# Fenster; UiScale.safe_insets_canvas schneidet die Display-Safe-Area (=Screen)
# mit dem Fenster und erfand so Phantom-Safe-Insets (rechts 234,6/unten 108 px
# Canvas beim Leitformat) — jede Zentrierung in den Screenshots war verschoben.
#
# Parallel (10 Instanzen): jede bekommt automatisch eigene Lauf-Id, eigenes
# user:// und ein eigenes xvfb-Display (xvfb-run -a):
#   for f in flow_home_basis flow_baumodus flow_arcade; do
#     tools/ci/run_playtest.sh "$f" & done; wait
#
# Exit-Codes: 0 alles ok, 1 Pflicht-Schritt fehlgeschlagen, 2 Watchdog,
# 3 Konfigurationsfehler, 124 harter timeout(1)-Abbruch.
set -uo pipefail

FLOW="${1:?Nutzung: run_playtest.sh <flow> [BxH] [lauf-id]}"
RES="${2:-2868x1320}"
if ! [[ "$RES" =~ ^[0-9]+x[0-9]+$ ]]; then
	echo "[run_playtest] Ungültiges Format '$RES' (erwartet BxH, z. B. 2868x1320)" >&2
	exit 3
fi
LAUF="${3:-${FLOW}_$(date +%H%M%S)_$$}"
OUT_BASE="${PLAYTEST_OUT:-/tmp/gooby-godot/artifacts/PLAYTEST}"
OUT="$OUT_BASE/$LAUF"
MAX_SEC="${PLAYTEST_MAX_SEC:-900}"

cd "$(dirname "$0")/../.."
mkdir -p "$OUT/user-data"

# Harter Not-Aus 90 s über dem Harness-Watchdog (falls Godot selbst hängt).
PLAYTEST_FLOW="$FLOW" PLAYTEST_LAUF="$LAUF" PLAYTEST_OUT="$OUT_BASE" \
	PLAYTEST_SIZE="$RES" PLAYTEST_MAX_SEC="$MAX_SEC" \
	CIWATCH_USER_DATA_ROOT="$OUT/user-data" \
	timeout -k 15 "$((MAX_SEC + 90))" \
	tools/ci/run_godot_isolated.sh xvfb-run -a -s "-screen 0 ${RES}x24" \
	godot --path GOOBY-GODOT \
	--rendering-method gl_compatibility --rendering-driver opengl3 \
	--audio-driver Dummy --resolution "$RES" \
	--script res://tests/tools/playtest_harness.gd 2>&1 | tee "$OUT/lauf.log"
CODE="${PIPESTATUS[0]}"

# Log-Befunde (Godot-Fehlerausgabe = Fundgrube) an den Report anhängen.
{
	echo ""
	echo "## Log-Befunde (aus lauf.log)"
	echo ""
	echo '```'
	grep -nE "SCRIPT ERROR|USER ERROR|^ERROR|WARNING" "$OUT/lauf.log" \
		| grep -v "at: \|libEGL warning" | head -80 || echo "keine ERROR/WARNING-Zeilen"
	echo '```'
} >>"$OUT/report.md" 2>/dev/null

echo "[run_playtest] Lauf '$LAUF' fertig (Exit $CODE) -> $OUT/report.md"
exit "$CODE"

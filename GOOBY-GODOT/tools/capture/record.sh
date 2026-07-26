#!/usr/bin/env bash
## Trailer-Aufnahme (Agent TRAILER): rendert einen Clip-Treiber im Godot-
## Movie-Maker-Modus (feste 60-fps-Schrittweite, MJPEG-AVI) unter xvfb.
## Nutzung: tools/capture/record.sh <clip-name> [WxH]
## Ausgabe: $OUT_DIR/<clip-name>.avi (Default /workspace/trailer/captures)
set -euo pipefail

CLIP="${1:?Nutzung: record.sh <clip-name> [WxH] [max-sekunden]}"
RES="${2:-1920x1080}"
CAP_SEC="${3:-30}"
OUT_DIR="${OUT_DIR:-/workspace/trailer/captures}"
mkdir -p "$OUT_DIR"

cd "$(dirname "$0")/../.."

# --quit-after als harte Notbremse, falls ein Treiber sich nicht beendet.
# NICE_LEVEL=0 für finale Aufnahmen (Probeläufe laufen niedrig priorisiert).
nice -n "${NICE_LEVEL:-10}" xvfb-run -a godot --path . \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution "$RES" --write-movie "$OUT_DIR/$CLIP.avi" --fixed-fps 60 \
  --quit-after "$((CAP_SEC * 60))" \
  res://tools/capture/capture_stage.tscn -- --clip="$CLIP"

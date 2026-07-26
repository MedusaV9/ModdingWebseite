#!/usr/bin/env bash
## Trailer-Aufnahme (Agent TRAILER): rendert einen Clip-Treiber im Godot-
## Movie-Maker-Modus (feste 60-fps-Schrittweite) unter xvfb.
## Nutzung: tools/capture/record.sh <clip-name> [WxH] [max-sekunden]
## FORMAT=png (Default): verlustfreie PNG-Einzelbilder nach
##   $OUT_DIR/<clip-name>/f00000000.png … (Qualitäts-Kette ohne MJPEG!)
## FORMAT=avi: altes MJPEG-AVI-Verhalten (nur für schnelle Probeläufe).
set -euo pipefail

CLIP="${1:?Nutzung: record.sh <clip-name> [WxH] [max-sekunden]}"
RES="${2:-1920x1080}"
CAP_SEC="${3:-30}"
OUT_DIR="${OUT_DIR:-/workspace/trailer/captures}"
FORMAT="${FORMAT:-png}"
mkdir -p "$OUT_DIR"

if [[ "$FORMAT" == "png" ]]; then
  rm -rf "$OUT_DIR/$CLIP"
  mkdir -p "$OUT_DIR/$CLIP"
  MOVIE="$OUT_DIR/$CLIP/f.png" # Godot schreibt f00000000.png, f00000001.png …
else
  MOVIE="$OUT_DIR/$CLIP.avi"
fi

cd "$(dirname "$0")/../.."

# --quit-after als harte Notbremse, falls ein Treiber sich nicht beendet.
# NICE_LEVEL=0 für finale Aufnahmen (Probeläufe laufen niedrig priorisiert).
nice -n "${NICE_LEVEL:-10}" xvfb-run -a godot --path . \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution "$RES" --write-movie "$MOVIE" --fixed-fps 60 \
  --quit-after "$((CAP_SEC * 60))" \
  res://tools/capture/capture_stage.tscn -- --clip="$CLIP"

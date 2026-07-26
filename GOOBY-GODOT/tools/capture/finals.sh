#!/usr/bin/env bash
## Finale Trailer-Aufnahmen in NATIVER Zielauflösung (kein Upscaling mehr —
## das 960x540→1080p-Hochskalieren war die Ursache des „pixelig“-Feedbacks):
## quer 1920x1080, hoch 720x1280, Godot-Qualität wird vom clip_driver auf
## „hoch“ + MSAA 4x gezwungen. Kette: PNG-Einzelbilder (verlustfrei) →
## H.264 CRF 14 preset slow (visuell transparentes Zwischenformat für
## Remotion) → trailer/public/clips. PNGs werden nach dem Encode gelöscht.
## Nutzung: finals.sh clip1 clip2 ...   (ohne Argumente: alle Trailer-Clips)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CAP_DIR="${CAP_DIR:-/workspace/trailer/captures}"
CLIP_DIR="${CLIP_DIR:-/workspace/trailer/public/clips}"
LAND_RES="${LAND_RES:-1920x1080}"
PORTRAIT_RES="${PORTRAIT_RES:-720x1280}"
CRF="${CRF:-14}"
mkdir -p "$CAP_DIR" "$CLIP_DIR"

PORTRAIT="mg_mini_golf mg_fishing mg_ghost_hunt"
ALLE="showcase home_room home_build ikea wardrobe city_overview city_day \
city_night mg_toy_racer mg_runner mg_goalie mg_gvz mg_gobnom mg_mini_golf \
mg_fishing mg_ghost_hunt visit ranch ranch_ride ranch_comp ranch_dorf \
ranch_wetter"

CLIPS=("$@")
if [[ ${#CLIPS[@]} -eq 0 ]]; then read -r -a CLIPS <<<"$ALLE"; fi

for clip in "${CLIPS[@]}"; do
  res="$LAND_RES"
  if [[ " $PORTRAIT " == *" $clip "* ]]; then res="$PORTRAIT_RES"; fi
  echo "=== FINAL $clip ($res) $(date +%H:%M:%S)"
  OUT_DIR="$CAP_DIR" NICE_LEVEL=0 FORMAT=png "$HERE/record.sh" "$clip" "$res" 40 2>&1 \
    | grep -E "SCRIPT ERROR|ERROR|WARNING|Clip|capture|Done recording|frames at" | head -30
  frames_dir="$CAP_DIR/$clip"
  n=$(ls "$frames_dir"/f*.png 2>/dev/null | wc -l)
  if [[ "$n" -lt 60 ]]; then
    echo "!!! $clip: nur $n PNG-Frames — Aufnahme fehlgeschlagen?"
    continue
  fi
  ffmpeg -y -loglevel error -framerate 60 -i "$frames_dir/f%08d.png" \
    -c:v libx264 -preset slow -crf "$CRF" -pix_fmt yuv420p -an \
    "$CLIP_DIR/$clip.mp4"
  status=$?
  if [[ $status -eq 0 ]]; then
    rm -rf "$frames_dir" "$frames_dir.wav" "$CAP_DIR/$clip/f.wav" 2>/dev/null
    echo "    → $CLIP_DIR/$clip.mp4 ($n Frames, $(du -h "$CLIP_DIR/$clip.mp4" | cut -f1))"
  else
    echo "!!! $clip: ffmpeg-Encode fehlgeschlagen (PNGs bleiben liegen)"
  fi
done
echo "=== FERTIG $(date +%H:%M:%S)"

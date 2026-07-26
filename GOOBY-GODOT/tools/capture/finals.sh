#!/usr/bin/env bash
## Finale Trailer-Aufnahmen: rendert jeden übergebenen Clip in Zielauflösung
## (960x540 quer / 480x854 hoch), konvertiert direkt nach H.264-MP4 in
## trailer/public/clips (quer mit Lanczos auf 1920x1080 hochskaliert).
## Nutzung: finals.sh clip1 clip2 ...   (ohne Argumente: alle Trailer-Clips)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CAP_DIR="${CAP_DIR:-/workspace/trailer/captures}"
CLIP_DIR="${CLIP_DIR:-/workspace/trailer/public/clips}"
mkdir -p "$CAP_DIR" "$CLIP_DIR"

PORTRAIT="mg_mini_golf mg_fishing mg_ghost_hunt"
ALLE="showcase home_room home_build ikea wardrobe city_overview city_day \
city_night mg_toy_racer mg_runner mg_goalie mg_gvz mg_gobnom mg_mini_golf \
mg_fishing mg_ghost_hunt visit ranch"

CLIPS=("$@")
if [[ ${#CLIPS[@]} -eq 0 ]]; then read -r -a CLIPS <<<"$ALLE"; fi

for clip in "${CLIPS[@]}"; do
  res="960x540"
  filter="scale=1920:1080:flags=lanczos"
  if [[ " $PORTRAIT " == *" $clip "* ]]; then
    res="480x854"
    filter="scale=480:854:flags=lanczos"
  fi
  echo "=== FINAL $clip ($res) $(date +%H:%M:%S)"
  OUT_DIR="$CAP_DIR" NICE_LEVEL=0 "$HERE/record.sh" "$clip" "$res" 40 2>&1 \
    | grep -E "SCRIPT ERROR|ERROR|WARNING|Clip|Done recording|frames at" | head -30
  avi="$CAP_DIR/$clip.avi"
  if [[ ! -f "$avi" ]]; then
    echo "!!! $clip: kein AVI"
    continue
  fi
  # CRF 20/slow: Quellmaterial fürs Remotion-Rendering — klein genug fürs
  # Repo, der finale Trailer wird ohnehin nochmal komprimiert.
  ffmpeg -y -loglevel error -i "$avi" -vf "$filter" \
    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -an \
    "$CLIP_DIR/$clip.mp4"
  echo "    → $CLIP_DIR/$clip.mp4 ($(du -h "$CLIP_DIR/$clip.mp4" | cut -f1))"
done
echo "=== FERTIG $(date +%H:%M:%S)"

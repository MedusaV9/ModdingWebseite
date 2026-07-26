#!/usr/bin/env bash
## Probelauf: rendert jeden übergebenen Clip klein (640x360 bzw. 360x640)
## und zieht ein Kontrollbild aus der Mitte. Nutzung: probe_all.sh clip1 clip2 ...
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${OUT_DIR:-/workspace/trailer/probe}"
mkdir -p "$OUT_DIR"

PORTRAIT="mg_mini_golf mg_fishing mg_ghost_hunt"

for clip in "$@"; do
  res="640x360"
  if [[ " $PORTRAIT " == *" $clip "* ]]; then res="360x640"; fi
  echo "=== $clip ($res)"
  OUT_DIR="$OUT_DIR" FORMAT=avi "$HERE/record.sh" "$clip" "$res" 30 2>&1 \
    | grep -E "SCRIPT ERROR|ERROR|Clip|Done recording|frames at|WARNING.*capture" | head -20
  avi="$OUT_DIR/$clip.avi"
  if [[ -f "$avi" ]]; then
    frames=$(ffprobe -v error -count_packets -select_streams v -show_entries stream=nb_read_packets -of csv=p=0 "$avi" 2>/dev/null)
    mid=$((frames / 2))
    ffmpeg -y -loglevel error -i "$avi" -vf "select=eq(n\,$mid)" -vframes 1 "$OUT_DIR/${clip}_mid.png"
    ffmpeg -y -loglevel error -i "$avi" -vf "select=eq(n\,$((frames-30)))" -vframes 1 "$OUT_DIR/${clip}_end.png"
    echo "    $frames Frames → ${clip}_mid.png / _end.png"
  fi
done

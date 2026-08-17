#!/usr/bin/env bash
# Chunked-Render für den Trailer: Langläufer-Renders degradieren auf der VM
# (Tab-Hänger nach ~1500+ Frames trotz Retries) — deshalb 4 Video-Chunks mit
# je frischem Prozess/Browser + 1 Audio-Pass, dann ffmpeg-Concat + Mux.
# Aufruf: bash scripts/render-chunked.sh (im Ordner remotion/)
set -eu
cd "$(dirname "$0")/.."

FRAMES=2160
CHUNK=540
OUT=out/chunks
mkdir -p "$OUT"

echo "== Audio-Pass =="
npx remotion render Trailer "$OUT/trailer_audio.wav" --codec wav

i=0
start=0
LIST="$OUT/concat.txt"
: > "$LIST"
while [ "$start" -lt "$FRAMES" ]; do
  end=$((start + CHUNK - 1))
  [ "$end" -ge "$FRAMES" ] && end=$((FRAMES - 1))
  echo "== Video-Chunk $i: Frames $start-$end =="
  npx remotion render Trailer "$OUT/chunk_$i.mp4" --codec h264 --crf=23 --muted \
    --frames="$start-$end"
  echo "file 'chunk_$i.mp4'" >> "$LIST"
  i=$((i + 1))
  start=$((end + 1))
done

echo "== Concat + Mux =="
mkdir -p ../assets/video
ffmpeg -y -f concat -safe 0 -i "$LIST" -i "$OUT/trailer_audio.wav" \
  -c:v copy -c:a aac -b:a 192k -movflags +faststart -shortest \
  ../assets/video/trailer.mp4
ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 \
  ../assets/video/trailer.mp4
echo "OK — assets/video/trailer.mp4"

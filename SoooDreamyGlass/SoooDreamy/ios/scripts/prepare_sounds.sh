#!/usr/bin/env bash
# prepare_sounds.sh — the one-way street from a raw CC0/CC-BY recording to a
# bundled cue file (Dossier 47, section d). ffmpeg-based so the pipeline runs
# identically on macOS and Linux CI (afconvert would be the Mac-only
# alternative).
#
#   bash ios/scripts/prepare_sounds.sh <raw-file> <cueId> [maxDur] [tailFade] [pitch]
#
#   <raw-file>  original download (keep it in tools/sound_sources/, gitignored;
#               record its SHA-256 in sound_credits.json)
#   <cueId>     catalog id from AppCueCatalog.swift — output name is ALWAYS
#               cue_<cueId>.caf, never chosen freely
#   [maxDur]    optional cap in seconds (tail cut on ringing sources)
#   [tailFade]  fade-out length in seconds (default 0.01 — click guard;
#               use 0.2–0.4 when cutting into a ringing tail)
#   [pitch]     optional pitch factor (0.85 = deeper; via asetrate)
#
# Fixed processing (not negotiable, see the dossier):
#   1. leading-silence trim at −50 dB
#   2. 5 ms fade-in / ≥10 ms fade-out — samples click, synthesis does not
#   3. mono, 44.1 kHz — width comes from the engine, not the file
#   4. peak normalization to −6 dBTP; deliberately NOT loudnorm −14 LUFS
#      (integrated loudness is meaningless on sub-second cues and −14 would
#      be startling). Per-cue taste lives in the manifest `gain` field.
#   5. container CAF/PCM16 — AAC priming samples would eat the transient.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <raw-file> <cueId> [maxDur] [tailFade] [pitch]" >&2
    exit 2
fi

RAW="$1"
CUE="$2"
MAXDUR="${3:-}"
TAILFADE="${4:-0.01}"
PITCH="${5:-}"

command -v ffmpeg >/dev/null 2>&1 || { echo "FEHLER: ffmpeg wird gebraucht." >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../SoooDreamy/Resources/Sounds"
OUT="$OUT_DIR/cue_${CUE}.caf"
TMP="$(mktemp --suffix=.wav)"
trap 'rm -f "$TMP"' EXIT

FILTERS="silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.002"
if [[ -n "$PITCH" ]]; then
    FILTERS+=",asetrate=44100*${PITCH},aresample=44100"
fi
if [[ -n "$MAXDUR" ]]; then
    FILTERS+=",atrim=0:${MAXDUR}"
fi
FILTERS+=",aresample=44100,afade=t=in:d=0.005,areverse,afade=t=in:d=${TAILFADE},areverse"

# Pass 1: trim/fade/resample/downmix into an intermediate.
ffmpeg -hide_banner -loglevel error -y -i "$RAW" -af "$FILTERS" -ac 1 -ar 44100 "$TMP"

# Pass 2: measure the true peak (loudnorm's measurement stage — reliable for
# TP even on short files) and normalize to −6 dBTP.
TP=$(ffmpeg -hide_banner -nostats -i "$TMP" -af loudnorm=I=-24:TP=-6.0:print_format=json -f null - 2>&1 \
        | sed -n 's/.*"input_tp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [[ -z "$TP" ]]; then
    echo "FEHLER: True Peak von $RAW nicht messbar." >&2
    exit 1
fi
GAIN=$(awk -v tp="$TP" 'BEGIN { printf "%.2f", -6.0 - tp }')

mkdir -p "$OUT_DIR"
ffmpeg -hide_banner -loglevel error -y -i "$TMP" -af "volume=${GAIN}dB" \
    -ac 1 -ar 44100 -c:a pcm_s16le "$OUT"

SIZE=$(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT")
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")
SHA=$(shasum -a 256 "$RAW" 2>/dev/null | awk '{print $1}' || sha256sum "$RAW" | awk '{print $1}')
echo "cue_${CUE}.caf  dur=${DUR}s  size=${SIZE}B  tp_in=${TP}dBTP  gain=${GAIN}dB  raw_sha256=${SHA}"
if [[ "$SIZE" -gt 122880 ]]; then
    echo "WARNUNG: cue_${CUE}.caf überschreitet das 120-KB-Budget." >&2
    exit 1
fi

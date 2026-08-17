#!/usr/bin/env bash
# Tutorial-Rollout-Render: 1 frischer Remotion-Prozess pro Video (Chunk-
# Prinzip von render-chunked.sh — Langläufer degradieren auf der VM, 540
# Frames pro Tutorial bleiben aber deutlich unter der Hänger-Schwelle).
# Kompositions-Ids + Format-Ids müssen zu src/tutorials.ts passen.
# Aufruf: bash scripts/render-tutorials.sh [format-id …] (ohne Args: alle)
set -eu
cd "$(dirname "$0")/.."

ALLE=(
  "bananen-basics:TutorialBananenBasics"
  "kokosnuss-uhr:TutorialKokosnussUhr"
  "bananen-tresor:TutorialBananenTresor"
  "affenleiter:TutorialAffenleiter"
  "pixel-dschungel:TutorialPixelDschungel"
  "taschendieb:TutorialTaschendieb"
  "affenbank:TutorialAffenbank"
  "alles-oder-banane:TutorialAllesOderBanane"
  "lianen-finale:TutorialLianenFinale"
  "monkey-market:TutorialMonkeyMarket"
  "bananen-bluff:TutorialBananenBluff"
  "bananen-boerse:TutorialBananenBoerse"
  "affen-auktion:TutorialAffenAuktion"
  "lianensteg-duell:TutorialLianenstegDuell"
  "goldener-affe:TutorialGoldenerAffe"
  "buchstaben-telegramm:TutorialBuchstabenTelegramm"
  "musikvideo-raten:TutorialMusikvideoRaten"
  "song-rueckwaerts:TutorialSongRueckwaerts"
  "song-snippet:TutorialSongSnippet"
)

mkdir -p ../assets/video
for paar in "${ALLE[@]}"; do
  id="${paar%%:*}"
  komp="${paar##*:}"
  if [ "$#" -gt 0 ]; then
    case " $* " in
      *" $id "*) ;;
      *) continue ;;
    esac
  fi
  echo "== Tutorial $id ($komp) =="
  npx remotion render "$komp" "../assets/video/tutorial_$id.mp4" --codec h264 --crf=23
done

echo "OK — Tutorials liegen unter assets/video/tutorial_*.mp4"

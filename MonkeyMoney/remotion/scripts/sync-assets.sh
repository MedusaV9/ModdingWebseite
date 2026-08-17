#!/usr/bin/env bash
# Kopiert alles Render-Material (Fonts, Musik, SVGs, Spiel-Screenshots) nach
# public/material/ — Single Source of Truth bleibt assets/** bzw. die
# Test-Artefakte; public/material/ ist gitignored und wird bei Bedarf neu
# erzeugt. Aufruf: npm run sync-assets (im Ordner remotion/).
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="public/material"
mkdir -p "$DEST/fonts" "$DEST/music" "$DEST/img" "$DEST/monkeys" "$DEST/screens"

# Fonts (Bungee/Rubik, OFL — s. CREDITS.md)
cp ../assets/fonts/bungee.ttf ../assets/fonts/bungeeshade.ttf \
  ../assets/fonts/rubik.ttf "$DEST/fonts/"

# Musik (Kevin MacLeod, CC-BY 4.0 — Attribution steht auf der End-Card!)
cp ../assets/audio/music/MonkeysSpinningMonkeys.mp3 \
  ../assets/audio/music/FluffingADuck.mp3 "$DEST/music/"

# Logo (PNG — das SVG nutzt <text>, dessen Fonts in <Img> nicht laden) + Money + UI
cp ../assets/img/logo/monkey-money-logo.png "$DEST/img/"
cp ../assets/img/money/schein.svg ../assets/img/money/muenze.svg \
  ../assets/img/money/geldstapel.svg "$DEST/img/"
cp ../assets/img/ui/rad-basis.svg ../assets/img/ui/timer-banane.svg \
  ../assets/img/ui/buzzer.svg "$DEST/img/"
mkdir -p "$DEST/kategorien" "$DEST/joker"
cp ../assets/img/ui/kategorien/*.svg "$DEST/kategorien/"
cp ../assets/img/ui/joker/*.svg "$DEST/joker/"

# Chrome-Gotcha 1: „--spielerfarbe" u. Ä. in XML-Kommentaren = „double hyphen
# within comment" = ungültiges XML → <img>-Decode schlägt fehl. Alle Kommentare
# aus den Kopien strippen.
# Chrome-Gotcha 2: CSS var() in SVG-als-Bild → auf Default-Farbwert zurückfallen.
# Chrome-Gotcha 3: Steuerzeichen (z. B. 0x1E) in <title> = „PCDATA invalid
# Char" → Titles + Steuerzeichen ebenfalls entfernen.
perl -0pi -e 's/<!--.*?-->//gs; s/<title>.*?<\/title>//gs; tr/\x00-\x08\x0B\x0C\x0E-\x1F//d; s/style="fill:var\(--spielerfarbe,(#[0-9A-Fa-f]{6})\)"/fill="$1"/g' \
  "$DEST"/img/*.svg "$DEST"/monkeys/*.svg "$DEST"/kategorien/*.svg "$DEST"/joker/*.svg
# Timer-Banane: <style>-Block mit var()-clip-path entfernen (volle Banane).
perl -0pi -e 's/<style>.*?<\/style>//gs' "$DEST/img/timer-banane.svg"

# Die 8 Affen
cp ../assets/img/monkeys/*.svg "$DEST/monkeys/"

# Echte Spiel-Screenshots (Gameplay-Beweis) aus den Test-Artefakten.
# Fehlende Quellen sind ok (frische VM) — dann bleibt die vorhandene Kopie
# unter public/material/screens/ einfach stehen.
ART=/opt/cursor/artifacts
for f in \
  mm_tour_01_phone_join_affenwahl.png \
  mm_tour_02_studio_lobby.png \
  mm_tour_05_frage_ledwand.png \
  mm_tour_06_phone_frage.png \
  mm_tour_07_phone_muenz_lockin.png \
  mm_tour_08_aufloesung_podium.png \
  mm_tour_10_gluecksrad_dreh.png \
  mm_tour_11b_phone_buzzer_xxl.png \
  mm_tour_12_siegerehrung.png \
  mm_test1_doc_stinkbanane_sitzkreis.png \
  mm_test2_gm_cockpit_regal_werkzeuge.png; do
  if [ -f "$ART/$f" ]; then
    cp "$ART/$f" "$DEST/screens/"
  else
    echo "   (übersprungen: $ART/$f fehlt — behalte vorhandene Kopie)"
  fi
done

# Format-Gameplay-Shots für den Tutorial-Rollout (src/tutorials.ts):
# erzeugt tools/screenshots/tutorial-shots.mjs (Marathon-Walk, mm_play_*.png).
SHOTS="${SHOTS_DIR:-/tmp/mm-tutorial-shots}"
if compgen -G "$SHOTS/mm_play_*.png" > /dev/null; then
  cp "$SHOTS"/mm_play_*.png "$DEST/screens/"
  echo "   + Gameplay-Shots aus $SHOTS"
fi

echo "OK — Material liegt unter remotion/$DEST"

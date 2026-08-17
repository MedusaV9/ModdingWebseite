#!/usr/bin/env bash
# MONKEY MONEY — SVG/HTML → PNG per Headless-Chrome.
# Aufruf: render_svg.sh <eingabe.svg|.html> <ausgabe.png> <breite> <hoehe> [scale]
# SVGs werden in eine HTML-Hülle mit den lokalen Repo-Fonts eingebettet,
# damit font-family-Referenzen (Bungee/Bungee Shade/Rubik) korrekt rendern.
set -euo pipefail

IN="$1"
OUT="$2"
W="$3"
H="$4"
SCALE="${5:-1}"

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$IN" in
  *.svg)
    {
      echo '<!DOCTYPE html><html><head><meta charset="utf-8"><style>'
      echo "@font-face{font-family:'Bungee';src:url('file://$ROOT/assets/fonts/bungee.ttf')}"
      echo "@font-face{font-family:'Bungee Shade';src:url('file://$ROOT/assets/fonts/bungeeshade.ttf')}"
      echo "@font-face{font-family:'Rubik';src:url('file://$ROOT/assets/fonts/rubik.ttf')}"
      echo "html,body{margin:0;padding:0}svg{display:block;width:${W}px;height:${H}px}"
      echo '</style></head><body>'
      cat "$IN"
      echo '</body></html>'
    } >"$TMP/page.html"
    SRC="file://$TMP/page.html"
    ;;
  *)
    SRC="file://$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")"
    ;;
esac

/usr/bin/google-chrome-stable --headless=new --disable-gpu --no-sandbox \
  --disable-dev-shm-usage --allow-file-access-from-files \
  --user-data-dir="$TMP/profile" --hide-scrollbars \
  --force-device-scale-factor="$SCALE" \
  --default-background-color=00000000 \
  --window-size="$W,$H" --screenshot="$OUT" "$SRC" 2>/dev/null

echo "Gerendert: $OUT (${W}x${H} @ ${SCALE}x)"

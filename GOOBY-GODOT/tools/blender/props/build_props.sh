#!/usr/bin/env bash
# build_props.sh — EIN Einstieg für alle selbstgebauten WELT2-Home-Props
# (Muster: tools/blender/ranch/build_ranch.sh). Baut deterministisch alle
# GLBs nach assets/props/. Aufruf (beliebiges cwd):
#   GOOBY-GODOT/tools/blender/props/build_props.sh [nur_dieses_prop]

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_ROOT="$(cd "$DIR/../../.." && pwd)"
ASSETS="$GODOT_ROOT/assets/props"
BLENDER="${BLENDER:-blender}"
export PYTHONDONTWRITEBYTECODE=1

PROPS=(
    tuer_zarge tuer_blatt
    fenster_rahmen_1 fenster_rahmen_2 fenster_rahmen_3
    duschvorhang duschkopf
    heizkoerper lichtschalter steckdose bilderrahmen
    shed_l1 shed_l2 shed_l3 werkstatt gewaechshaus sprinkler
    werkbank sammel_stock sammel_blatt
    pflanze_tomate pflanze_chili pflanze_ananas
)
if [ "${1:-}" != "" ]; then
    PROPS=("$1")
fi

echo "== WELT2-Home-Props-Pipeline: $ASSETS =="
for p in "${PROPS[@]}"; do
    "$BLENDER" --background --factory-startup \
        --python "$DIR/build_home_props.py" -- \
        --prop "$p" --out "$ASSETS/$p.glb" \
        2>&1 | grep -E "\[(build_home_props|props_stil)\]|Error|Traceback" || true
done
# HINWEIS: `godot --import` extrahiert die eingebettete Palette-Textur als
# `<prop>_<objekt>_palette.png` neben das GLB — diese Dateien MÜSSEN
# eingecheckt bleiben (die importierte Szene referenziert sie).
echo "== FERTIG =="

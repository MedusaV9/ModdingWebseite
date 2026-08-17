#!/usr/bin/env bash
# build_ranch.sh — EIN Einstieg für alle selbstgebauten Gooby-Ranch-Assets
# (Muster: tools/blender/build_gooby.sh). Baut deterministisch:
#   Pferd + Fohlen (Rig + 9 Clips)   → assets/ranch/pferd/
#   Reh/Fuchs/Ente/Katze (Rig+Clips) → assets/ranch/tiere/*_gooby.glb
#   Hindernisse (3 Varianten)        → assets/ranch/hindernisse/
#   Sattel/Bürste/Trog/Heuballen     → assets/ranch/props/
#
# Aufruf (vom Repo-Root): GOOBY-GODOT/tools/blender/ranch/build_ranch.sh

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_ROOT="$(cd "$DIR/../../.." && pwd)"
ASSETS="$GODOT_ROOT/assets/ranch"
BLENDER="${BLENDER:-blender}"
export PYTHONDONTWRITEBYTECODE=1

run() {
    local script="$1"; shift
    "$BLENDER" --background --factory-startup --python "$DIR/$script" -- "$@" \
        2>&1 | grep -E "\[(build_|ranch_stil)|FEHLER" || true
}

echo "== Gooby-Ranch-Pipeline: $ASSETS =="
run build_pferd.py --out "$ASSETS/pferd/pferd.glb" --variante pferd
run build_pferd.py --out "$ASSETS/pferd/fohlen.glb" --variante fohlen
for t in reh fuchs ente katze; do
    run build_tier.py --tier "$t" --out "$ASSETS/tiere/${t}_gooby.glb"
done
for p in hindernis_a hindernis_b hindernis_c; do
    run build_props.py --prop "$p" --out "$ASSETS/hindernisse/$p.glb"
done
for p in sattel buerste trog heuballen; do
    run build_props.py --prop "$p" --out "$ASSETS/props/$p.glb"
done
echo "== FERTIG =="

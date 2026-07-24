#!/usr/bin/env bash
# build_gooby.sh — EIN Einstieg für die komplette Gooby-Charakter-Pipeline.
#
# Erzeugt deterministisch Mesh -> Rig/Shapekeys -> Animationen -> GLB:
#   tools/blender/gooby_build/build_mesh.py    (Stufe 1: Geometrie + Palette)
#   tools/blender/gooby_build/build_rig.py     (Stufe 2: Armature + Shapekeys)
#   tools/blender/gooby_build/build_anims.py   (Stufe 3: Clips als NLA-Tracks)
#   tools/blender/gooby_build/export_glb.py    (Stufe 4: GLB für Godot)
#
# Aufruf (vom Repo-Root):
#   tools/blender/build_gooby.sh [BUILD_DIR] [GLB_OUT]
# Default: BUILD_DIR=/tmp/gooby_build, GLB_OUT=GOOBY-GODOT/assets/character/gooby.glb

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPE_DIR="$REPO_ROOT/tools/blender/gooby_build"
BUILD_DIR="${1:-/tmp/gooby_build}"
GLB_OUT="${2:-$REPO_ROOT/GOOBY-GODOT/assets/character/gooby.glb}"
BLENDER="${BLENDER:-blender}"
export PYTHONDONTWRITEBYTECODE=1  # kein __pycache__ im Repo

mkdir -p "$BUILD_DIR"
echo "== Gooby-Pipeline: BUILD_DIR=$BUILD_DIR GLB_OUT=$GLB_OUT =="

run_stage() {
    local label="$1" script="$2"; shift 2
    echo "-- Stufe: $label"
    "$BLENDER" --background --factory-startup --python "$PIPE_DIR/$script" -- "$@" \
        2>&1 | grep -Ev "^(Blender|Read prefs|Info:|Fra:)" | sed 's/^/   /' || true
}

run_stage "Mesh"       build_mesh.py  --out "$BUILD_DIR/stage1_mesh.blend" \
                                      --palette "$BUILD_DIR/gooby_palette.png"
run_stage "Rig"        build_rig.py   --in "$BUILD_DIR/stage1_mesh.blend" \
                                      --out "$BUILD_DIR/stage2_rig.blend"
run_stage "Animationen" build_anims.py --in "$BUILD_DIR/stage2_rig.blend" \
                                      --out "$BUILD_DIR/stage3_anims.blend"
run_stage "GLB-Export" export_glb.py  --in "$BUILD_DIR/stage3_anims.blend" \
                                      --out "$GLB_OUT"

if [[ ! -s "$GLB_OUT" ]]; then
    echo "FEHLER: GLB wurde nicht erzeugt: $GLB_OUT" >&2
    exit 1
fi
echo "== FERTIG: $GLB_OUT ($(stat -c %s "$GLB_OUT") Bytes) =="

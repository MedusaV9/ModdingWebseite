#!/usr/bin/env python3
"""Umbral Pick — GeckoLib ITEM geo/anim/texture generator (POLISH3, MD4 §9 spec).

Hand-3D conversion of the W13 shard-shop pickaxe. The pixel icon
(`textures/item/umbral_pick.png`) stays FINAL for GUI/ground/fixed
(`neoforge:separate_transforms` routes those contexts to the sprite); this
script authors the 3D geo for FIRST/THIRD person.

Design (POLISH3 brief): the umbral_blade's material language on a mining tool —
ash-dark haft with a bone grip band, a twin-pronged head (fore/aft prongs whose
tips dip via their own bones), purple glow seams along the prong tops, a socketed
`glow_moon_gem` on the crown and a vein plane running up the haft.

13 bones / 12 cubes, 64x64 + glowmask.

Anims:
* `idle` (6 s loop) — haft vein + moon gem breathe, the two prong seams pulse in
  counter-phase, sub-degree head nod.
* `night_bite` (0.5 s one-shot, action controller) — prong tips snap down a few
  degrees and the seams/gem flash. Wired INSIDE `UmbralPickItem#mineBlock`
  (own class, no foreign-file edit): fires only when the block broke under an
  open night sky — exactly the condition of the +50 % break-speed buff
  (`ShardEconomy#onBreakSpeed`), throttled to the anim length.

Writes (all deterministic — reruns are byte-identical):
    src/main/resources/assets/eclipse/geo/item/umbral_pick.geo.json
    src/main/resources/assets/eclipse/animations/item/umbral_pick.animation.json
    src/main/resources/assets/eclipse/textures/item/umbral/umbral_pick.png + _glowmask.png

Run from the ProjectEclipse root:
    python3 scripts/geckolib_gen/items/umbral_pick.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, metal, mix, mul, wood  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "src/main/resources/assets/eclipse"
GEO = ASSETS / "geo/item/umbral_pick.geo.json"
ANIM = ASSETS / "animations/item/umbral_pick.animation.json"
OUT = ASSETS / "textures/item/umbral/umbral_pick.png"

SEED = 0x0B1A0E02  # "pick" — fixed, never change (byte-identical reruns)

# Same icon-derived palette as umbral_blade (shared material language):
NIGHT = hexc("#120B1E")
PURPLE_DEEP = hexc("#3A2860")
PURPLE_MID = hexc("#56378C")
GLOW = hexc("#7B4FD0")
GLOW_PALE = hexc("#CEB2FC")
WHITE_VIOLET = hexc("#EDE7F8")
STEEL_PALE = hexc("#D8CEC7")   # honed prong tips (icon pick-head highlight)
ASH_WOOD = hexc("#484037")     # icon haft
BONE_LIGHT = hexc("#C9BCA4")
BONE_DARK = hexc("#6E6254")


# ---------------------------------------------------------------------------
# geometry (GENERATED)
# ---------------------------------------------------------------------------

def build_geo():
    """13 bones: root → grip(+wrap) + glow_vein_h · collar · head_carrier →
    head_core · prong_f→prong_f_tip · prong_b→prong_b_tip · glow_seam_f/b ·
    glow_moon_gem. Prongs run fore/aft (±z) so the head sits in the swing
    plane when the display transform pitches the haft forward."""
    bones = [
        {"name": "root", "pivot": [0, 0, 0]},
        {"name": "grip", "parent": "root", "pivot": [0, 0, 0], "cubes": [
            {"origin": [-0.5, 0, -0.5], "size": [1, 12, 1], "uv": [0, 0]},
            # bone grip band (two-hand zone)
            {"origin": [-1, 3, -1], "size": [2, 2, 2], "inflate": -0.35, "uv": [6, 0]},
        ]},
        # emissive vein crawling up the haft front, floats 0.05 proud of the wood
        {"name": "glow_vein_h", "parent": "grip", "pivot": [0, 6, 0], "cubes": [
            {"origin": [-0.5, 6, 0.55], "size": [1, 6, 0], "uv": [22, 16]},
        ]},
        {"name": "collar", "parent": "root", "pivot": [0, 12, 0], "cubes": [
            {"origin": [-1, 11, -1], "size": [2, 2, 2], "inflate": -0.1, "uv": [16, 0]},
        ]},
        {"name": "head_carrier", "parent": "root", "pivot": [0, 13, 0]},
        {"name": "head_core", "parent": "head_carrier", "pivot": [0, 13, 0], "cubes": [
            {"origin": [-1, 12, -1.5], "size": [2, 2, 3], "uv": [26, 0]},
        ]},
        # Sign convention (MD3 §6.3 / chamber_lid precedent): positive X rotation
        # lifts the +z end and dips the -z end. The fore prong (-z) therefore
        # droops with +X, the aft prong (+z) with -X — a real pick's down-curve.
        {"name": "prong_f", "parent": "head_carrier", "pivot": [0, 13, -1.5],
         "rotation": [4, 0, 0], "cubes": [
            {"origin": [-1, 12, -5.5], "size": [2, 2, 4], "inflate": -0.12, "uv": [38, 0]},
        ]},
        {"name": "prong_f_tip", "parent": "prong_f", "pivot": [0, 13, -5.5],
         "rotation": [10, 0, 0], "cubes": [
            {"origin": [-0.5, 12.5, -7.5], "size": [1, 1, 2], "inflate": -0.08, "uv": [0, 16]},
        ]},
        {"name": "prong_b", "parent": "head_carrier", "pivot": [0, 13, 1.5],
         "rotation": [-4, 0, 0], "cubes": [
            {"origin": [-1, 12, 1.5], "size": [2, 2, 4], "inflate": -0.12, "uv": [50, 0]},
        ]},
        {"name": "prong_b_tip", "parent": "prong_b", "pivot": [0, 13, 5.5],
         "rotation": [-10, 0, 0], "cubes": [
            {"origin": [-0.5, 12.5, 5.5], "size": [1, 1, 2], "inflate": -0.08, "uv": [8, 16]},
        ]},
        # horizontal glow seams riding ON TOP of the prongs (h = 0 planes)
        {"name": "glow_seam_f", "parent": "prong_f", "pivot": [0, 14, -3.5], "cubes": [
            {"origin": [-0.5, 14.05, -5.5], "size": [1, 0, 4], "uv": [26, 16]},
        ]},
        {"name": "glow_seam_b", "parent": "prong_b", "pivot": [0, 14, 3.5], "cubes": [
            {"origin": [-0.5, 14.05, 1.5], "size": [1, 0, 4], "uv": [38, 16]},
        ]},
        {"name": "glow_moon_gem", "parent": "head_carrier", "pivot": [0, 14, 0], "cubes": [
            {"origin": [-0.5, 13.9, -0.5], "size": [1, 1, 1], "inflate": 0.16, "uv": [16, 16]},
        ]},
    ]
    return {
        "format_version": "1.12.0",
        "minecraft:geometry": [{
            "description": {
                "identifier": "geometry.umbral_pick",
                "texture_width": 64,
                "texture_height": 64,
                "visible_bounds_width": 2.5,
                "visible_bounds_height": 2.5,
                "visible_bounds_offset": [0, 0.5, 0],
            },
            "bones": bones,
        }],
    }


# ---------------------------------------------------------------------------
# animation (GENERATED)
# ---------------------------------------------------------------------------

Q = "query.anim_time"


def build_anim():
    idle = {
        "loop": True,
        "animation_length": 6.0,
        "bones": {
            "root": {
                "rotation": [0, 0, f"math.sin({Q} * 60) * 0.7"],
                "position": [0, f"math.sin({Q} * 120) * 0.08", 0],
            },
            "head_carrier": {"rotation": [f"math.sin({Q} * 60 + 60) * 0.6", 0, 0]},
            "glow_moon_gem": {"scale": [
                f"1 + math.sin({Q} * 120) * 0.14",
                f"1 + math.sin({Q} * 120) * 0.14",
                f"1 + math.sin({Q} * 120) * 0.14"]},
            "glow_vein_h": {"scale": [
                f"1 + math.sin({Q} * 120 - 30) * 0.2", "1", "1"]},
            # counter-phase seam pulses: the head "breathes" fore/aft
            "glow_seam_f": {"scale": [
                f"1 + math.sin({Q} * 120) * 0.25", "1", f"1 + math.sin({Q} * 120) * 0.12"]},
            "glow_seam_b": {"scale": [
                f"1 + math.sin({Q} * 120 + 180) * 0.25", "1",
                f"1 + math.sin({Q} * 120 + 180) * 0.12"]},
        },
    }
    night_bite = {
        "loop": False,
        "animation_length": 0.5,
        "bones": {
            "head_carrier": {"rotation": {
                "0.0": [0, 0, 0], "0.06": [-5, 0, 0], "0.16": [2, 0, 0],
                "0.3": [-1, 0, 0], "0.5": [0, 0, 0],
            }},
            # tips BITE DOWN (fore = +X dips -z, aft = -X dips +z), then recoil
            "prong_f_tip": {"rotation": {
                "0.0": [0, 0, 0], "0.08": [9, 0, 0], "0.2": [-3, 0, 0],
                "0.5": [0, 0, 0],
            }},
            "prong_b_tip": {"rotation": {
                "0.0": [0, 0, 0], "0.08": [-9, 0, 0], "0.2": [3, 0, 0],
                "0.5": [0, 0, 0],
            }},
            "glow_seam_f": {"scale": {
                "0.0": [1, 1, 1], "0.08": [1.7, 1, 1.7], "0.2": [1.15, 1, 1.15],
                "0.35": [1.4, 1, 1.4], "0.5": [1, 1, 1],
            }},
            "glow_seam_b": {"scale": {
                "0.0": [1, 1, 1], "0.08": [1.7, 1, 1.7], "0.2": [1.15, 1, 1.15],
                "0.35": [1.4, 1, 1.4], "0.5": [1, 1, 1],
            }},
            "glow_moon_gem": {"scale": {
                "0.0": [1, 1, 1], "0.07": [1.8, 1.8, 1.8], "0.18": [0.9, 0.9, 0.9],
                "0.32": [1.25, 1.25, 1.25], "0.5": [1, 1, 1],
            }},
        },
    }
    return {
        "format_version": "1.8.0",
        "animations": {
            "animation.umbral_pick.idle": idle,
            "animation.umbral_pick.night_bite": night_bite,
        },
    }


# ---------------------------------------------------------------------------
# texture painting
# ---------------------------------------------------------------------------

def bone_band(px):
    """Carved bone grip band with lathe rings (blade-hilt language)."""
    ring = (px.gy + 1) % 3 == 0
    col = mix(BONE_LIGHT, BONE_DARK, 0.55 if ring else 0.12)
    return mul(col, 0.92 + px.noise(19) * 0.2)


def umbral_head(salt):
    """Prong/head steel: near-black violet metal, pale honed ridge on the top
    edge of side faces (the working edge catches moonlight)."""
    base_fn = metal(mix(NIGHT, PURPLE_DEEP, 0.55), salt=salt)

    def fn(px):
        col = base_fn(px)
        if px.face in ("north", "south", "east", "west") and px.fy == 0:
            col = mix(col, STEEL_PALE, 0.4)
        return col
    return fn


def tip_steel(px):
    """Honed tips: pale steel darkening toward the point via violet."""
    col = mul(STEEL_PALE, 0.85 + px.noise(23) * 0.25)
    return mix(col, PURPLE_MID, 0.25)


def seam_glow(px):
    """Emissive seam strip: dashed pale-violet light (broken vein, not a lamp)."""
    if px.noise(29) > 0.82:
        return None  # seam gap
    return mix(GLOW_PALE, GLOW, 0.3 + px.noise(37) * 0.4)


seam_glow.shadeless = True


def haft_vein(px):
    """Emissive haft vein plane: single wandering column like the blade veins."""
    if px.noise(43) > 0.85:
        return None
    return mix(GLOW, GLOW_PALE, 0.25 + px.noise(47) * 0.3)


haft_vein.shadeless = True


def main():
    GEO.parent.mkdir(parents=True, exist_ok=True)
    GEO.write_text(json.dumps(build_geo(), indent=1) + "\n")
    ANIM.parent.mkdir(parents=True, exist_ok=True)
    ANIM.write_text(json.dumps(build_anim(), indent=1) + "\n")

    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("grip", wood(ASH_WOOD, salt=11))
    painter.set_cube_material("grip", 1, bone_band)
    painter.set_material("collar", umbral_head(salt=13))
    painter.set_material("head_core", umbral_head(salt=17))
    painter.set_material("prong_f", umbral_head(salt=31))
    painter.set_material("prong_b", umbral_head(salt=41))
    painter.set_material("prong_*_tip", tip_steel)
    painter.set_material("glow_seam_*", seam_glow)
    painter.set_material("glow_vein_h", haft_vein)
    painter.set_material("glow_moon_gem", flame(WHITE_VIOLET, GLOW, salt=53))
    painter.paint(OUT)


if __name__ == "__main__":
    main()

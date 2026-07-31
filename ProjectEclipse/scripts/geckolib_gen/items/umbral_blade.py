#!/usr/bin/env python3
"""Umbral Blade — GeckoLib ITEM geo/anim/texture generator (POLISH3, MD4 §9 spec).

Hand-3D conversion of the W13 shard-shop sword: the pixel icon
(`textures/item/umbral_blade.png`) stays the FINAL art for GUI/ground/fixed
(AGENTS.md law — the model JSON routes those contexts back to the 2D sprite via
`neoforge:separate_transforms`); this script authors the 3D geo that FIRST/THIRD
person hands get.

Design (MD4 §9.2, POLISH3 brief): a dark umbral shortsword with a SLIGHT CURVE —
the blade is split into three stacked segments (`blade_root` → `blade_mid` →
`blade_tip`) whose static z-rest-rotations bend the silhouette away from every
straight vanilla sword. Purple vein glow lives in the blade segments' GLOWMASK
pixels (branching vein walk, deterministic), the cutting-edge aura in three
zero-depth `glow_edge_*` planes that stick out past the edge, and the pommel
carries a lidless `glow_eye`. Two `wisp_*` shadow pennants at the guard rest at
scale 0 (MD3 storm_heart law) and only flicker alive in `idle` / flare in `feast`.

14 bones / 15 cubes, 64x64 + glowmask. GeckoLib sign conventions per
MD3_ITEMSB_REPORT.md §6.3 (rest rotation Z is applied as-is; molang and numeric
keyframes behave identically).

Anims:
* `idle` (6 s loop) — edge-glow breathing travelling tip-ward (per-segment phase
  offset), pommel-eye pulse, sub-degree curve "breathing" on the blade segments,
  two wisp flickers (keyframed, start == end == scale 0 for a clean loop seam).
* `feast` (1.2 s one-shot, action controller) — pommel eye dilates, edge flames,
  wisps flag out, blade whips; ends in rest. Trigger:
  `UmbralBladeItem.triggerFeast(ServerPlayer)` (waits for the LifecycleEvents
  owner, MD3-`triggerShatter` pattern — NOT wired by POLISH3).

Writes (all deterministic — reruns are byte-identical):
    src/main/resources/assets/eclipse/geo/item/umbral_blade.geo.json
    src/main/resources/assets/eclipse/animations/item/umbral_blade.animation.json
    src/main/resources/assets/eclipse/textures/item/umbral/umbral_blade.png + _glowmask.png

Run from the ProjectEclipse root:
    python3 scripts/geckolib_gen/items/umbral_blade.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, metal, mix, mul, weave, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "src/main/resources/assets/eclipse"
GEO = ASSETS / "geo/item/umbral_blade.geo.json"
ANIM = ASSETS / "animations/item/umbral_blade.animation.json"
OUT = ASSETS / "textures/item/umbral/umbral_blade.png"

SEED = 0x0B1A0E01  # "blade" — fixed, never change (byte-identical reruns)

# Palette lifted from the FINAL 16x16 icon (art-language continuity):
NIGHT = hexc("#120B1E")        # umbral near-black
PURPLE_DEEP = hexc("#3A2860")  # dark violet steel
PURPLE_MID = hexc("#56378C")
GLOW = hexc("#7B4FD0")         # vein glow
GLOW_PALE = hexc("#CEB2FC")
WHITE_VIOLET = hexc("#EDE7F8")
BONE_LIGHT = hexc("#C9BCA4")   # hilt bone/ivory
BONE_DARK = hexc("#6E6254")


# ---------------------------------------------------------------------------
# geometry (GENERATED — the geo json is written by this script, never by hand)
# ---------------------------------------------------------------------------

def build_geo():
    """14 bones: root → grip(+wrap) → pommel → glow_eye · guard(+horns) ·
    blade_carrier → blade_root → blade_mid → blade_tip (static z-curve 0°/5°/7°),
    glow_edge_a/b/c aura planes past the cutting edge, wisp_a/b pennants."""
    bones = [
        {"name": "root", "pivot": [0, 0, 0]},
        {"name": "grip", "parent": "root", "pivot": [0, 2, 0], "cubes": [
            # hilt column + leather mid-wrap
            {"origin": [-0.5, 2, -0.5], "size": [1, 5, 1], "uv": [0, 0]},
            {"origin": [-1, 4, -1], "size": [2, 1, 2], "inflate": -0.15, "uv": [8, 0]},
        ]},
        {"name": "pommel", "parent": "grip", "pivot": [0, 2, 0], "cubes": [
            {"origin": [-1, 0, -1], "size": [2, 2, 2], "uv": [16, 0]},
        ]},
        {"name": "glow_eye", "parent": "pommel", "pivot": [0, 1, 0], "cubes": [
            # slightly proud of the pommel on every side -> visible glowing iris ring
            {"origin": [-0.5, 0.5, -0.5], "size": [1, 1, 1], "inflate": 0.18, "uv": [26, 0]},
        ]},
        {"name": "guard", "parent": "root", "pivot": [0, 7, 0], "cubes": [
            {"origin": [-3, 7, -1], "size": [6, 1, 2], "uv": [32, 0]},
            # up-and-OUTWARD-swept horn tips (+z rotation leans a cube's top toward
            # -x): crescent guard silhouette, distinct from every straight vanilla bar
            {"origin": [-3.5, 7.5, -1], "size": [1, 2, 2], "inflate": -0.1,
             "rotation": [0, 0, 28], "pivot": [-2.5, 8, 0], "uv": [0, 8]},
            {"origin": [2.5, 7.5, -1], "size": [1, 2, 2], "inflate": -0.1,
             "rotation": [0, 0, -28], "pivot": [2.5, 8, 0], "uv": [8, 8]},
        ]},
        {"name": "blade_carrier", "parent": "root", "pivot": [0, 8, 0]},
        {"name": "blade_root", "parent": "blade_carrier", "pivot": [0, 8, 0], "cubes": [
            {"origin": [-1, 8, -0.5], "size": [2, 6, 1], "uv": [16, 8]},
        ]},
        # static z-rest-rotations = the curve (MD3 §6.1: static tilt and animated
        # motion never share a bone — the micro "breath" rides ON these rests).
        {"name": "blade_mid", "parent": "blade_root", "pivot": [0, 14, 0],
         "rotation": [0, 0, 5], "cubes": [
            {"origin": [-1, 14, -0.5], "size": [2, 5, 1], "inflate": -0.08, "uv": [24, 8]},
        ]},
        {"name": "blade_tip", "parent": "blade_mid", "pivot": [0, 19, 0],
         "rotation": [0, 0, 7], "cubes": [
            {"origin": [-1, 19, -0.5], "size": [2, 2, 1], "inflate": -0.16, "uv": [32, 8]},
            # back-swept point on the cutting-edge side
            {"origin": [-1, 21, -0.5], "size": [1, 2, 1], "inflate": -0.24, "uv": [40, 8]},
        ]},
        # zero-depth aura planes: the inner half hides inside the blade, the outer
        # half sticks past the cutting edge (-x) as free-floating glow
        {"name": "glow_edge_a", "parent": "blade_root", "pivot": [0, 8, 0], "cubes": [
            {"origin": [-1.75, 8.5, 0], "size": [1, 5, 0], "uv": [46, 8]},
        ]},
        {"name": "glow_edge_b", "parent": "blade_mid", "pivot": [0, 14, 0], "cubes": [
            {"origin": [-1.7, 14, 0], "size": [1, 5, 0], "uv": [50, 8]},
        ]},
        {"name": "glow_edge_c", "parent": "blade_tip", "pivot": [0, 19, 0], "cubes": [
            {"origin": [-1.6, 19, 0], "size": [1, 3, 0], "uv": [54, 8]},
        ]},
        # shadow pennants (rest scale 0 via idle anim — MD3 storm_heart law)
        {"name": "wisp_a", "parent": "guard", "pivot": [-3, 8, 0], "cubes": [
            {"origin": [-5, 7, 0], "size": [2, 2, 0], "uv": [0, 16]},
        ]},
        {"name": "wisp_b", "parent": "guard", "pivot": [3, 8, 0], "cubes": [
            {"origin": [3, 7, 0], "size": [2, 2, 0], "uv": [6, 16]},
        ]},
    ]
    return {
        "format_version": "1.12.0",
        "minecraft:geometry": [{
            "description": {
                "identifier": "geometry.umbral_blade",
                "texture_width": 64,
                "texture_height": 64,
                "visible_bounds_width": 3,
                "visible_bounds_height": 3,
                "visible_bounds_offset": [0, 0.75, 0],
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
            # 360°/6 s molang sines -> perfect loop seam (MD4 §9.2 law)
            "root": {
                "rotation": [0, 0, f"math.sin({Q} * 60) * 0.8"],
                "position": [0, f"math.sin({Q} * 120) * 0.1", 0],
            },
            "blade_root": {"rotation": [0, 0, f"math.sin({Q} * 60) * 0.4"]},
            "blade_mid": {"rotation": [0, 0, f"math.sin({Q} * 60 - 25) * 0.55"]},
            "blade_tip": {"rotation": [0, 0, f"math.sin({Q} * 60 - 50) * 0.75"]},
            # glow breath travels tip-ward (per-segment phase offset)
            "glow_edge_a": {"scale": [
                f"1 + math.sin({Q} * 120) * 0.22", "1", f"1 + math.sin({Q} * 120) * 0.22"]},
            "glow_edge_b": {"scale": [
                f"1 + math.sin({Q} * 120 - 40) * 0.22", "1", f"1 + math.sin({Q} * 120 - 40) * 0.22"]},
            "glow_edge_c": {"scale": [
                f"1 + math.sin({Q} * 120 - 80) * 0.26", "1", f"1 + math.sin({Q} * 120 - 80) * 0.26"]},
            "glow_eye": {"scale": [
                f"1 + math.sin({Q} * 120 + 90) * 0.12",
                f"1 + math.sin({Q} * 120 + 90) * 0.12",
                f"1 + math.sin({Q} * 120 + 90) * 0.12"]},
            # two shadow flickers per loop; scale 0 at 0.0 AND 6.0 = seamless
            "wisp_a": {
                "scale": {
                    "0.0": [0, 0, 0], "2.5": [0, 0, 0],
                    "2.62": [1.1, 1, 1.1], "2.86": [0.7, 0.95, 0.7],
                    "3.05": [0.95, 1, 0.95], "3.3": [0, 0, 0], "6.0": [0, 0, 0],
                },
                "rotation": {
                    "0.0": [0, 0, 0], "2.5": [0, 0, 0], "2.7": [0, 0, -14],
                    "2.95": [0, 0, -4], "3.3": [0, 0, 0], "6.0": [0, 0, 0],
                },
            },
            "wisp_b": {
                "scale": {
                    "0.0": [0, 0, 0], "4.9": [0, 0, 0],
                    "5.02": [1.1, 1, 1.1], "5.26": [0.7, 0.95, 0.7],
                    "5.45": [0.95, 1, 0.95], "5.7": [0, 0, 0], "6.0": [0, 0, 0],
                },
                "rotation": {
                    "0.0": [0, 0, 0], "4.9": [0, 0, 0], "5.1": [0, 0, 14],
                    "5.35": [0, 0, 4], "5.7": [0, 0, 0], "6.0": [0, 0, 0],
                },
            },
        },
    }
    feast = {
        "loop": False,
        "animation_length": 1.2,
        "bones": {
            "root": {
                "rotation": {
                    "0.0": [0, 0, 0], "0.1": [-4, 0, -6],
                    "0.28": {"post": [2, 0, 4], "lerp_mode": "catmullrom"},
                    "0.5": [-1, 0, -1.5], "1.2": [0, 0, 0],
                },
                "position": {
                    "0.0": [0, 0, 0], "0.1": [0, -0.5, 0],
                    "0.3": [0, 0.25, 0], "1.2": [0, 0, 0],
                },
            },
            "glow_eye": {"scale": {
                "0.0": [1, 1, 1], "0.12": [2.1, 2.1, 2.1], "0.3": [0.85, 0.85, 0.85],
                "0.55": [1.35, 1.35, 1.35], "1.2": [1, 1, 1],
            }},
            "glow_edge_a": {"scale": {
                "0.0": [1, 1, 1], "0.1": [2.4, 1.15, 2.4], "0.4": [1.3, 1.02, 1.3],
                "1.2": [1, 1, 1],
            }},
            "glow_edge_b": {"scale": {
                "0.0": [1, 1, 1], "0.16": [2.4, 1.15, 2.4], "0.46": [1.3, 1.02, 1.3],
                "1.2": [1, 1, 1],
            }},
            "glow_edge_c": {"scale": {
                "0.0": [1, 1, 1], "0.22": [2.6, 1.2, 2.6], "0.52": [1.35, 1.02, 1.35],
                "1.2": [1, 1, 1],
            }},
            "blade_mid": {"rotation": {
                "0.0": [0, 0, 0], "0.12": [0, 0, 4], "0.3": [0, 0, -2],
                "0.6": [0, 0, 1], "1.2": [0, 0, 0],
            }},
            "blade_tip": {"rotation": {
                "0.0": [0, 0, 0], "0.16": [0, 0, 6], "0.36": [0, 0, -3],
                "0.66": [0, 0, 1.5], "1.2": [0, 0, 0],
            }},
            "wisp_a": {"scale": {
                "0.0": [0, 0, 0], "0.15": [1.25, 1.1, 1.25], "0.6": [1, 1, 1],
                "0.9": [0.9, 1, 0.9], "1.2": [0, 0, 0],
            }},
            "wisp_b": {"scale": {
                "0.0": [0, 0, 0], "0.18": [1.25, 1.1, 1.25], "0.63": [1, 1, 1],
                "0.93": [0.9, 1, 0.9], "1.2": [0, 0, 0],
            }},
        },
    }
    return {
        "format_version": "1.8.0",
        "animations": {
            "animation.umbral_blade.idle": idle,
            "animation.umbral_blade.feast": feast,
        },
    }


# ---------------------------------------------------------------------------
# texture painting
# ---------------------------------------------------------------------------

def vein_intensity(px, salt):
    """Deterministic branching vein mask on a blade-face pixel, 0..1.

    A wandering center column (per-row noise keyed on GLOBAL y so segments stay
    coherent) with occasional 1px side branches. Shared by the albedo material
    (dark violet inlay) and the glow painter (bright emissive) so both stay
    perfectly aligned."""
    if px.face not in ("north", "south"):
        return 0.0
    wander = int(px.noise(salt, x=0, y=px.gy) * 3) - 1  # -1 / 0 / 1
    center = px.fw // 2 + wander
    if px.fx == center:
        return 1.0
    if abs(px.fx - center) == 1 and px.noise(salt + 7) > 0.72:
        return 0.55  # side branch
    return 0.0


def blade_steel(salt):
    """Dark umbral blade steel. The 1px-wide WEST face (-x) is the honed cutting
    edge (pale catch-light), the EAST spine stays darkest, and the 2px-wide
    flats carry a subtle violet bevel plus the vein inlay."""
    def fn(px):
        base = mix(NIGHT, PURPLE_DEEP, 0.45)
        col = mul(base, 0.9 + px.noise(salt) * 0.25)
        if px.face == "west":       # cutting edge
            col = mix(col, WHITE_VIOLET, 0.5)
        elif px.face == "east":     # spine
            col = mul(col, 0.72)
        elif px.face in ("north", "south"):
            if px.fx == 0 or px.fx == px.fw - 1:
                col = mix(col, PURPLE_MID, 0.32)  # side bevel
            v = vein_intensity(px, salt)
            if v > 0:
                col = mix(col, GLOW, 0.35 + 0.3 * v)
        return col
    return fn


def blade_vein_glow(salt):
    """Glowmask for the blade segments: ONLY the veins emit (runs instead of
    nothing — blade bones are not glow_-prefixed, so without this they stay
    dark)."""
    def fn(px):
        v = vein_intensity(px, salt)
        if v <= 0:
            return None
        r, g, b, _ = mix(GLOW, GLOW_PALE, 0.35 * v)
        return (r, g, b, int(90 + 120 * v))
    return fn


def edge_aura(px):
    """Emissive cutting-edge aura plane (1 px wide strip): pale core with ragged
    flame gaps, cooling toward the strip's far end."""
    if px.noise(31) > 0.88:
        return None  # ragged flame gap
    t = px.fy / max(px.fh - 1, 1) if px.fh > 1 else 0.0
    col = mix(GLOW_PALE, GLOW, 0.35 + 0.4 * t)
    return with_alpha(col, 235)


edge_aura.shadeless = True


def wisp_cloth(px):
    """Shadow pennant: near-black weave with a ragged free edge and violet hem."""
    n = px.noise(41, x=px.gx, y=0)
    cut = 0 if n < 0.4 else (1 if n < 0.8 else 2)
    if px.fy >= px.fh - cut and px.fh > 1:
        return None
    col = mul(NIGHT, 0.95 + px.noise(43) * 0.3)
    if px.fy == px.fh - 1:
        col = mix(col, PURPLE_MID, 0.4)
    return col


def hilt_bone(px):
    """Carved bone/ivory grip (icon language): pale with darker lathe rings."""
    ring = (px.gy + 1) % 3 == 0
    col = mix(BONE_LIGHT, BONE_DARK, 0.55 if ring else 0.12)
    return mul(col, 0.92 + px.noise(47) * 0.2)


def guard_iron(px):
    """Umbral guard iron: violet-black metal, pale top catch-light."""
    col = metal(mix(NIGHT, PURPLE_DEEP, 0.6), salt=53)(px)
    if px.face in ("north", "south", "east", "west") and px.fy == 0:
        col = mix(col, GLOW_PALE, 0.3)
    return col


def main():
    GEO.parent.mkdir(parents=True, exist_ok=True)
    GEO.write_text(json.dumps(build_geo(), indent=1) + "\n")
    ANIM.parent.mkdir(parents=True, exist_ok=True)
    ANIM.write_text(json.dumps(build_anim(), indent=1) + "\n")

    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("grip", hilt_bone)
    painter.set_cube_material("grip", 1, weave(mix(NIGHT, PURPLE_DEEP, 0.3), direction=2, salt=57))
    painter.set_material("pommel", guard_iron)
    painter.set_material("guard", guard_iron)
    painter.set_material("blade_*", blade_steel(salt=11))
    painter.set_material("glow_eye", flame(WHITE_VIOLET, GLOW, salt=17))
    painter.set_material("glow_edge_*", edge_aura)
    painter.set_material("wisp_*", wisp_cloth)
    # veins: blade bones are non-glow_, so the emissive veins need explicit painters
    painter.set_glow_painter("blade_root", blade_vein_glow(salt=11))
    painter.set_glow_painter("blade_mid", blade_vein_glow(salt=11))
    painter.set_glow_painter("blade_tip", blade_vein_glow(salt=11))
    painter.paint(OUT)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Ferryman's Toll — GeckoLib ITEM geo/anim/texture generator (POLISH3, MD4 §9).

Hand-3D conversion of the day-14 finale trophy. The pixel icon
(`textures/item/ferryman_toll.png`) stays FINAL for GUI/ground/fixed
(`neoforge:separate_transforms`); in FIRST/THIRD person the toll becomes a
large spectral coin hovering over the holder's fist.

Design (POLISH3 brief): an octagonal verdigris-bronze coin (two crossed slabs),
a raised lantern boss in the center, a STRONG emissive rim (four glow band
segments hugging the edge, proud of both faces), and per-face 16x16 emissive
motifs — the Ferryman's barge on the obverse, his lantern on the reverse
(per-face UV at 2 texels per geo unit, so the engraving is finer than the
geometry). Two tiny obol glyphs orbit the coin on a counter-tilted halo.

Precession per the MD3 §6.1 law: the static 10° plane tilt lives on `tilt`,
the 360°/8 s spin on its child `spin` — the coin runs true in its tilted plane
while `tilt` adds a slow molang wobble on top (the actual precession).

12 bones / 11 cubes, 64x64 + glowmask (spectral teal — the icon's palette,
deliberately NOT the umbral purple: this is Ferryman currency, not shard-shop
steel).

Anims:
* `idle` (8 s loop) — coin spin 360°, halo counter-spin −360°, tilt wobble,
  float bob, rim/motif glow breathing, obol counter-bob.
* `present` (2.0 s one-shot, action controller) — the hand-over moment (MD4):
  the coin rises, its tilt rights itself to level, it flips 180° to PRESENT the
  lantern reverse, holds the reveal, then flips back and settles. All channels
  end at rest — no controller-handback unwind. Trigger: server-side
  `GeoItem#triggerAnim` from `FerrymanTollItem#use` (throttled).

Writes (all deterministic — reruns are byte-identical):
    src/main/resources/assets/eclipse/geo/item/ferryman_toll.geo.json
    src/main/resources/assets/eclipse/animations/item/ferryman_toll.animation.json
    src/main/resources/assets/eclipse/textures/item/toll/ferryman_toll.png + _glowmask.png

Run from the ProjectEclipse root:
    python3 scripts/geckolib_gen/items/ferryman_toll.py
"""

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, metal, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "src/main/resources/assets/eclipse"
GEO = ASSETS / "geo/item/ferryman_toll.geo.json"
ANIM = ASSETS / "animations/item/ferryman_toll.animation.json"
OUT = ASSETS / "textures/item/toll/ferryman_toll.png"

SEED = 0x0B1A0E03  # "toll" — fixed, never change (byte-identical reruns)

# Palette from the FINAL 16x16 icon (spectral verdigris + teal glow):
NIGHT = hexc("#120B1E")
VERDIGRIS = hexc("#4A6A5C")
VERDIGRIS_DEEP = hexc("#2C4238")
VERDIGRIS_SHADOW = hexc("#1D2B24")
SILVER = hexc("#8E9E9D")
GLOW_TEAL = hexc("#8FF2DE")
WHITE_VIOLET = hexc("#F7F0FF")


# ---------------------------------------------------------------------------
# geometry (GENERATED)
# ---------------------------------------------------------------------------

def build_geo():
    """12 bones: root → tilt (static 10° x) → spin → disc (octagon, 2 cubes) →
    emboss boss · glow_face_f/b (16x16 per-face-UV motif planes) · glow_rim
    (4 edge bands) — plus halo → halo_spin → glow_obol_a/b orbiters."""
    bones = [
        {"name": "root", "pivot": [0, 0, 0]},
        # static plane tilt — NEVER animate spin here (MD3 §6.1 precession law)
        {"name": "tilt", "parent": "root", "pivot": [0, 5, 0], "rotation": [10, 0, 0]},
        {"name": "spin", "parent": "tilt", "pivot": [0, 5, 0]},
        {"name": "disc", "parent": "spin", "pivot": [0, 5, 0], "cubes": [
            # two crossed slabs = octagonal coin, diameter 8, thickness 1
            {"origin": [-3, 1, -0.5], "size": [6, 8, 1], "uv": [0, 0]},
            {"origin": [-4, 2, -0.5], "size": [8, 6, 1], "uv": [16, 0]},
        ]},
        {"name": "emboss", "parent": "disc", "pivot": [0, 5, 0], "cubes": [
            # raised lantern boss, proud of both faces (2^3 shrunk to ~1.4 deep)
            {"origin": [-1, 4, -1], "size": [2, 2, 2], "inflate": -0.3, "uv": [36, 0]},
        ]},
        # engraving planes: 8x8 geo faces mapped onto 16x16 texture rects
        # (per-face UV, 2 texels per unit) — only the OUTWARD face of each plane
        # is declared, the inward one presses against the disc anyway
        {"name": "glow_face_f", "parent": "disc", "pivot": [0, 5, 0], "cubes": [
            {"origin": [-4, 1, 0.55], "size": [8, 8, 0],
             "uv": {"south": {"uv": [32, 16], "uv_size": [16, 16]}}},
        ]},
        {"name": "glow_face_b", "parent": "disc", "pivot": [0, 5, 0], "cubes": [
            {"origin": [-4, 1, -0.55], "size": [8, 8, 0],
             "uv": {"north": {"uv": [48, 16], "uv_size": [16, 16]}}},
        ]},
        {"name": "glow_rim", "parent": "disc", "pivot": [0, 5, 0], "cubes": [
            # four bands hugging the octagon edge, inflated proud of both faces
            {"origin": [-3, 8, -0.5], "size": [6, 1, 1], "inflate": 0.15, "uv": [46, 0]},
            {"origin": [-3, 1, -0.5], "size": [6, 1, 1], "inflate": 0.15, "uv": [0, 12]},
            {"origin": [-4, 2, -0.5], "size": [1, 6, 1], "inflate": 0.15, "uv": [16, 10]},
            {"origin": [3, 2, -0.5], "size": [1, 6, 1], "inflate": 0.15, "uv": [24, 10]},
        ]},
        # obol halo: counter-tilted carrier, spin on the CHILD (precession law)
        {"name": "halo", "parent": "root", "pivot": [0, 5, 0], "rotation": [18, 0, 0]},
        {"name": "halo_spin", "parent": "halo", "pivot": [0, 5, 0]},
        {"name": "glow_obol_a", "parent": "halo_spin", "pivot": [0, 5, 0], "cubes": [
            {"origin": [-0.5, 4.5, 5.5], "size": [1, 1, 1], "inflate": -0.15, "uv": [32, 8]},
        ]},
        {"name": "glow_obol_b", "parent": "halo_spin", "pivot": [0, 5, 0], "cubes": [
            {"origin": [-0.5, 4.5, -6.5], "size": [1, 1, 1], "inflate": -0.15, "uv": [40, 8]},
        ]},
    ]
    return {
        "format_version": "1.12.0",
        "minecraft:geometry": [{
            "description": {
                "identifier": "geometry.ferryman_toll",
                "texture_width": 64,
                "texture_height": 64,
                "visible_bounds_width": 2.5,
                "visible_bounds_height": 2,
                "visible_bounds_offset": [0, 0.4, 0],
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
        "animation_length": 8.0,
        "bones": {
            "root": {"position": [0, f"math.sin({Q} * 90) * 0.25", 0]},
            # slow wobble ON TOP of the static 10° rest = visible precession
            "tilt": {"rotation": [
                f"math.sin({Q} * 45) * 2.5", 0, f"math.cos({Q} * 45) * 2.5"]},
            # 360°/8 s — linear keyframes, seamless loop
            "spin": {"rotation": {"0.0": [0, 0, 0], "8.0": [0, 360, 0]}},
            "halo_spin": {"rotation": {"0.0": [0, 0, 0], "8.0": [0, -360, 0]}},
            "glow_rim": {"scale": [
                f"1 + math.sin({Q} * 90) * 0.05",
                f"1 + math.sin({Q} * 90) * 0.05",
                f"1 + math.sin({Q} * 90) * 0.05"]},
            "glow_face_f": {"scale": [
                f"1 + math.sin({Q} * 45) * 0.04", f"1 + math.sin({Q} * 45) * 0.04", "1"]},
            "glow_face_b": {"scale": [
                f"1 + math.sin({Q} * 45 + 180) * 0.04",
                f"1 + math.sin({Q} * 45 + 180) * 0.04", "1"]},
            "glow_obol_a": {
                "position": [0, f"math.sin({Q} * 90 + 90) * 0.3", 0],
                "scale": [
                    f"1 + math.sin({Q} * 180) * 0.1", f"1 + math.sin({Q} * 180) * 0.1",
                    f"1 + math.sin({Q} * 180) * 0.1"],
            },
            "glow_obol_b": {
                "position": [0, f"math.sin({Q} * 90 - 90) * 0.3", 0],
                "scale": [
                    f"1 + math.sin({Q} * 180 + 180) * 0.1",
                    f"1 + math.sin({Q} * 180 + 180) * 0.1",
                    f"1 + math.sin({Q} * 180 + 180) * 0.1"],
            },
        },
    }
    # The hand-over: rise, right the plane, flip 180° (lantern reverse shown),
    # hold the reveal, flip BACK and settle. Ending every channel at rest avoids
    # the 360°→0° controller-handback unwind a full-turn flip would cause.
    present = {
        "loop": False,
        "animation_length": 2.0,
        "bones": {
            "root": {"position": {
                "0.0": [0, 0, 0],
                "0.35": {"post": [0, 3, 0], "lerp_mode": "catmullrom"},
                "0.9": [0, 2.6, 0], "1.5": [0, 0.4, 0], "2.0": [0, 0, 0],
            }},
            # cancels the static 10° rest → the coin levels for the ceremony
            "tilt": {"rotation": {
                "0.0": [0, 0, 0], "0.3": [-10, 0, 0], "1.4": [-10, 0, 0],
                "2.0": [0, 0, 0],
            }},
            "disc": {"rotation": {
                "0.0": [0, 0, 0],
                "0.2": [-24, 0, 0],
                "0.55": {"post": [186, 0, 0], "lerp_mode": "catmullrom"},
                "0.75": [178, 0, 0],
                "0.85": [180, 0, 0],
                "1.25": [180, 0, 0],
                "1.45": [196, 0, 0],
                "1.8": {"post": [-6, 0, 0], "lerp_mode": "catmullrom"},
                "2.0": [0, 0, 0],
            }},
            "glow_rim": {"scale": {
                "0.0": [1, 1, 1], "0.4": [1.3, 1.3, 1.3], "0.9": [1.18, 1.18, 1.18],
                "1.3": [1.3, 1.3, 1.3], "2.0": [1, 1, 1],
            }},
            "glow_obol_a": {"scale": {
                "0.0": [1, 1, 1], "0.35": [1.6, 1.6, 1.6], "1.3": [1.35, 1.35, 1.35],
                "2.0": [1, 1, 1],
            }},
            "glow_obol_b": {"scale": {
                "0.0": [1, 1, 1], "0.4": [1.6, 1.6, 1.6], "1.35": [1.35, 1.35, 1.35],
                "2.0": [1, 1, 1],
            }},
            "emboss": {"scale": {
                "0.0": [1, 1, 1], "0.6": [1, 1, 1.3], "1.2": [1, 1, 1.15],
                "2.0": [1, 1, 1],
            }},
        },
    }
    return {
        "format_version": "1.8.0",
        "animations": {
            "animation.ferryman_toll.idle": idle,
            "animation.ferryman_toll.present": present,
        },
    }


# ---------------------------------------------------------------------------
# texture painting — motif helpers (16x16 per-face grids)
# ---------------------------------------------------------------------------

def _ring_dist(px):
    """Distance of a 16x16 face pixel from the face center, in pixel units."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    return math.hypot(px.fx - cx, px.fy - cy)


def _barge_pixel(px):
    """Ferry-barge engraving on a 16x16 grid: hull arc, prow lantern pole, three
    soul passengers, waterline dashes. Returns intensity 0..1 or 0."""
    x, y = px.fx, px.fy
    # hull: shallow arc rows 9-10, columns 3..12
    if y in (9, 10) and 3 <= x <= 12 and not (y == 10 and (x < 4 or x > 11)):
        return 1.0
    # waterline dashes under the hull
    if y == 12 and x % 3 == 1 and 2 <= x <= 13:
        return 0.45
    # prow pole + hanging lantern (right side)
    if x == 12 and 5 <= y <= 8:
        return 0.8
    if x == 11 and y == 4:
        return 1.0
    # three hunched souls on the deck
    if y == 8 and x in (4, 6, 8):
        return 0.7
    if y == 7 and x in (4, 6, 8):
        return 0.5
    return 0.0


def _lantern_pixel(px):
    """Ferryman's lantern engraving on a 16x16 grid: cage, cross-brace, flame
    kernel, hanging ring. Returns intensity 0..1 or 0."""
    x, y = px.fx, px.fy
    # hanging ring + hook
    if y == 2 and x in (7, 8):
        return 0.7
    if y == 3 and x in (6, 9):
        return 0.7
    # cage frame: rows 4 and 12, columns 5 and 10
    if y in (4, 12) and 5 <= x <= 10:
        return 0.9
    if x in (5, 10) and 4 <= y <= 12:
        return 0.9
    # inner flame kernel (hot)
    if 7 <= x <= 8 and 7 <= y <= 9:
        return 1.0
    if x in (6, 9) and y == 8:
        return 0.75
    return 0.0


def face_material(motif_fn, salt):
    """Albedo for an engraving plane: transparent except a 1px rim ring and the
    motif lines (dim verdigris inlay — the GLOW painter carries the light)."""
    def fn(px):
        d = _ring_dist(px)
        if d > 7.8:
            return None  # outside the coin silhouette
        if d >= 6.6:
            return mix(VERDIGRIS_DEEP, SILVER, 0.35)  # rim ring inlay
        m = motif_fn(px)
        if m > 0:
            return mix(VERDIGRIS_SHADOW, GLOW_TEAL, 0.25 + 0.2 * m)
        return None
    return fn


def face_glow(motif_fn, salt):
    """Glowmask for an engraving plane: STRONG rim ring + motif lines. Runs
    instead of the automatic glow_* albedo copy."""
    def fn(px):
        d = _ring_dist(px)
        if d > 7.8:
            return None
        if d >= 6.6:
            flicker = 200 + int(px.noise(salt) * 55)
            return with_alpha(mix(GLOW_TEAL, WHITE_VIOLET, 0.2), flicker)
        m = motif_fn(px)
        if m > 0:
            return with_alpha(mix(GLOW_TEAL, WHITE_VIOLET, 0.35 * m), int(120 + 110 * m))
        return None
    return fn


def coin_bronze(salt):
    """Verdigris coin metal: weathered bronze-green with silver wear on the
    face rims and dark pitting."""
    base_fn = metal(VERDIGRIS, salt=salt)

    def fn(px):
        col = base_fn(px)
        if px.noise(salt + 5) < 0.12:
            col = mix(col, VERDIGRIS_DEEP, 0.7)  # corrosion pit
        on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
        if on_rim and px.noise(salt + 9) > 0.55:
            col = mix(col, SILVER, 0.4)  # worn-through silver
        return col
    return fn


def boss_material(px):
    """Raised lantern boss: silvered dome with a teal-catching crown."""
    col = mul(SILVER, 0.85 + px.noise(61) * 0.3)
    if px.face == "up" or px.fy == 0:
        col = mix(col, GLOW_TEAL, 0.3)
    return mix(col, VERDIGRIS_DEEP, 0.25)


def boss_glow(px):
    """Faint teal crown light on the boss (highlight, not a lamp)."""
    if px.face != "up" and px.fy != 0:
        return None
    return with_alpha(GLOW_TEAL, 70)


def rim_band(px):
    """Emissive rim band: full-bright spectral teal with white-hot flecks."""
    col = mix(GLOW_TEAL, WHITE_VIOLET, 0.15)
    if px.noise(67) > 0.85:
        col = mix(col, WHITE_VIOLET, 0.6)
    return col


rim_band.shadeless = True


def obol_glyph(px):
    """Tiny orbiting obol: white-hot core, teal shell."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot(px.fx - cx, px.fy - cy)
    return mix(WHITE_VIOLET, GLOW_TEAL, min(1.0, d * 0.9))


obol_glyph.shadeless = True


def main():
    GEO.parent.mkdir(parents=True, exist_ok=True)
    GEO.write_text(json.dumps(build_geo(), indent=1) + "\n")
    ANIM.parent.mkdir(parents=True, exist_ok=True)
    ANIM.write_text(json.dumps(build_anim(), indent=1) + "\n")

    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("disc", coin_bronze(salt=11))
    painter.set_material("emboss", boss_material)
    painter.set_glow_painter("emboss", boss_glow)
    painter.set_material("glow_face_f", face_material(_barge_pixel, salt=17))
    painter.set_glow_painter("glow_face_f", face_glow(_barge_pixel, salt=17))
    painter.set_material("glow_face_b", face_material(_lantern_pixel, salt=19))
    painter.set_glow_painter("glow_face_b", face_glow(_lantern_pixel, salt=19))
    painter.set_material("glow_rim", rim_band)
    painter.set_material("glow_obol_*", obol_glyph)
    painter.paint(OUT)


if __name__ == "__main__":
    main()

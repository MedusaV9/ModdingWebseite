#!/usr/bin/env python3
"""WOAH-01 glitch-emitter texture generator (PLAN-01 §7, MC5 revision).

Procedurally renders the 64x64 GeckoLib canvas for ``geo/entity/glitch_emitter.geo.json``
— the ``tools/scare/gen_overlays.py`` school (seeded numpy noise + PIL, deterministic,
vanilla-pixel look, never AI-generated):

  entity/glitch_emitter.png           albedo: dark gunmetal with copper edging; the
                                      core cube, the antenna knob and the inner ring's
                                      seam in the toxic dome green (0.30/0.95/0.62).
  entity/glitch_emitter_glowmask.png  emissive layer (AutoGlowingGeoLayer): ONLY the
                                      core + knob + antenna-tip + inner-ring-seam
                                      pixels (copied from the albedo, slightly lifted),
                                      transparent everywhere else — the repo glowmask
                                      convention (EclipseGeoRenderer doc: "emissive
                                      pixels only, transparent elsewhere").

Every painted region is one cube's full box-UV footprint (the standard Bedrock face
layout, same strip order as ``scripts/geckolib_gen/validate_geo.py::box_uv_rects``), so
the UVs in the .geo.json resolve to finished pixels with zero bleed, and every cube size
is an INTEGER — no fractional UV rects, no sub-texel sampling. Uses value noise
quantized to a few shades per material plus per-face directional shading (top lifted,
bottom dropped — the P6 painter convention) — the vanilla 16x look at model resolution.

Atlas (64x64, all rects exclusive on the right/bottom edge):

  (0,0)   48x15  base plate   12x3x12      (48,0)   8x7   leg strut     2x5x2
  (56,0)  4x10   antenna mast 1x9x1        (48,10)  12x6  antenna knob  3x3x3  EMISSIVE
  (0,16)  16x19  pylon mast   4x15x4       (16,16)  24x12 core cube     6x6x6  EMISSIVE
  (40,16) 18x9   ring_outer   2x2x7        (16,28)  12x7  ring_inner    1x2x5  seam EMISSIVE

Usage:  python3 tools/woahdome/gen_glitch_emitter_textures.py
        (writes into src/main/resources/assets/eclipse/textures/entity/)
"""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

SIZE = 64
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..",
                       "src", "main", "resources", "assets", "eclipse", "textures", "entity")

RNG = np.random.default_rng(20260101)

# ---------------------------------------------------------------- palettes (RGB 0-255)

GUNMETAL = [(40, 44, 49), (52, 57, 62), (63, 69, 75), (74, 81, 88)]
GUNMETAL_DARK = [(30, 33, 37), (40, 44, 49), (50, 55, 60)]
COPPER = [(122, 68, 40), (156, 89, 49), (191, 111, 61), (214, 138, 82)]
COPPER_OXID = [(94, 122, 100), (114, 148, 120), (139, 173, 141)]
TOXIC = [(20, 92, 54), (38, 150, 90), (77, 242, 158), (150, 255, 205)]

# Per-face directional shading (P6 painter law: top lifted, bottom dropped, sides mid).
FACE_SHADE = {"up": 1.18, "down": 0.62, "east": 0.92, "west": 0.92,
              "north": 1.0, "south": 0.86}

canvas = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
glow = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)


def shade_fill(x0: int, y0: int, w: int, h: int, palette, weights=None,
               oxid_chance: float = 0.0) -> None:
    """Fill a rect with per-pixel quantized noise shades of ``palette`` (+ optional
    oxidized-copper speckle) — the chunky vanilla pixel read."""
    if w <= 0 or h <= 0:
        return
    weights = weights or [1.0] * len(palette)
    weights = np.asarray(weights, dtype=np.float64)
    weights /= weights.sum()
    idx = RNG.choice(len(palette), size=(h, w), p=weights)
    block = np.asarray([(*c, 255) for c in palette], dtype=np.uint8)[idx]
    if oxid_chance > 0.0:
        mask = RNG.random((h, w)) < oxid_chance
        oxid = np.asarray([(*c, 255) for c in COPPER_OXID], dtype=np.uint8)[
            RNG.choice(len(COPPER_OXID), size=(h, w))]
        block[mask] = oxid[mask]
    canvas[y0:y0 + h, x0:x0 + w] = block


def edge_frame(x0: int, y0: int, w: int, h: int, palette) -> None:
    """1-px frame in ``palette`` shades around a rect (copper edging / panel lines)."""
    if w <= 1 or h <= 1:
        return
    for x in range(x0, x0 + w):
        canvas[y0, x, :3] = palette[RNG.integers(1, len(palette))]
        canvas[y0 + h - 1, x, :3] = palette[RNG.integers(0, len(palette) - 1)]
    for y in range(y0, y0 + h):
        canvas[y, x0, :3] = palette[RNG.integers(1, len(palette))]
        canvas[y, x0 + w - 1, :3] = palette[RNG.integers(0, len(palette) - 1)]


def face_rects(u: int, v: int, sx: int, sy: int, sz: int):
    """Box-UV face rects of a cube at [u, v] — the validator's ``box_uv_rects`` strip
    order (row 1 = up/down, row 2 = east, north, west, south)."""
    return {
        "up": (u + sz, v, u + sz + sx, v + sz),
        "down": (u + sz + sx, v, u + sz + 2 * sx, v + sz),
        "east": (u, v + sz, u + sz, v + sz + sy),
        "north": (u + sz, v + sz, u + sz + sx, v + sz + sy),
        "west": (u + sz + sx, v + sz, u + 2 * sz + sx, v + sz + sy),
        "south": (u + 2 * sz + sx, v + sz, u + 2 * sz + 2 * sx, v + sz + sy),
    }


def box_footprint(u: int, v: int, sx: int, sy: int, sz: int):
    """The full Bedrock box-UV footprint rect of a cube at [u, v]."""
    return u, v, 2 * (sx + sz), sy + sz


def shade_faces(u: int, v: int, sx: int, sy: int, sz: int, strength: float = 1.0) -> None:
    """Multiply each face rect by its directional factor (eased by ``strength``)."""
    for face, (x0, y0, x1, y1) in face_rects(u, v, sx, sy, sz).items():
        factor = 1.0 + (FACE_SHADE[face] - 1.0) * strength
        block = canvas[y0:y1, x0:x1, :3].astype(np.float32) * factor
        canvas[y0:y1, x0:x1, :3] = np.clip(block, 0, 255).astype(np.uint8)


def paint_box(u, v, sx, sy, sz, palette, weights=None, oxid=0.0, frame=None,
              shade: float = 1.0):
    x0, y0, w, h = box_footprint(u, v, sx, sy, sz)
    shade_fill(x0, y0, w, h, palette, weights, oxid)
    if frame:
        # Frame each side face (the sy-tall band below the up/down row).
        for fx, fw in ((u, sz), (u + sz, sx), (u + sz + sx, sz), (u + 2 * sz + sx, sx)):
            edge_frame(fx, v + sz, fw, sy, frame)
    if shade > 0.0:
        shade_faces(u, v, sx, sy, sz, shade)


def emissive(u, v, sx, sy, sz, faces=None, rows=None) -> None:
    """Copy albedo pixels into the glowmask, lifted +40 (the repo's glow convention).

    ``faces``  — restrict to these face names (default: the whole footprint).
    ``rows``   — with ``faces``, only the first N pixel rows of each face rect.
    """
    if faces is None:
        x0, y0, w, h = box_footprint(u, v, sx, sy, sz)
        rects = [(x0, y0, x0 + w, y0 + h)]
    else:
        all_rects = face_rects(u, v, sx, sy, sz)
        rects = []
        for face in faces:
            x0, y0, x1, y1 = all_rects[face]
            rects.append((x0, y0, x1, min(y1, y0 + rows) if rows else y1))
    for x0, y0, x1, y1 in rects:
        region = canvas[y0:y1, x0:x1, :3].astype(np.int16)
        glow[y0:y1, x0:x1, :3] = np.clip(region + 40, 0, 255).astype(np.uint8)
        glow[y0:y1, x0:x1, 3] = 255


# ---------------------------------------------------------------- cube regions (§7 UVs)

# base plate [0,0] 12x3x12 — gunmetal deck, copper edging, oxidized speckle.
paint_box(0, 0, 12, 3, 12, GUNMETAL, [2, 3, 3, 1], oxid=0.06, frame=COPPER)
# legs [48,0] 2x5x2 — dark strut.
paint_box(48, 0, 2, 5, 2, GUNMETAL_DARK)
# antenna spike [56,0] 1x9x1 — gunmetal needle, two copper collars, emissive green tip
# band. Deliberately NOT GUNMETAL_DARK: the needle is only 1x1 px in cross-section and
# is the ONLY thing linking the glowing knob to the pylon, so near-black pixels make the
# knob read as a detached floating cube against a dark sky (caught in the UV playblast).
paint_box(56, 0, 1, 9, 1, GUNMETAL, [1, 3, 3, 1])
for _collar in (3, 6):
    shade_fill(56, 1 + _collar, 4, 1, COPPER, [1, 2, 2, 1])
shade_fill(56, 1, 4, 1, TOXIC, [0, 1, 2, 1])
# knob [48,10] 3x3x3 — toxic green emitter knob (EMISSIVE).
paint_box(48, 10, 3, 3, 3, TOXIC, [0.5, 2, 4, 2], shade=0.45)
# mast [0,16] 4x15x4 — gunmetal pylon, copper bands at thirds, one green seam.
paint_box(0, 16, 4, 15, 4, GUNMETAL, [1, 3, 3, 1])
for band_y in (16 + 4 + 3, 16 + 4 + 8, 16 + 4 + 13):
    shade_fill(0, band_y, 16, 1, COPPER, [1, 2, 2, 1], oxid_chance=0.15)
shade_fill(0, 16 + 4 + 10, 16, 1, TOXIC, [1, 2, 1, 0])
# core [16,16] 6x6x6 — the toxic green heart (EMISSIVE), dark green mottling.
paint_box(16, 16, 6, 6, 6, TOXIC, [1, 3, 4, 2], shade=0.45)
# Scanline-ish darker rows across the core so the glow reads animated even unlit.
cx0, cy0, cw, ch = box_footprint(16, 16, 6, 6, 6)
for row in range(cy0, cy0 + ch, 3):
    dim = canvas[row, cx0:cx0 + cw, :3].astype(np.int16)
    canvas[row, cx0:cx0 + cw, :3] = np.clip(dim - 36, 0, 255).astype(np.uint8)
# ring_outer chord [40,16] 2x2x7 — copper hoop arc, oxidized flecks. NO ``frame`` here:
# the long walls are only sy=2 px tall, so a 1-px edge frame covers 100% of them and
# turns the whole outer hoop patina-green instead of copper. The segment END caps
# (north/south, 2x2) get dark joint plates so the octagon reads as eight SEGMENTS, and
# each wall keeps a single oxidized wear line along its bottom edge.
paint_box(40, 16, 2, 2, 7, COPPER, [1, 2, 3, 2], oxid=0.10)
_outer = face_rects(40, 16, 2, 2, 7)
for _face in ("north", "south"):
    fx0, fy0, fx1, fy1 = _outer[_face]
    shade_fill(fx0, fy0, fx1 - fx0, fy1 - fy0, GUNMETAL_DARK)
for _face in ("east", "west"):
    fx0, fy0, fx1, fy1 = _outer[_face]
    shade_fill(fx0, fy1 - 1, fx1 - fx0, 1, COPPER_OXID)
# ring_inner chord [16,28] 1x2x5 — bright copper with a toxic seam on its upper edge
# (the up face + the top row of both long sides): the inner hoop is the only ring the
# eye can track inside the outer one, so it is the one that glows.
paint_box(16, 28, 1, 2, 5, COPPER, [0.5, 1.5, 3, 3], oxid=0.08)
_inner = face_rects(16, 28, 1, 2, 5)
for _face in ("up",):
    fx0, fy0, fx1, fy1 = _inner[_face]
    shade_fill(fx0, fy0, fx1 - fx0, fy1 - fy0, TOXIC, [0, 1, 3, 2])
for _face in ("east", "west"):
    fx0, fy0, fx1, _ = _inner[_face]
    shade_fill(fx0, fy0, fx1 - fx0, 1, TOXIC, [1, 2, 2, 0])

# ---------------------------------------------------------------- glowmask

emissive(16, 16, 6, 6, 6)                                   # core cube
emissive(48, 10, 3, 3, 3)                                   # antenna knob
emissive(56, 0, 1, 9, 1, faces=("east", "north", "west", "south"), rows=1)  # spike tip
emissive(16, 28, 1, 2, 5, faces=("up",))                    # inner-hoop seam (top face)
emissive(16, 28, 1, 2, 5, faces=("east", "west"), rows=1)   # inner-hoop seam (sides)


def save(arr: np.ndarray, name: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, name)
    Image.fromarray(arr, "RGBA").save(out)
    print(f"WROTE {os.path.relpath(out)}")


save(canvas, "glitch_emitter.png")
save(glow, "glitch_emitter_glowmask.png")

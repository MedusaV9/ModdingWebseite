#!/usr/bin/env python3
"""WOAH-01 glitch-emitter texture generator (PLAN-01 §7).

Procedurally renders the 128x128 GeckoLib canvas for ``geo/entity/glitch_emitter.geo.json``
— the ``tools/scare/gen_overlays.py`` school (seeded numpy noise + PIL, deterministic,
vanilla-pixel look, never AI-generated):

  entity/glitch_emitter.png           albedo: dark gunmetal with copper edging; the
                                      core cube and the antenna knob in the toxic
                                      dome green (0.30/0.95/0.62).
  entity/glitch_emitter_glowmask.png  emissive layer (AutoGlowingGeoLayer): ONLY the
                                      core + knob pixels (copied from the albedo,
                                      slightly lifted), transparent everywhere else —
                                      the repo glowmask convention (EclipseGeoRenderer
                                      doc: "emissive pixels only, transparent
                                      elsewhere").

Every painted region is one cube's full box-UV footprint (per-face shading via the
standard Bedrock face layout), so the UVs in the .geo.json resolve to finished pixels
with zero bleed. Uses value noise quantized to a few shades per material — the vanilla
16x-look at model resolution.

Usage:  python3 tools/woahdome/gen_glitch_emitter_textures.py
        (writes into src/main/resources/assets/eclipse/textures/entity/)
"""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

SIZE = 128
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..",
                       "src", "main", "resources", "assets", "eclipse", "textures", "entity")

RNG = np.random.default_rng(20260101)

# ---------------------------------------------------------------- palettes (RGB 0-255)

GUNMETAL = [(40, 44, 49), (52, 57, 62), (63, 69, 75), (74, 81, 88)]
GUNMETAL_DARK = [(30, 33, 37), (40, 44, 49), (50, 55, 60)]
COPPER = [(122, 68, 40), (156, 89, 49), (191, 111, 61), (214, 138, 82)]
COPPER_OXID = [(94, 122, 100), (114, 148, 120), (139, 173, 141)]
TOXIC = [(20, 92, 54), (38, 150, 90), (77, 242, 158), (150, 255, 205)]

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


def box_footprint(u: int, v: int, sx: float, sy: float, sz: float):
    """The full Bedrock box-UV footprint rect of a cube at [u, v] (sizes rounded up)."""
    sx, sy, sz = math.ceil(sx), math.ceil(sy), math.ceil(sz)
    return u, v, 2 * (sx + sz), sy + sz


def paint_box(u, v, sx, sy, sz, palette, weights=None, oxid=0.0, frame=None):
    x0, y0, w, h = box_footprint(u, v, sx, sy, sz)
    shade_fill(x0, y0, w, h, palette, weights, oxid)
    if frame:
        # Frame each side face (the sy-tall band below the top/bottom row).
        sxc, szc = math.ceil(sx), math.ceil(sz)
        syc = math.ceil(sy)
        for fx, fw in ((u, szc), (u + szc, sxc), (u + szc + sxc, szc),
                       (u + 2 * szc + sxc, sxc)):
            edge_frame(fx, v + szc, fw, syc, frame)


# ---------------------------------------------------------------- cube regions (§7 UVs)

# base plate [0,0] 12x3x12 — gunmetal deck, copper edging, oxidized speckle.
paint_box(0, 0, 12, 3, 12, GUNMETAL, [2, 3, 3, 1], oxid=0.06, frame=COPPER)
# legs [48,0] 2x5x2 — dark strut.
paint_box(48, 0, 2, 5, 2, GUNMETAL_DARK)
# antenna spike [56,0] 1x9x1 — dark needle with a bright tip row.
paint_box(56, 0, 1, 9, 1, GUNMETAL_DARK)
shade_fill(56, 1, 4, 1, TOXIC, [0, 1, 2, 1])
# mast [0,16] 4x15x4 — gunmetal pylon, copper bands at thirds, one green seam.
paint_box(0, 16, 4, 15, 4, GUNMETAL, [1, 3, 3, 1])
for band_y in (16 + 4 + 3, 16 + 4 + 8, 16 + 4 + 13):
    shade_fill(0, band_y, 16, 1, COPPER, [1, 2, 2, 1], oxid_chance=0.15)
shade_fill(0, 16 + 4 + 10, 16, 1, TOXIC, [1, 2, 1, 0])
# ring outer segment [32,16] 5x2x3 — copper, oxidized flecks.
paint_box(32, 16, 5, 2, 3, COPPER, [1, 2, 3, 2], oxid=0.10)
# knob [56,16] 3x3x3 — toxic green emitter knob (EMISSIVE).
paint_box(56, 16, 3, 3, 3, TOXIC, [0.5, 2, 4, 2])
# ring inner segment [32,24] 3.5x1.6x2 — bright copper.
paint_box(32, 24, 3.5, 1.6, 2, COPPER, [0.5, 1.5, 3, 3], oxid=0.08)
# core [0,40] 6x6x6 — the toxic green heart (EMISSIVE), dark green mottling.
paint_box(0, 40, 6, 6, 6, TOXIC, [1, 3, 4, 2])
# Scanline-ish darker rows across the core so the glow reads animated even unlit.
x0, y0, w, h = box_footprint(0, 40, 6, 6, 6)
for row in range(y0, y0 + h, 3):
    dim = canvas[row, x0:x0 + w, :3].astype(np.int16)
    canvas[row, x0:x0 + w, :3] = np.clip(dim - 36, 0, 255).astype(np.uint8)

# ---------------------------------------------------------------- glowmask (core + knob)

for (gu, gv, gsx, gsy, gsz) in ((0, 40, 6, 6, 6), (56, 16, 3, 3, 3)):
    x0, y0, w, h = box_footprint(gu, gv, gsx, gsy, gsz)
    region = canvas[y0:y0 + h, x0:x0 + w].astype(np.int16)
    lifted = np.clip(region[..., :3] + 40, 0, 255)
    glow[y0:y0 + h, x0:x0 + w, :3] = lifted.astype(np.uint8)
    glow[y0:y0 + h, x0:x0 + w, 3] = 255


def save(arr: np.ndarray, name: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, name)
    Image.fromarray(arr, "RGBA").save(out)
    print(f"WROTE {os.path.relpath(out)}")


save(canvas, "glitch_emitter.png")
save(glow, "glitch_emitter_glowmask.png")

#!/usr/bin/env python3
"""Shared painting helpers for the GLITCHED family (P6-W8 — glitched_husk/hound/tick).

Design language (plan §2.3 "glitched"): desaturated `#4A4A52`-family bodies with 1px
RGB-split fringes (`#FF3B6B` magenta / `#37F2E5` cyan) on cube edges; the `_alt.png`
flicker variant of every texture re-runs the SAME materials with ``alt=True``, which
adds hue-shifted magenta/cyan scanline bands and horizontal scanline-displacement
blocks so the renderer's 2–4 tick texture swap reads as a datamosh/corruption glitch
rather than a palette swap. Emissive: `glow_seam`/`glow_core` bones use the shadeless
:func:`seam` material; the magenta heart-core shining through torso cracks is a glow
painter (:func:`heart_glow`) stamped onto the body bone's glowmask.

Not a driver — imported by `glitched_husk.py` / `glitched_hound.py` /
`glitched_tick.py` (each still writes its own 4 PNGs deterministically).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import hexc, mix, mul, with_alpha  # noqa: E402

MAGENTA = hexc("#FF3B6B")
CYAN = hexc("#37F2E5")
WHITE = hexc("#F4F0FF")
HEART_CORE = hexc("#FF6BF2")
HEART_HALO = hexc("#C13BFF")


def glitch_body(base, salt=31, alt=False, tint=None):
    """Desaturated glitch flesh/hide with RGB-split edge fringes.

    ``alt=True`` = the flicker frame: scanline rows are horizontally displaced in
    blocks (noise re-sampled at a shifted x) and whole 2px bands hue-crush toward
    magenta/cyan. ``tint`` pre-mixes the base (used for displaced shard bones so the
    broken-off geometry reads corrupted even on the calm frame)."""
    if tint is not None:
        base = mix(base, tint, 0.14)

    def fn(px):
        gx = px.gx
        if alt:
            band = px.gy // 2
            roll = px.noise(salt + 9, x=band, y=0)
            if roll > 0.45:
                gx = px.gx + int(roll * 9.0) - 4  # displaced scanline block
        streak = px.noise(salt, x=gx, y=px.gy // 3)
        fine = px.noise(salt + 1, x=gx)
        col = mul(base, 1.0 + (0.7 * streak + 0.3 * fine - 0.5) * 0.34)
        if alt:
            band_t = px.noise(salt + 13, x=px.gy // 2, y=0)
            if band_t > 0.70:
                col = mix(col, MAGENTA, 0.42)
            elif band_t < 0.22:
                col = mix(col, CYAN, 0.38)
        edge_chance = 0.50 if alt else 0.82
        if px.fx == 0 and px.noise(salt + 3) > edge_chance:
            col = mix(col, CYAN, 0.65)
        elif px.fx == px.fw - 1 and px.noise(salt + 4) > edge_chance:
            col = mix(col, MAGENTA, 0.65)
        return col

    return fn


def seam(alt=False, salt=41):
    """Emissive seam-sliver material for `glow_*` bones: magenta/cyan interleave,
    white-hot flecks. Shadeless — these pixels are the chromatic edge the flicker
    renderer leans on, and they must survive Iris albedo-dimming."""

    def fn(px):
        t = px.noise(salt, x=px.gy // 2, y=0)
        col = mix(MAGENTA, CYAN, 0.15 if t < 0.55 else 0.85)
        if alt:
            col = mix(col, WHITE, 0.30)
        return mix(col, WHITE, 0.10 + px.noise(salt + 2) * 0.25)

    fn.shadeless = True
    return fn


def heart_glow(face="north", cy_frac=0.45, radius=0.34, salt=47, alt=False):
    """Glow painter: the magenta heart-core visible THROUGH cracks in the given face
    (hash-gated so it reads as shine-through, not a sticker)."""

    def fn(px):
        if px.face != face:
            return None
        nx = (px.fx + 0.5) / px.fw - 0.5
        ny = (px.fy + 0.5) / px.fh - cy_frac
        d = (nx * nx + ny * ny) ** 0.5
        if d > radius:
            return None
        if px.noise(salt) < (0.28 if alt else 0.40):
            return None  # the crack gate — most pixels stay dark
        col = mix(HEART_CORE, HEART_HALO, min(1.0, d / radius))
        return with_alpha(col, int(255 * (1.0 - 0.6 * d / radius)))

    return fn


def glow_eyes(pixels, color=CYAN, salt=53):
    """Glow painter for pinpoint eyes: ``pixels`` = [(face, fx, fy), ...]."""
    wanted = set(pixels)

    def fn(px):
        if (px.face, px.fx, px.fy) in wanted:
            return mix(color, WHITE, 0.35)
        return None

    return fn

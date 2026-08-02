#!/usr/bin/env python3
"""Generate the dedicated soft limbo fog sprites (F-107 part 2).

Produces two RGBA sprites for the non-additive limbo fog emitters:

* ``assets/eclipse/textures/particle/limbo_fog_soft.png`` (128x128) for
  ``eclipse:limbo_fog`` — a round, very soft radial fog puff with a gentle
  3-lobe angular waviness so a sheet never reads as a perfect ball.
* ``assets/eclipse/textures/particle/limbo_fogbank_soft.png`` (128x64) for
  ``eclipse:limbo_fogbank`` — a horizontally stretched 2:1 oval bank. The UV
  square always maps onto the full (square) billboard quad, so the 2:1 shape
  must live in UV space: the ellipse radius doubles the v axis, which flattens
  the on-quad silhouette to half the quad height (a bank hugging the horizon,
  not a giant ball). The halved pixel height just matches the halved payload.

Shared style with ``gen_limbo_godray_shaft.py`` (F-107 part 1):

* Gaussian falloff with a smoothstep edge kill forced to exactly 0 on every
  border texel — the quad border can never draw a visible sheet edge, even
  with Veil's nearest-neighbor quasar sampling (blur=false, mipmap=false).
* PRE-DARKENED violet baked into the RGB channels (core #8C69C8 -> fringe
  #5A3C96, both below half luminance — the same limbo violet family as the
  god-ray shaft): the JSON vertex tint multiplies on top, so llvmpipe and
  real GPUs agree and the sheets can never wash pale.
* Peak texture alpha stays below the old 8x8 ``purple_wisp.png`` center
  (189/255): with the JSON tint alphas (0.13 fog / 0.1 fogbank) one sheet
  peaks around 0.08 / 0.06 opacity and falls off radially instead of the
  wisp's blocky 8x8 plateau (3-4 blocks per texel on a 20+ block quad — the
  visible stair-steps this replaces).

Deterministic (pure math, no randomness): re-running the script reproduces
both PNGs byte-identically for a given Pillow version.

Usage (from the repo root):
    python3 tools/art/gen_limbo_fog_soft.py
"""

import math
from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)
DST_FOG = PARTICLE_DIR / "limbo_fog_soft.png"
DST_FOGBANK = PARTICLE_DIR / "limbo_fogbank_soft.png"

FOG_SIZE = (128, 128)
FOGBANK_SIZE = (128, 64)

# Pre-darkened violet ramp (sRGB 0-255), the F-107 god-ray shaft family: both
# ends deliberately BELOW half luminance — see module docstring.
CORE_RGB = (140, 105, 200)
FRINGE_RGB = (90, 60, 150)

# Gaussian sigma in normalized radius units (r in [0, 1] at the edge midpoint).
FOG_SIGMA = 0.42
FOGBANK_SIGMA = 0.45
# Peak alpha (0-1) at the sheet core (below the wisp's 0.74 — see docstring).
FOG_PEAK_ALPHA = 0.62
FOGBANK_PEAK_ALPHA = 0.58


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def shade(h: float, alpha: float) -> tuple[int, int, int, int]:
    """Fringe->core RGB ramp with the same falloff (pre-darkened tint)."""
    r = FRINGE_RGB[0] + (CORE_RGB[0] - FRINGE_RGB[0]) * h
    g = FRINGE_RGB[1] + (CORE_RGB[1] - FRINGE_RGB[1]) * h
    b = FRINGE_RGB[2] + (CORE_RGB[2] - FRINGE_RGB[2]) * h
    return (int(round(r)), int(round(g)), int(round(b)),
            int(round(alpha * 255.0)))


def build_fog() -> Image.Image:
    width, height = FOG_SIZE
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for y in range(height):
        ny = (y / (height - 1)) * 2.0 - 1.0
        for x in range(width):
            nx = (x / (width - 1)) * 2.0 - 1.0
            r = math.hypot(nx, ny)
            h = math.exp(-((r / FOG_SIGMA) ** 2))
            # Force exact zero on every border texel: r >= 1 there, so the
            # smoothstep argument clamps to 0 (no visible quad edge, ever).
            h *= smoothstep(0.0, 0.15, 1.0 - r)
            # Gentle 3-lobe angular waviness (radius-gated so the core stays
            # clean) — the puff must not read as a perfect ball.
            theta = math.atan2(ny, nx)
            wave = 1.0 - 0.05 * (0.5 + 0.5 * math.sin(3.0 * theta + 1.7)) \
                * smoothstep(0.2, 0.6, r)
            px[x, y] = shade(h, FOG_PEAK_ALPHA * h * wave)
    return img


def build_fogbank() -> Image.Image:
    width, height = FOGBANK_SIZE
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for y in range(height):
        ny = (y / (height - 1)) * 2.0 - 1.0
        for x in range(width):
            nx = (x / (width - 1)) * 2.0 - 1.0
            # 2:1 horizontal oval IN UV SPACE (v radius doubled): the square
            # quad then shows a bank half as tall as it is wide.
            r = math.hypot(nx, 2.0 * ny)
            h = math.exp(-((r / FOGBANK_SIGMA) ** 2))
            h *= smoothstep(0.0, 0.15, 1.0 - r)
            # Long-wave brightness variation along the bank so it does not
            # read as a uniform lens (the god-ray shaft's long-wave trick).
            wave = 1.0 - 0.06 * (0.5 + 0.5 * math.sin(nx * math.pi * 1.5 + 0.8)) \
                * smoothstep(0.15, 0.55, r)
            px[x, y] = shade(h, FOGBANK_PEAK_ALPHA * h * wave)
    return img


def main() -> None:
    build_fog().save(DST_FOG, optimize=True)
    print(f"wrote {DST_FOG} ({FOG_SIZE[0]}x{FOG_SIZE[1]})")
    build_fogbank().save(DST_FOGBANK, optimize=True)
    print(f"wrote {DST_FOGBANK} ({FOGBANK_SIZE[0]}x{FOGBANK_SIZE[1]})")


if __name__ == "__main__":
    main()

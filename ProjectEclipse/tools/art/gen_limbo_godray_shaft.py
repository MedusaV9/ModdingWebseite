#!/usr/bin/env python3
"""Generate the dedicated limbo god-ray shaft sprite (F-107).

Produces ``assets/eclipse/textures/particle/limbo_godray_shaft.png`` (64x256 RGBA),
a soft VERTICAL light shaft for the ``eclipse:limbo_godray`` Quasar emitter:

* Horizontal cross-section: Gaussian falloff around the center column (core ~25% of
  the quad width), forced to exactly 0 at the left/right texel columns so the quad
  border can never draw a visible sheet edge.
* Vertical envelope: smooth fade over the top/bottom ~22% (symmetric — Veil's quad
  UV vertical orientation is not part of the emitter contract), full plateau in the
  middle, plus a very gentle long-wave brightness variation so the shaft does not
  read as a uniform bar.
* PRE-DARKENED violet baked into the RGB channels (core #8C69C8 -> fringe #5A3C96):
  the darkness of the shaft does not hang on the JSON vertex tint alone, so llvmpipe
  and real GPUs agree — additive stacking of a few shafts can lift toward violet but
  never wash toward the old white-pink wall (the F-107 artifact).

Why not the old 8x8 ``purple_wisp.png``: Veil's quasar render type samples particle
textures with blur=false (nearest neighbor, see VeilRenderType QUASAR_PARTICLE), so a
tiny sprite stretched over a many-block quad shows its texel grid as hard stair-stepped
bands — exactly the reported artifact. 64x256 gives ~35 texels per block on a 7-block
shaft; nearest sampling stays smooth.

Deterministic (pure math, no randomness): re-running the script reproduces the PNG
byte-identically for a given Pillow version.

Usage (from the repo root):
    python3 tools/art/gen_limbo_godray_shaft.py
"""

import math
from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)
DST = PARTICLE_DIR / "limbo_godray_shaft.png"

WIDTH = 64
HEIGHT = 256

# Pre-darkened violet ramp (sRGB 0-255): core is a muted lavender, fringe leans darker
# and cooler. Both are deliberately BELOW half luminance — see module docstring.
CORE_RGB = (140, 105, 200)
FRINGE_RGB = (90, 60, 150)

# Horizontal Gaussian sigma in normalized half-width units (nx in [-1, 1]).
H_SIGMA = 0.34
# Vertical fade band as a fraction of texture height (each end).
V_FADE = 0.22
# Peak alpha (0-1) at the shaft core.
PEAK_ALPHA = 0.80


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def build() -> Image.Image:
    img = Image.new("RGBA", (WIDTH, HEIGHT))
    px = img.load()
    for y in range(HEIGHT):
        ny = y / (HEIGHT - 1)
        # Symmetric end fade + full plateau in the middle.
        v_env = smoothstep(0.0, V_FADE, ny) * smoothstep(0.0, V_FADE, 1.0 - ny)
        # Gentle long-wave variation (+-8%) so the shaft is not a uniform bar.
        v_env *= 0.92 + 0.08 * math.sin(ny * math.pi * 3.0)
        for x in range(WIDTH):
            nx = (x / (WIDTH - 1)) * 2.0 - 1.0
            h = math.exp(-((nx / H_SIGMA) ** 2))
            # Force exact zero on the outermost columns: a quad border must never
            # carry alpha (that is what draws hard sheet edges).
            h *= smoothstep(0.0, 0.12, 1.0 - abs(nx))
            a = PEAK_ALPHA * h * v_env
            # RGB ramps fringe->core with the same falloff (pre-darkened tint).
            r = FRINGE_RGB[0] + (CORE_RGB[0] - FRINGE_RGB[0]) * h
            g = FRINGE_RGB[1] + (CORE_RGB[1] - FRINGE_RGB[1]) * h
            b = FRINGE_RGB[2] + (CORE_RGB[2] - FRINGE_RGB[2]) * h
            px[x, y] = (int(round(r)), int(round(g)), int(round(b)),
                        int(round(a * 255.0)))
    return img


def main() -> None:
    build().save(DST, optimize=True)
    print(f"wrote {DST} ({WIDTH}x{HEIGHT})")


if __name__ == "__main__":
    main()
